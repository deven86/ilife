"""Prints App Store + TestFlight status for iLife (read-only)."""
import os, time, json, jwt, requests
E = os.environ; API = "https://api.appstoreconnect.apple.com/v1"
k = open(E["ASC_KEY_PATH"]).read(); n = int(time.time())
T = jwt.encode({"iss": E["ASC_ISSUER_ID"], "iat": n, "exp": n + 1100, "aud": "appstoreconnect-v1"}, k, algorithm="ES256", headers={"kid": E["ASC_KEY_ID"], "typ": "JWT"})
def get(p):
    r = requests.get(API + p, headers={"Authorization": f"Bearer {T}"}); return r.json() if r.ok else {"error": r.status_code, "body": r.text[:300]}
aid = get("/apps?filter[bundleId]=com.jondhale.ilife")["data"][0]["id"]
for v in get(f"/apps/{aid}/appStoreVersions?limit=5")["data"]:
    print("::notice title=App Store::", v["attributes"]["versionString"], v["attributes"]["appStoreState"])
for g in get(f"/apps/{aid}/betaGroups?limit=50")["data"]:
    a = g["attributes"]; print("::notice title=Group::", a["name"], "internal" if a["isInternalGroup"] else "external", "publicLink:", a.get("publicLinkEnabled"), a.get("publicLink"))
for b in get(f"/builds?filter[app]={aid}&sort=-uploadedDate&limit=4&include=buildBetaDetail,preReleaseVersion")["data"]:
    d = get(f"/builds/{b['id']}/buildBetaDetail")["data"]["attributes"]
    print("::notice title=Build::", b["attributes"]["version"], b["attributes"]["processingState"], "external:", d.get("externalBuildState"), "internal:", d.get("internalBuildState"))
for c in get(f"/bundleIds?filter[identifier]=com.jondhale.ilife&include=bundleIdCapabilities").get("included", []):
    print("::notice title=Capability::", c["attributes"]["capabilityType"])
