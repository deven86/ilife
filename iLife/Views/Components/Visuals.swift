import SwiftUI
import PhotosUI
import UIKit

// MARK: - Image helpers

enum ImageTools {
    /// Downscale + JPEG so photos stay small in iCloud.
    static func jpeg(_ image: UIImage, maxSide: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        resized(image, maxSide: maxSide).jpegData(compressionQuality: quality)
    }

    static func thumbnail(_ image: UIImage) -> Data? { jpeg(image, maxSide: 400, quality: 0.7) }

    static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

// MARK: - Built-in illustrations (used until you add your own photo)

struct Illustration {
    let symbol: String
    let colors: [Color]

    static func exercise(_ name: String, equipment: String = "") -> Illustration {
        let n = (name + " " + equipment).lowercased()
        func has(_ words: String...) -> Bool { words.contains { n.contains($0) } }
        if has("run", "jog", "treadmill", "high knees") { return .init(symbol: "figure.run", colors: [.orange, .red]) }
        if has("cycle", "bike", "cycling", "spin") { return .init(symbol: "figure.indoor.cycle", colors: [.yellow, .orange]) }
        if has("row") && has("machine", "erg") { return .init(symbol: "figure.rower", colors: [.teal, .blue]) }
        if has("yoga", "salutation", "warrior", "triangle", "dog", "savasana", "pose") { return .init(symbol: "figure.yoga", colors: [.purple, .pink]) }
        if has("stretch", "mobility", "foam") { return .init(symbol: "figure.flexibility", colors: [.mint, .teal]) }
        if has("plank", "crunch", "core", "sit-up", "abs", "mountain climber") { return .init(symbol: "figure.core.training", colors: [.pink, .purple]) }
        if has("burpee", "jump", "hiit", "jumping") { return .init(symbol: "figure.highintensity.intervaltraining", colors: [.red, .orange]) }
        if has("kettlebell", "swing") { return .init(symbol: "figure.cross.training", colors: [.orange, .brown]) }
        if has("squat", "lunge", "leg press", "leg curl", "leg extension", "calf", "deadlift", "rdl") { return .init(symbol: "figure.strengthtraining.functional", colors: [.green, .teal]) }
        if has("pull-up", "pull up", "chin", "pulldown", "row", "face pull") { return .init(symbol: "figure.strengthtraining.traditional", colors: [.blue, .indigo]) }
        if has("bench", "press", "push-up", "push up", "dip", "fly", "raise") { return .init(symbol: "dumbbell.fill", colors: [.cyan, .blue]) }
        if has("curl", "tricep", "bicep", "pushdown", "extension") { return .init(symbol: "dumbbell.fill", colors: [.indigo, .purple]) }
        if has("walk", "lunges") { return .init(symbol: "figure.walk", colors: [.green, .mint]) }
        if has("swim") { return .init(symbol: "figure.pool.swim", colors: [.cyan, .blue]) }
        if has("rest") { return .init(symbol: "pause.circle.fill", colors: [.gray, .secondary]) }
        return .init(symbol: "figure.mixed.cardio", colors: [.cyan, .teal])
    }

    static func food(_ name: String) -> Illustration {
        let n = name.lowercased()
        func has(_ words: String...) -> Bool { words.contains { n.contains($0) } }
        if has("coffee") { return .init(symbol: "cup.and.saucer.fill", colors: [.brown, .black]) }
        if has("tea", "chai") { return .init(symbol: "mug.fill", colors: [.orange, .brown]) }
        if has("water", "lemon", "coconut water") { return .init(symbol: "drop.fill", colors: [.cyan, .blue]) }
        if has("milk", "shake", "whey", "protein", "lassi", "smoothie") { return .init(symbol: "takeoutbag.and.cup.and.straw.fill", colors: [.white.opacity(0.7), .cyan]) }
        if has("juice") { return .init(symbol: "wineglass.fill", colors: [.orange, .yellow]) }
        if has("egg") { return .init(symbol: "oval.portrait.fill", colors: [.yellow, .orange]) }
        if has("chicken", "fish", "mutton", "meat", "prawn") { return .init(symbol: "fish.fill", colors: [.orange, .red]) }
        if has("banana", "apple", "fruit", "mango", "papaya", "orange", "grape") { return .init(symbol: "apple.logo", colors: [.red, .pink]) }
        if has("salad", "sprout", "sabzi", "vegetable", "veg") { return .init(symbol: "leaf.fill", colors: [.green, .mint]) }
        if has("almond", "nut", "cashew", "walnut", "seed") { return .init(symbol: "circle.hexagongrid.fill", colors: [.brown, .orange]) }
        if has("rice", "biryani", "pulao", "poha", "upma", "oats") { return .init(symbol: "takeoutbag.and.cup.and.straw", colors: [.yellow, .white.opacity(0.6)]) }
        if has("roti", "chapati", "dosa", "idli", "paratha", "bread", "toast") { return .init(symbol: "circle.circle.fill", colors: [.orange, .yellow]) }
        if has("dal", "curd", "dahi", "paneer", "soup") { return .init(symbol: "takeoutbag.and.cup.and.straw.fill", colors: [.yellow, .orange]) }
        return .init(symbol: "fork.knife", colors: [.teal, .cyan])
    }
}

/// Square tile: your photo if you added one, otherwise a built-in illustration.
struct ItemThumbnail: View {
    let photo: Data?
    let illustration: Illustration
    var size: CGFloat = 52
    var corner: CGFloat = 12

    var body: some View {
        Group {
            if let photo, let img = UIImage(data: photo) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: illustration.colors.map { $0.opacity(0.85) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: illustration.symbol)
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(.white.opacity(0.2)))
    }
}

// MARK: - Photo picker: camera or library

struct PhotoSourceButton<Label: View>: View {
    let onPick: (UIImage) -> Void
    @ViewBuilder var label: Label

    @State private var showMenu = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var item: PhotosPickerItem?

    var body: some View {
        Button { showMenu = true } label: { label }
            .confirmationDialog("Add photo", isPresented: $showMenu) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") { showCamera = true }
                }
                Button("Choose from Library") { showLibrary = true }
            }
            .photosPicker(isPresented: $showLibrary, selection: $item, matching: .images)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in
                    showCamera = false
                    if let img { onPick(img) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: item) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let d = try? await newItem.loadTransferable(type: Data.self), let img = UIImage(data: d) { onPick(img) }
                    item = nil
                }
            }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var device: UIImagePickerController.CameraDevice = .rear
    let onFinish: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = .camera
        vc.cameraDevice = UIImagePickerController.isCameraDeviceAvailable(device) ? device : .rear
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}

/// Round profile picture with initials fallback.
struct AvatarView: View {
    let data: Data?
    let name: String
    var size: CGFloat = 48
    var body: some View {
        Group {
            if let data, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(initials).font(.system(size: size * 0.38, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2))
        .shadow(color: .black.opacity(0.25), radius: 4)
    }
    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap { $0.first.map(String.init) }.joined()
        return s.isEmpty ? "?" : s.uppercased()
    }
}
