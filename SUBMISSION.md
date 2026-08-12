# App Store submission checklist

§10 of the specification — `CLAUDE.md`, which is not in this repository — says
this blocks release. Items marked **done in
the repo** are written and committed; items marked **needs a Mac** or **needs
you** cannot be produced from Windows, and are listed with exactly what remains.

Nothing here has been verified against App Store Connect, because that needs an
account, a Mac and a build.

---

## Info.plist usage strings

All present in [Config/Info.plist](Config/Info.plist), written as plain
sentences describing the benefit. Generic strings are an automatic rejection.

| Key | Status |
|---|---|
| `NSMicrophoneUsageDescription` | **Done** — recording audio alongside notes |
| `NSSpeechRecognitionUsageDescription` | **Done** — on-device dictation |
| `NSFaceIDUsageDescription` | **Done** — unlocking the vault |
| `NSLocationWhenInUseUsageDescription` | **Done** — finding nearby matches for place reminders |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | **Done** — place reminders while the app is closed |
| `NSPhotoLibraryUsageDescription` | **Not needed** — the `image` block type is declared but unimplemented, and nothing reaches the photo library. Add this string if that changes. |
| `NSCameraUsageDescription` | **Not needed** — same reason. |
| `NSCalendarsUsageDescription` | **Not needed** — schedules use `UNUserNotificationCenter`, not EventKit. |

## PrivacyInfo.xcprivacy

**Done** — [Verso/Resources/PrivacyInfo.xcprivacy](Verso/Resources/PrivacyInfo.xcprivacy).
Declares required-reason API usage for `UserDefaults` (CA92.1), file timestamps
(C617.1) and disk space (E174.1). `NSPrivacyCollectedDataTypes` is empty and
`NSPrivacyTracking` is false, which is the truth rather than an aspiration.

**Verify on a Mac:** system boot time is listed in §10 but Verso does not read
it. If a dependency-free build turns out to touch it, add `35F9.1`.

## App Privacy nutrition label

**Needs you, in App Store Connect.** The answer is **Data Not Collected** —
there is no server, no analytics SDK, and no third-party dependency of any kind.
Every feature that could have phoned home does not:

- Dictation refuses to run rather than sending audio to a speech server.
- Intelligence is on-device, and falls back to plain text processing.
- Sync is CloudKit private database only, in the user's own account.
- Sharing produces files; nothing is uploaded.

§10 calls this a genuine marketing asset. It is worth a line on the product page.

## Export compliance

`ITSAppUsesNonExemptEncryption` is set to **`false`** in Info.plist.

Verso uses CryptoKit (AES-GCM) and CommonCrypto (PBKDF2) solely to protect the
user's own data on their own device. That is normally exempt.

**Needs you:** §10 says to confirm the current exemption language in App Store
Connect before submitting, because it changes. If the current wording does not
cover this case, flip the key to `true` and file the year-end self-classification
report.

---

## Assets and metadata

| Item | Status |
|---|---|
| App icon, every size | **Needs you** — [AppIcon.appiconset](Verso/Resources/Assets.xcassets/AppIcon.appiconset) declares the 1024pt universal slot plus dark and tinted variants, and is empty. No artwork can be produced from here. |
| Launch screen | **Done** — `UILaunchScreen` with the `LaunchBackground` colour set, which follows light and dark. |
| Screenshots | **Needs a Mac** — §10 warns the required sizes change; check App Store Connect rather than assuming. Take them on `iron-gall` and `midnight-oil` so the theming shows. |
| Privacy policy URL | **Needs you** — required even collecting nothing. |
| Support URL | **Needs you.** |
| Age rating questionnaire | **Needs you** — no objectionable content; the honest answers should give 4+. |

---

## Capabilities to enable in Xcode

The entitlements files declare these; the matching capabilities still have to be
switched on for the App ID.

- **iCloud → CloudKit**, container `iCloud.com.verso.notes`
- **App Groups**, `group.com.verso.notes` — the widget and App Intents read the
  store through it
- **Push Notifications** — CloudKit sync needs it
- **Background Modes → Remote notifications** — for CloudKit
- **Time Sensitive Notifications** — rest timers and place reminders use
  `.timeSensitive`
- **Sign in with Apple** — *not* needed. There are no accounts.

Change `PRODUCT_BUNDLE_IDENTIFIER` from `com.verso.notes` to your own, and
update the iCloud container in both entitlements files and in
`VersoModelContainer.cloudKitContainerIdentifier` to match.

---

## Before you submit

§10 names four states that must all degrade gracefully. Each has code behind it;
none has been run.

| Test | What should happen | Where it is handled |
|---|---|---|
| Physical device | Haptics, Pencil, biometrics and geofences all need one | — |
| No iCloud account | Everything works, Settings says "This device only" | `VersoModelContainer.makeShared` falls back through CloudKit → local → in-memory and reports which |
| iCloud storage full | Local edits keep working; sync stops | Same fallback; the failure surfaces in Settings rather than as a crash |
| No Apple Intelligence | Every AI feature still works | `IntelligenceService` picks `HeuristicIntelligence`; §1's requirement is structural, not a stub |
| Airplane mode | Everything except sync and POI resolution | Place reminders report "no matching place found near you" rather than failing silently |

Also worth testing, from §9's quality bar:

- Two simulators on one iCloud account, to verify sync correctness
- Scrolling a 20,000-word note with Instruments, for the 16ms budget
- VoiceOver on every screen
- Dynamic Type through AX5 without clipping
- Reduce Motion, Increase Contrast and Reduce Transparency all on at once
- Cold launch under 400ms on the oldest supported device

---

## Known gaps at v1

Not blockers, but worth deciding on before submitting rather than after.

- **Four block types are declared but unimplemented:** `callout`, `code`,
  `image`, `link`. They decode and render an explicit placeholder rather than
  vanishing, and no bundled template uses them.
- **Documents do not sync.** See the README's deviation list.
- **User templates do not sync.** Same.
- **The exercise library holds ~170 entries**, not the ~200 §7 asks for.
