import UIKit
import PhotosUI
import VisionKit
import QuickLook
import UniformTypeIdentifiers

/// Opens the camera, photo library, document scanner, Files and previews directly with UIKit,
/// on top of whatever is showing. Unlike SwiftUI `.sheet`/`.fullScreenCover` modifiers this works the
/// same at any depth (a sheet inside a sheet inside a list) and can never close the screens underneath.
@MainActor
enum Presenter {
    /// Keeps the delegate alive while its picker is on screen.
    private static var keep: NSObject?

    static func top() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var vc = window?.rootViewController
        while let next = vc?.presentedViewController, !next.isBeingDismissed { vc = next }
        return vc
    }

    private static func show(_ vc: UIViewController) {
        guard let top = top() else { return }
        // A popover-style presentation needs an anchor on iPad.
        if let pop = vc.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        top.present(vc, animated: true)
    }

    static var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    // MARK: Camera (photo)

    static func camera(front: Bool = false, _ done: @escaping (UIImage) -> Void) {
        guard hasCamera else { return }
        let d = CameraDelegate { info in
            if let img = info[.originalImage] as? UIImage { done(img) }
        }
        let vc = UIImagePickerController()
        vc.sourceType = .camera
        vc.cameraDevice = front && UIImagePickerController.isCameraDeviceAvailable(.front) ? .front : .rear
        vc.delegate = d
        vc.modalPresentationStyle = .fullScreen
        keep = d
        show(vc)
    }

    // MARK: Camera (video)

    static func videoCamera(front: Bool = true, maxSeconds: Double = 30, _ done: @escaping (URL) -> Void) {
        guard hasCamera else { return }
        let d = CameraDelegate { info in
            if let url = info[.mediaURL] as? URL { done(url) }
        }
        let vc = UIImagePickerController()
        vc.sourceType = .camera
        vc.mediaTypes = [UTType.movie.identifier]
        vc.cameraCaptureMode = .video
        vc.videoMaximumDuration = maxSeconds
        vc.videoQuality = .typeHigh
        vc.cameraDevice = front && UIImagePickerController.isCameraDeviceAvailable(.front) ? .front : .rear
        vc.delegate = d
        vc.modalPresentationStyle = .fullScreen
        keep = d
        show(vc)
    }

    // MARK: Photo library

    /// One picture from the library.
    static func photoLibrary(_ done: @escaping (UIImage) -> Void) {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let d = LibraryDelegate { results in
            guard let p = results.first?.itemProvider else { return }
            if p.canLoadObject(ofClass: UIImage.self) {
                p.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let img = obj as? UIImage { Task { @MainActor in done(img) } }
                }
            } else {
                // HEIC/RAW variants: fall back to the raw data.
                p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data, let img = UIImage(data: data) { Task { @MainActor in done(img) } }
                }
            }
        }
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = d
        keep = d
        show(vc)
    }

    /// One video from the library, copied to a temporary file.
    static func videoLibrary(_ done: @escaping (URL?) -> Void) {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let d = LibraryDelegate { results in
            guard let p = results.first?.itemProvider else { return }
            p.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                var copy: URL?
                if let url {
                    let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension.isEmpty ? "mov" : url.pathExtension)
                    if (try? FileManager.default.copyItem(at: url, to: dest)) != nil { copy = dest }
                }
                Task { @MainActor in done(copy) }
            }
        }
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = d
        keep = d
        show(vc)
    }

    /// The raw data of one picture (keeps GIF animation intact).
    static func imageData(_ done: @escaping (Data?) -> Void) {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let d = LibraryDelegate { results in
            guard let p = results.first?.itemProvider else { return }
            let type = p.hasItemConformingToTypeIdentifier(UTType.gif.identifier) ? UTType.gif : UTType.image
            p.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in Task { @MainActor in done(data) } }
        }
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = d
        keep = d
        show(vc)
    }

    // MARK: Document scanner

    static var canScan: Bool { VNDocumentCameraViewController.isSupported }

    static func scan(_ done: @escaping ([UIImage]) -> Void) {
        guard canScan else { return }
        let d = ScanDelegate(done: done)
        let vc = VNDocumentCameraViewController()
        vc.delegate = d
        vc.modalPresentationStyle = .fullScreen
        keep = d
        show(vc)
    }

    // MARK: Files

    /// Copies the chosen file into the app, so no security-scoped access is needed afterwards.
    static func file(types: [UTType], _ done: @escaping (URL) -> Void) {
        let d = FileDelegate(done: done)
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        vc.allowsMultipleSelection = false
        vc.delegate = d
        keep = d
        show(vc)
    }

    // MARK: Preview (PDF / image)

    static func preview(_ url: URL) {
        let d = PreviewSource(url: url)
        let vc = QLPreviewController()
        vc.dataSource = d
        keep = d
        show(vc)
    }

    /// Writes data to a temporary file and previews it.
    static func preview(data: Data, name: String, ext: String) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("preview", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(Exporter.safe(name.isEmpty ? "File" : name) + "." + ext)
        try? data.write(to: url, options: .completeFileProtection)
        preview(url)
    }

    // MARK: Delegates

    private final class CameraDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: ([UIImagePickerController.InfoKey: Any]) -> Void
        init(done: @escaping ([UIImagePickerController.InfoKey: Any]) -> Void) { self.done = done }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            done(info)
            Task { @MainActor in Presenter.keep = nil }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            Task { @MainActor in Presenter.keep = nil }
        }
    }

    private final class LibraryDelegate: NSObject, PHPickerViewControllerDelegate {
        let done: ([PHPickerResult]) -> Void
        init(done: @escaping ([PHPickerResult]) -> Void) { self.done = done }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            done(results)
            Task { @MainActor in Presenter.keep = nil }
        }
    }

    private final class ScanDelegate: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: ([UIImage]) -> Void
        init(done: @escaping ([UIImage]) -> Void) { self.done = done }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            controller.dismiss(animated: true)
            done(pages)
            Task { @MainActor in Presenter.keep = nil }
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
            Task { @MainActor in Presenter.keep = nil }
        }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true)
            Task { @MainActor in Presenter.keep = nil }
        }
    }

    private final class FileDelegate: NSObject, UIDocumentPickerDelegate {
        let done: (URL) -> Void
        init(done: @escaping (URL) -> Void) { self.done = done }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let u = urls.first { done(u) }
            Task { @MainActor in Presenter.keep = nil }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            Task { @MainActor in Presenter.keep = nil }
        }
    }

    private final class PreviewSource: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewItem(at index: Int) -> QLPreviewItem { url as NSURL }
    }
}
