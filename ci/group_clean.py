"""Removes every build from a TestFlight group except builds of KEEP_VERSION."""
import os, time, json, jwt, requests
E = os.environ; API = "https://api.appstoreconnect.apple.com/v1"
k = open(E["ASC_KEY_PATH"]).read(); n = int(time.time())
T = jwt.encode({"iss": E["ASC_ISSUER_ID"], "iat": n, "exp": n + 1100, "aud": "appstoreconnect-v1"}, k, algorithm="ES256", headers={"kid": E["ASC_KEY_ID"], "typ": "JWT"})
H = {"Authorization": f"Bearer {T}", "Content-Type": "application/json"}
aid = requests.get(API + "/apps?filter[bundleId]=com.jondhale.ilife", headers=H).json()["data"][0]["id"]
g = next(x for x in requests.get(API + f"/apps/{aid}/betaGroups?limit=50", headers=H).json()["data"] if x["attributes"]["name"] == E["GROUP"])
builds = requests.get(API + f"/betaGroups/{g['id']}/builds?limit=50&include=preReleaseVersion", headers=H).json()
ver = {x["id"]: x["attributes"]["version"] for x in builds.get("included", []) if x["type"] == "preReleaseVersions"}
drop = [b["id"] for b in builds["data"] if ver.get(b["relationships"]["preReleaseVersion"]["data"]["id"]) != E.get("KEEP_VERSION")]
if drop:
    r = requests.delete(API + f"/betaGroups/{g['id']}/relationships/builds", headers=H, data=json.dumps({"data": [{"type": "builds", "id": i} for i in drop]}))
    print(f"::notice title=group::removed {len(drop)} build(s) from {E['GROUP']} (HTTP {r.status_code})")
else:
    print("::notice title=group::nothing to remove")
