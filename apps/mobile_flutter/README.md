# Geofenced Attendance — Flutter employee app

Flutter rewrite of the employee-facing app. Reuses the **same Supabase backend**
and the attendance engine (`record_location_event`, `employee_check_out`); only
the client is new. The Expo app remains under `apps/mobile`.

## Features

- Email/password auth with persisted session (Supabase Auth).
- **Today** — status, check-in/check-out times, duration, manual check-in,
  check-out with a mandatory work summary (min 3 chars), update summary.
- **History** — monthly calendar with per-day detail.
- **Settings** — profile, background-detection status, recent location events, sign out.
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

## Verify

```bash
flutter analyze
flutter test
```

## Notes

- Times render in the **company timezone** (`app_settings.company_timezone`), 12-hour AM/PM.
- Background geofencing uses [`geofence_service`](https://pub.dev/packages/geofence_service);
  Android/iOS permissions and background modes are preconfigured in
  `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist`.
- The database is authoritative: the client only reports ENTER/EXIT transitions
  and reflects the returned attendance state.
