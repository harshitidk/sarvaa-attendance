# Sarvaa Analytics — Flutter employee app

Flutter rewrite of the employee-facing app. Reuses the **same Supabase backend**
and the attendance engine (`record_location_event`, `employee_check_out`); only
the client is new. The Expo app remains under `apps/mobile`.

## Features

- Email/password auth with persisted session (Supabase Auth).
- **Today** — a large live status panel, check-in/check-out, this month's
  attendance calendar, WFH and leave requests, and the quarter's leave and
  work-hour counts. The work summary is written at check-out and can be revised
  only for a short window afterwards (30 minutes, hard-locked at 40; enforced
  server-side too).
- **History** — monthly calendar with per-day detail.
- **Requests** — work-from-home and leave (sick / paid / unpaid, reason
  required) are filed from Today and approved by an admin in the Requests panel.
- **Settings** — profile, background-detection status, appearance, sign out.
- **Background geofencing** — native geofence transitions reported to the backend
  (minute-bucketed dedupe keys); local notifications on transition.

## Requirements

- Flutter 3.x (Dart 3.12+)
- A Supabase project (the same one the Expo app uses)

## Run

Supply the Supabase URL and publishable/anon key at run time:

```bash
cd apps/mobile_flutter
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_KEY
```

Without these the app shows a configuration message instead of the login screen.

## Permissions

The manifest declaring a permission grants nothing — each must be requested at
runtime, and `lib/services/permissions_service.dart` is the single place that
does it.

| Permission | Needed for | Notes |
| --- | --- | --- |
| Location, while in use | Manual check-in | Requested on the check-in path. |
| Location, **all the time** | Automatic geofence attendance | Android 11+ will not grant this from a dialog; the app sends the user to system settings. |
| Notifications | Arrival/departure alerts | Android 13+ and iOS both gate this. A refusal never blocks attendance. |

Geofence monitoring is **only started once "all the time" is granted**. Starting
it earlier would report the service as running while the OS delivered no
transitions — the app would look fine and silently record nothing. When the
grant is missing, Today shows a banner naming the exact problem and the one
action that fixes it.

## Work from home

Two separate mechanisms, deliberately:

- **A request** (`wfh_requests`) — an employee asks for a day from Today; an
  admin approves it under **Requests**. Approval is the only path from a
  request to a real WFH day: the backend then materialises a row in
  `wfh_assignments`, which is what the attendance engine already reads. RLS
  stops an employee filing an approved request, filing for someone else, or
  backdating one.
- **A company day** (`company_wfh_days`) — an admin marks a date under
  **Holidays & WFH → Company WFH** and every active employee is excused from
  checking in. Clearing it removes only the rows it created, so a day granted
  to an individual survives.

`working_days` in company settings is a different thing again: the recurring
weekly pattern used to decide when absence is marked, not a calendar.

## Release builds

```bash
pnpm build:mobile aab     # Play Store bundle (default)
pnpm build:mobile apk     # per-ABI APKs for sideloading
pnpm build:mobile both
```

The script refuses to build without `SUPABASE_URL` / `SUPABASE_ANON_KEY` (it
falls back to `apps/mobile/.env`), runs `flutter analyze` and `flutter test`
first, and locates a JDK if `java` is not on the path.

### Signing

Release signing reads `android/key.properties`, which is gitignored along with
`*.jks`. Without it the build still succeeds but is **signed with the debug
key** and cannot be published — it prints a warning saying so.

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
cp android/key.properties.example android/key.properties   # then fill it in
```

Back the `.jks` up somewhere permanent. If it is lost, the app can never be
updated on the Play Store under this application ID (`in.co.sarvaa.attendance`).

## Design system

Monochrome by design: one hue family, warm paper white through ink black —
and its inverse in dark mode, which follows the device or can be pinned from
Settings.
Meaning is carried by **fill inversion, weight, border and glyph** — never by
colour — so the interface stays calm and reads identically for colour-blind
users.

- `lib/core/theme.dart` — colour tokens (`AppColors`), radii (`Radii`), the
  4pt spacing scale (`Insets`), the type scale (`AppText`), per-status tones,
  and a fully themed `ThemeData`. Tokens are grouped so a dark theme is a
  value swap rather than a rewrite.
- `lib/widgets/common.dart` — the shared vocabulary every screen is built
  from: `TodayHero`, `SectionCard`, `GroupedList`/`AppRow`, `StatTile`,
  `CountCell`, `StatusBadge`, `InitialsAvatar`, `IconTile`, `Segmented`,
  `DayToggle`, `SearchField`, `Notice`, `EmptyState`, `ScreenState`,
  `Refreshable`, `DateRangeBar`, `SheetShell`/`showAppSheet`, `BusyButton`.

Layout rules the screens follow, so views cannot drift apart:

- **Titles** — employee screens own their title via `PageHeader`; admin
  screens take it from the shell's app bar and add at most a one-line
  `ScreenCaption`. A screen never states its title twice.
- **Padding** — every scrollable uses an `AppPadding` constant
  (`page`, `pageWithFab`, `pageBelowBar`, `bar`), never an ad-hoc `fromLTRB`.
- **States** — every data view routes through `ScreenState`
  (skeleton → error-with-retry → empty → content) and wraps its content in
  `Refreshable`, so no screen can strand a spinner or lack pull-to-refresh.

Rules that hold across the app: no shadows (separation comes from the warm
canvas behind white cards), times and counts use tabular figures so columns
align, uppercase eyebrow labels head every section, and only the live
"checked in" state is drawn inverted.

## Verify

```bash
flutter analyze
flutter test
```

`flutter test` covers the attendance helpers plus a design-system suite that
renders every component at 360px — a layout overflow fails the build.

### Visual preview

`test_preview/` renders reference PNGs of the real widgets. It is deliberately
outside `test/`, so `flutter test` never runs it (goldens are host-dependent):

```bash
flutter test test_preview/ --update-goldens   # writes test_preview/preview/*.png
```

## Notes

- Times render in the **company timezone** (`app_settings.company_timezone`), 12-hour AM/PM.
- Background geofencing uses [`geofence_service`](https://pub.dev/packages/geofence_service);
  Android/iOS permissions and background modes are preconfigured in
  `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist`.
- The database is authoritative: the client only reports ENTER/EXIT transitions
  and reflects the returned attendance state.
