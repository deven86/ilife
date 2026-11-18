"""Submits the prepared iLife App Store version for App Review (reuses an open draft submission)."""
import os, time, json, jwt, requests
E = os.environ; API = "https://api.appstoreconnect.apple.com/v1"
def tok():
    k = open(E["ASC_KEY_PATH"]).read(); n = int(time.time())
    return jwt.encode({"iss": E["ASC_ISSUER_ID"], "iat": n, "exp": n + 1100, "aud": "appstoreconnect-v1"}, k, algorithm="ES256", headers={"kid": E["ASC_KEY_ID"], "typ": "JWT"})
def call(m, p, body=None, ok=(200, 201, 204)):
    r = requests.request(m, API + p, headers={"Authorization": f"Bearer {tok()}", "Content-Type": "application/json"}, data=json.dumps(body) if body else None)
    if r.status_code not in ok:
        print(f"::error title={m} {p.split('?')[0]}::{r.status_code}"); print(r.text[:3000]); return None
    return r.json() if r.text else {}
aid = call("GET", "/apps?filter[bundleId]=com.jondhale.ilife")["data"][0]["id"]
v = next(x for x in call("GET", f"/apps/{aid}/appStoreVersions?filter[platform]=IOS")["data"] if x["attributes"]["versionString"] == E["VERSION"])
vid = v["id"]; print("version state:", v["attributes"]["appStoreState"])
subs = call("GET", f"/reviewSubmissions?filter[app]={aid}&filter[platform]=IOS&filter[state]=READY_FOR_REVIEW")["data"]
sid = subs[0]["id"] if subs else call("POST", "/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
      "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}})["data"]["id"]
items = call("GET", f"/reviewSubmissions/{sid}/items")["data"]
if not items:
    if call("POST", "/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}}) is None: raise SystemExit(1)
if call("PATCH", f"/reviewSubmissions/{sid}", {"data": {"type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}}) is None: raise SystemExit(1)
time.sleep(5)
print("::notice title=SUBMITTED::" + call("GET", f"/appStoreVersions/{vid}")["data"]["attributes"]["appStoreState"])
