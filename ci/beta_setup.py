"""Sets up external TestFlight testing for iLife via the App Store Connect API.

Fills Test Information + Beta Review contact, creates an external group with a public link,
adds the newest build, submits it to Beta App Review and prints the public link.
Personal contact details come from masked workflow inputs — never committed.
"""
import os, sys, time, json, jwt, requests

BUNDLE = "com.jondhale.ilife"
API = "https://api.appstoreconnect.apple.com/v1"
E = os.environ

def token():
    key = open(E["ASC_KEY_PATH"]).read()
    now = int(time.time())
    return jwt.encode({"iss": E["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": E["ASC_KEY_ID"], "typ": "JWT"})

H = {"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}

def call(method, path, body=None, ok=(200, 201, 204)):
    r = requests.request(method, API + path if path.startswith("/") else path, headers=H, data=json.dumps(body) if body else None)
    if r.status_code not in ok:
        print(f"::warning title={method} {path.split('?')[0]}::{r.status_code} {r.text[:600]}")
        return None
    return r.json() if r.text else {}

def note(t, m): print(f"::notice title={t}::{m}")

app = call("GET", f"/apps?filter[bundleId]={BUNDLE}")["data"][0]
aid = app["id"]
note("app", f"{app['attributes']['name']} ({aid})")

# 1) Test information (beta app localization)
info = {"description": E["DESCRIPTION"], "feedbackEmail": E["EMAIL"], "privacyPolicyUrl": E["PRIVACY_URL"], "marketingUrl": E["PRIVACY_URL"]}
locs = call("GET", f"/apps/{aid}/betaAppLocalizations")["data"]
en = next((l for l in locs if l["attributes"]["locale"].startswith("en")), None)
if en:
    call("PATCH", f"/betaAppLocalizations/{en['id']}", {"data": {"type": "betaAppLocalizations", "id": en["id"], "attributes": info}})
else:
    call("POST", "/betaAppLocalizations", {"data": {"type": "betaAppLocalizations", "attributes": {"locale": "en-US", **info},
          "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}})
note("test info", "description, feedback email and privacy policy set")

# 2) Beta review contact
rd = call("GET", f"/apps/{aid}/betaAppReviewDetail")["data"]
call("PATCH", f"/betaAppReviewDetails/{rd['id']}", {"data": {"type": "betaAppReviewDetails", "id": rd["id"], "attributes": {
    "contactFirstName": E["FIRST"], "contactLastName": E["LAST"], "contactPhone": E["PHONE"], "contactEmail": E["EMAIL"],
    "demoAccountRequired": False, "notes": E["REVIEW_NOTES"]}}})
note("review contact", "contact details set")

# 3) Newest processed build
build = None
for _ in range(30):
    vf = f"&filter[preReleaseVersion.version]={E['BUILD_VERSION']}" if E.get("BUILD_VERSION") else ""
    b = call("GET", f"/builds?filter[app]={aid}{vf}&sort=-uploadedDate&limit=1&include=preReleaseVersion")
    if b and b["data"]:
        build = b["data"][0]
        if build["attributes"]["processingState"] == "VALID": break
    print("Build not ready yet…"); time.sleep(30)
if not build or build["attributes"]["processingState"] != "VALID":
    print("::error title=build::No processed build found"); sys.exit(1)
ver = next((x["attributes"]["version"] for x in b.get("included", []) if x["type"] == "preReleaseVersions"), "?")
bid = build["id"]
note("build", f"{ver} ({build['attributes']['version']}) — {bid}")

# What to test
bl = call("GET", f"/builds/{bid}/betaBuildLocalizations")["data"]
if bl:
    call("PATCH", f"/betaBuildLocalizations/{bl[0]['id']}", {"data": {"type": "betaBuildLocalizations", "id": bl[0]["id"], "attributes": {"whatsNew": E["WHATS_NEW"]}}})
else:
    call("POST", "/betaBuildLocalizations", {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": E["WHATS_NEW"]},
          "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})

# 4) External group with public link
limit = int(E.get("LIMIT", "4"))
groups = call("GET", f"/apps/{aid}/betaGroups?limit=200")["data"]
# Close old links (people already in those groups keep their access only if CLOSE_OLD isn't set).
for old in [x.strip() for x in E.get("CLOSE_OLD", "").split(",") if x.strip()]:
    og = next((x for x in groups if x["attributes"]["name"] == old), None)
    if og and og["attributes"].get("publicLinkEnabled"):
        call("PATCH", f"/betaGroups/{og['id']}", {"data": {"type": "betaGroups", "id": og["id"], "attributes": {"publicLinkEnabled": False}}})
        note("closed", f"public link of '{old}' switched off")
g = next((x for x in groups if x["attributes"]["name"] == E["GROUP"]), None)
attrs = {"publicLinkEnabled": True, "publicLinkLimitEnabled": True, "publicLinkLimit": limit, "feedbackEnabled": True}
if g:
    g = call("PATCH", f"/betaGroups/{g['id']}", {"data": {"type": "betaGroups", "id": g["id"], "attributes": attrs}})["data"]
else:
    g = call("POST", "/betaGroups", {"data": {"type": "betaGroups", "attributes": {"name": E["GROUP"], **attrs},
              "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}})["data"]
gid = g["id"]
note("group", f"{E['GROUP']} (external, public link limit {limit})")

# 5) Add build to group (and take older builds out of it, so new testers get this one)
call("POST", f"/betaGroups/{gid}/relationships/builds", {"data": [{"type": "builds", "id": bid}]})
others = [x["id"] for x in (call("GET", f"/betaGroups/{gid}/builds?limit=50") or {}).get("data", []) if x["id"] != bid]
if others:
    call("DELETE", f"/betaGroups/{gid}/relationships/builds", {"data": [{"type": "builds", "id": o} for o in others]})
    note("group", f"removed {len(others)} older build(s) from the group")

# 6) Submit for Beta App Review (409 = already submitted / approved)
st = call("GET", f"/builds/{bid}/buildBetaDetail")
sub = call("POST", "/betaAppReviewSubmissions", {"data": {"type": "betaAppReviewSubmissions",
            "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}}, ok=(200, 201, 409))
d = call("GET", f"/builds/{bid}/buildBetaDetail")
if d: note("review", f"external state: {d['data']['attributes'].get('externalBuildState')}")

# 7) Public link
g = call("GET", f"/betaGroups/{gid}")["data"]
link = g["attributes"].get("publicLink")
note("PUBLIC LINK", link or "not generated yet")
print("PUBLIC_LINK=" + str(link))
