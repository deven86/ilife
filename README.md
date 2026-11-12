# iLife — Live Healthy • Live Strong • Live Better

Private health, workout and diet companion for iPhone and iPad (Apple Watch via Apple Health).
SwiftUI · SwiftData + iCloud (CloudKit private DB) · HealthKit · MusicKit · ActivityKit · WidgetKit · Vision OCR.
Built and shipped to TestFlight entirely from GitHub Actions — no Mac needed.

## What's in Phase 1

| Area | What it does |
|---|---|
| Dashboard | Readiness score (sleep, HRV, resting HR), steps, sleep, heart rate, hydration, calories, workout minutes, today's plan, nutrition ring, weight goal |
| Fitness | Workout history + weekly chart, Cult-style plans by weekday (starter Push/Pull/Legs, Full Body, HIIT, Yoga), quick start, log past workouts with sets |
| Auto-detect | Every workout recorded by Apple Watch, Fitness, Strava, Garmin etc. is imported from Apple Health; background delivery + "Workout detected" notification |
| Active session | Timer, live heart rate (from Watch), calories, exercise-by-exercise flow, Apple Music controls, Lock Screen Live Activity + Dynamic Island |
| Apple Music | Pick a workout playlist; auto-plays (shuffled) when a session starts |
| Nutrition | Meals by breakfast/lunch/snacks/dinner, Indian food quick-add library, custom foods, macros donut, water tracking — all written to Apple Health |
| InBody | Scan the sheet (camera), photo or PDF → on-device OCR → review → save; history + body-composition trend; writes weight / body fat / lean mass to Apple Health |
| Medical vault | Reports, prescriptions, lab reports, doctor notes — scan/upload, stored in iCloud, Quick Look viewer |
| Emergency | Contacts (manual or from Contacts, tap-to-call), Medical ID (blood group, allergies, conditions, meds) |
| Security | Face ID / Touch ID lock every time the app leaves the foreground (not during a workout) |
| Themes | Nature Glass, Aurora Glow, Dark Elegance, Sunset Dream, Minimal Clear + your own photo as wallpaper; Liquid Glass on iOS 26 |
| Widget | "Today's Target" — Home Screen (small/medium) and Lock Screen (circular/rectangular) |
| Alarms | Workout, water, meal, medicine, sleep — repeat by weekday |
| iPad | Sidebar layout, 4-column dashboard |

## Phase 2 (next)
Apple Watch app (start workouts from the wrist, live HR), AlarmKit alarms that ring through Silent mode,
food photo / barcode logging, AI weekly insights, PDF health report export.

## One-time setup

1. **Repo secrets** (Settings → Secrets → Actions) — same values as VISION:
   `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`.
2. **developer.apple.com → Identifiers** (the API can't do these):
   - App Groups → create `group.com.jondhale.ilife`
   - iCloud Containers → create `iCloud.group.com.jondhale.ilife`
3. Actions → **Signing setup** → Run. This registers `com.jondhale.ilife` and `com.jondhale.ilife.widgets`
   and enables HealthKit, iCloud, Push, App Groups, Data Protection.
4. developer.apple.com → Identifiers → `com.jondhale.ilife`: tick the App Group and iCloud container,
   and under **App Services** tick **MusicKit**. Same App Group on `com.jondhale.ilife.widgets`.
   Then run **Signing setup** again with *force* ticked.
5. **App Store Connect** → My Apps → + New App → bundle `com.jondhale.ilife`, name e.g. "iLife Health" (plain "iLife" is likely taken).
6. Actions → **TestFlight** → Run, type `UPLOAD`.

`CI` compiles for the Simulator only; it runs on PRs or by hand (Mac minutes are shared with VISION and Third Eye).

## Data & privacy
All data lives in SwiftData on the device and your **private** iCloud database. Nothing is sent to any server.
InBody OCR runs on-device (Apple Vision). Medical files use iOS Complete file protection.

## Known limitation (being fixed next)
TestFlight builds talk to the **Production** iCloud environment, where SwiftData can't create its record types by itself.
Until the schema is deployed (a CloudKit-schema workflow, like VISION's), iLife works fully on each device but iPhone ⇄ iPad sync stays idle.
