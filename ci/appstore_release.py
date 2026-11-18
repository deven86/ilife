"""Prepares (and optionally submits) the iLife App Store release via the App Store Connect API.

Steps: version + build, store text, categories, age rating, review contact, screenshots,
free price, worldwide availability (except China mainland, which needs an ICP filing),
then — if SUBMIT=yes — submits for App Review.
Personal contact details come from masked workflow inputs, never from the repo.
"""
import os, sys, time, json, glob, hashlib, jwt, requests

E = os.environ
API = "https://api.appstoreconnect.apple.com"
BUNDLE = "com.jondhale.ilife"
VERSION = E["VERSION"]

def tok():
    k = open(E["ASC_KEY_PATH"]).read(); n = int(time.time())
    return jwt.encode({"iss": E["ASC_ISSUER_ID"], "iat": n, "exp": n + 1100, "aud": "appstoreconnect-v1"}, k,
                      algorithm="ES256", headers={"kid": E["ASC_KEY_ID"], "typ": "JWT"})

S = requests.Session()
def H(): return {"Authorization": f"Bearer {tok()}", "Content-Type": "application/json"}
problems = []

def call(m, path, body=None, ok=(200, 201, 204), quiet=False):
    url = path if path.startswith("http") else API + (path if path.startswith("/v") else "/v1" + path)
    r = S.request(m, url, headers=H(), data=json.dumps(body) if body is not None else None)
    if r.status_code not in ok:
        msg = f"{m} {path.split('?')[0]} → {r.status_code}: {r.text[:700]}"
        if not quiet: print("::warning title=api::" + msg); problems.append(msg)
        return None
    return r.json() if r.text else {}

def note(t, m): print(f"::notice title={t}::{m}")

def text(name): return open(f"appstore/{name}.txt").read().strip()

app = call("GET", f"/apps?filter[bundleId]={BUNDLE}")["data"][0]; aid = app["id"]
note("app", f"{app['attributes']['name']} ({aid})")

# Content rights: no third-party content
call("PATCH", f"/apps/{aid}", {"data": {"type": "apps", "id": aid, "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})

# ---------- App info: categories, name/subtitle/privacy URL, age rating ----------
infos = call("GET", f"/apps/{aid}/appInfos")["data"]
editable = [i for i in infos if i["attributes"].get("appStoreState") not in ("READY_FOR_SALE", "REPLACED_WITH_NEW_INFO")
            and i["attributes"].get("state") not in ("READY_FOR_DISTRIBUTION",)] or infos
info = editable[0]; iid = info["id"]
call("PATCH", f"/appInfos/{iid}", {"data": {"type": "appInfos", "id": iid, "relationships": {
    "primaryCategory": {"data": {"type": "appCategories", "id": "HEALTH_AND_FITNESS"}},
    "secondaryCategory": {"data": {"type": "appCategories", "id": "LIFESTYLE"}}}}})
locs = call("GET", f"/appInfos/{iid}/appInfoLocalizations")["data"]
loc = next((l for l in locs if l["attributes"]["locale"].startswith("en")), None)
ia = {"name": E["APP_NAME"], "subtitle": text("subtitle"), "privacyPolicyUrl": E["PRIVACY_URL"]}
if loc:
    call("PATCH", f"/appInfoLocalizations/{loc['id']}", {"data": {"type": "appInfoLocalizations", "id": loc["id"], "attributes": ia}})
else:
    call("POST", "/appInfoLocalizations", {"data": {"type": "appInfoLocalizations", "attributes": {"locale": "en-US", **ia},
         "relationships": {"appInfo": {"data": {"type": "appInfos", "id": iid}}}}})
note("app info", "categories Health & Fitness / Lifestyle, name, subtitle, privacy policy")

# Age rating: nothing objectionable; the app covers health & wellness topics.
ar = call("GET", f"/appInfos/{iid}/ageRatingDeclaration")
if ar:
    d = ar["data"]; cur = d["attributes"]
    print("Age rating fields:", json.dumps(cur))
    enum_none = {"alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "horrorOrFearThemes",
                 "matureOrSuggestiveThemes", "medicalOrTreatmentInformation", "profanityOrCrudeHumor",
                 "sexualContentGraphicAndNudity", "sexualContentOrNudity", "violenceCartoonOrFantasy", "violenceRealistic",
                 "violenceRealisticProlongedGraphicOrSadistic", "gunsOrOtherWeapons"}
    bool_false = {"gambling", "unrestrictedWebAccess", "lootBox", "messagingAndChat", "parentalControls", "ageAssurance",
                  "userGeneratedContent", "advertising", "seventeenPlus", "kidsAgeBand", "socialMedia", "socialMediaAgeRestricted"}
    new = {}
    for k in cur:
        if k in enum_none: new[k] = "NONE"
        elif k == "healthOrWellnessTopics": new[k] = True
        elif k in bool_false and k != "kidsAgeBand": new[k] = False
    if call("PATCH", f"/ageRatingDeclarations/{d['id']}", {"data": {"type": "ageRatingDeclarations", "id": d["id"], "attributes": new}}) is not None:
        note("age rating", "answered (no objectionable content; health & wellness topics)")

# ---------- Version ----------
vers = call("GET", f"/apps/{aid}/appStoreVersions?filter[platform]=IOS&limit=20")["data"]
open_states = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
v = next((x for x in vers if x["attributes"]["versionString"] == VERSION), None) \
    or next((x for x in vers if x["attributes"].get("appStoreState") in open_states), None)
va = {"versionString": VERSION, "copyright": f"2026 {E['FIRST']} {E['LAST']}", "releaseType": "AFTER_APPROVAL"}
if v:
    v = call("PATCH", f"/appStoreVersions/{v['id']}", {"data": {"type": "appStoreVersions", "id": v["id"], "attributes": va}})["data"]
else:
    v = call("POST", "/appStoreVersions", {"data": {"type": "appStoreVersions", "attributes": {"platform": "IOS", **va},
             "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}})["data"]
vid = v["id"]; note("version", f"{VERSION} ({v['attributes'].get('appStoreState')})")

# Build
build = None
for _ in range(40):
    b = call("GET", f"/builds?filter[app]={aid}&filter[preReleaseVersion.version]={VERSION}&sort=-uploadedDate&limit=1")
    if b and b["data"]:
        build = b["data"][0]
        if build["attributes"]["processingState"] == "VALID": break
    print("waiting for build to process…"); time.sleep(30)
if not build or build["attributes"]["processingState"] != "VALID":
    print(f"::error title=build::No processed {VERSION} build"); sys.exit(1)
call("PATCH", f"/appStoreVersions/{vid}/relationships/build", {"data": {"type": "builds", "id": build["id"]}})
note("build", f"{VERSION} ({build['attributes']['version']}) attached")

# Store text
vl = call("GET", f"/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]
en = next((l for l in vl if l["attributes"]["locale"].startswith("en")), None)
la = {"description": text("description"), "keywords": text("keywords"), "promotionalText": text("promo"),
      "supportUrl": E["SUPPORT_URL"], "marketingUrl": E["SUPPORT_URL"]}
if en:
    call("PATCH", f"/appStoreVersionLocalizations/{en['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": en["id"], "attributes": la}})
    lid = en["id"]
else:
    lid = call("POST", "/appStoreVersionLocalizations", {"data": {"type": "appStoreVersionLocalizations", "attributes": {"locale": "en-US", **la},
               "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})["data"]["id"]
note("store text", "description, keywords, promotional text, support URL")

# Review contact
rv = {"contactFirstName": E["FIRST"], "contactLastName": E["LAST"], "contactPhone": E["PHONE"], "contactEmail": E["EMAIL"],
      "demoAccountRequired": False, "notes": text("review_notes")}
rd = call("GET", f"/appStoreVersions/{vid}/appStoreReviewDetail", quiet=True)
if rd and rd.get("data"):
    call("PATCH", f"/appStoreReviewDetails/{rd['data']['id']}", {"data": {"type": "appStoreReviewDetails", "id": rd["data"]["id"], "attributes": rv}})
else:
    call("POST", "/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": rv,
         "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
note("review", "contact and notes for the reviewer")

# ---------- Screenshots ----------
def upload_set(display, files):
    sets = call("GET", f"/appStoreVersionLocalizations/{lid}/appScreenshotSets")["data"]
    s = next((x for x in sets if x["attributes"]["screenshotDisplayType"] == display), None)
    if s:
        for old in call("GET", f"/appScreenshotSets/{s['id']}/appScreenshots")["data"]:
            call("DELETE", f"/appScreenshots/{old['id']}")
    else:
        s = call("POST", "/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display},
                 "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": lid}}}}})["data"]
    done = 0
    for f in files:
        data = open(f, "rb").read()
        r = call("POST", "/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {"fileName": os.path.basename(f), "fileSize": len(data)},
                 "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": s["id"]}}}}})
        if not r: continue
        shot = r["data"]
        for op in shot["attributes"]["uploadOperations"]:
            hdr = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
            chunk = data[op["offset"]: op["offset"] + op["length"]]
            requests.request(op["method"], op["url"], headers=hdr, data=chunk).raise_for_status()
        call("PATCH", f"/appScreenshots/{shot['id']}", {"data": {"type": "appScreenshots", "id": shot["id"],
             "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        done += 1
    note("screenshots", f"{display}: {done} uploaded")

phone = sorted(glob.glob("appstore/screenshots/iphone_*.png"))
pad = sorted(glob.glob("appstore/screenshots/ipad_*.png"))
if phone: upload_set("APP_IPHONE_67", phone[:10])
if pad: upload_set("APP_IPAD_PRO_3GEN_129", pad[:10])

# ---------- Price: free ----------
pts = call("GET", f"/apps/{aid}/appPricePoints?filter[territory]=USA&limit=200")
free = next((p for p in (pts or {}).get("data", []) if float(p["attributes"]["customerPrice"]) == 0), None)
if free:
    call("POST", "/appPriceSchedules", {"data": {"type": "appPriceSchedules", "relationships": {
        "app": {"data": {"type": "apps", "id": aid}},
        "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
        "manualPrices": {"data": [{"type": "appPrices", "id": "${price0}"}]}}},
        "included": [{"type": "appPrices", "id": "${price0}", "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": free["id"]}}}}]})
    note("price", "Free")

# ---------- Availability: every country except China mainland ----------
terr = []
url = "/territories?limit=200"
while url:
    r = call("GET", url); terr += [t["id"] for t in r["data"]]; url = r.get("links", {}).get("next")
terr = [t for t in terr if t != "CHN"]
inc = [{"type": "territoryAvailabilities", "id": f"${{t{i}}}", "attributes": {"available": True},
        "relationships": {"territory": {"data": {"type": "territories", "id": t}}}} for i, t in enumerate(terr)]
res = call("POST", "/v2/appAvailabilities", {"data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
          "relationships": {"app": {"data": {"type": "apps", "id": aid}},
                            "territoryAvailabilities": {"data": [{"type": "territoryAvailabilities", "id": x["id"]} for x in inc]}}},
          "included": inc}, ok=(200, 201, 409))
note("availability", f"{len(terr)} countries/regions (all except China mainland)" + (" — already set" if res is None else ""))

# ---------- Submit ----------
if E.get("SUBMIT") == "yes":
    sub = call("POST", "/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
               "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}})
    if sub:
        sid = sub["data"]["id"]
        if call("POST", "/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}}) is not None:
            if call("PATCH", f"/reviewSubmissions/{sid}", {"data": {"type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}}) is not None:
                note("SUBMITTED", f"iLife {VERSION} sent to App Review")

st = call("GET", f"/appStoreVersions/{vid}")["data"]["attributes"].get("appStoreState")
note("state", st)
if problems:
    print("PROBLEMS:"); [print(" - " + p) for p in problems]
