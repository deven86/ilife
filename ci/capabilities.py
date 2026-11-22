"""Turns on App ID capabilities through the App Store Connect API (fastlane's way is refused)."""
import os, time, json, jwt, requests
E = os.environ; API = "https://api.appstoreconnect.apple.com/v1"
k = open(E["ASC_KEY_PATH"]).read(); n = int(time.time())
T = jwt.encode({"iss": E["ASC_ISSUER_ID"], "iat": n, "exp": n + 1100, "aud": "appstoreconnect-v1"}, k, algorithm="ES256", headers={"kid": E["ASC_KEY_ID"], "typ": "JWT"})
H = {"Authorization": f"Bearer {T}", "Content-Type": "application/json"}
def call(m, p, body=None):
    r = requests.request(m, API + p, headers=H, data=json.dumps(body) if body else None)
    if not r.ok: print(f"::warning title={m} {p.split('?')[0]}::{r.status_code} {r.text[:400]}"); return None
    return r.json() if r.text else {}
WANT = {
    "APPLE_ID_AUTH": [{"key": "APPLE_ID_AUTH_APP_CONSENT", "options": [{"key": "PRIMARY_APP_CONSENT"}]}],
    "ICLOUD": [{"key": "ICLOUD_VERSION", "options": [{"key": "XCODE_6"}]}],
    "PUSH_NOTIFICATIONS": None, "HEALTHKIT": None, "APP_GROUPS": None,
}
b = call("GET", "/bundleIds?filter[identifier]=com.jondhale.ilife")
bid = next(x["id"] for x in b["data"] if x["attributes"]["identifier"] == "com.jondhale.ilife")
have = {c["attributes"]["capabilityType"] for c in (call("GET", f"/bundleIds/{bid}/bundleIdCapabilities") or {}).get("data", [])}
print("::notice title=Before::" + ", ".join(sorted(have)))
for cap, settings in WANT.items():
    if cap in have: continue
    attrs = {"capabilityType": cap}
    if settings: attrs["settings"] = settings
    if call("POST", "/bundleIdCapabilities", {"data": {"type": "bundleIdCapabilities", "attributes": attrs,
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}}}}) is not None:
        print(f"::notice title=Enabled::{cap}")
have = {c["attributes"]["capabilityType"] for c in (call("GET", f"/bundleIds/{bid}/bundleIdCapabilities") or {}).get("data", [])}
print("::notice title=After::" + ", ".join(sorted(have)))
