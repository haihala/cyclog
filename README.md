# cyclog

Private, offline tracking for things that recur.

You define every tracker yourself — its name, and whether an entry is a single
day or a stretch of days. From the gaps between your entries the app works out
a plain arithmetic estimate of when the next one might fall, with a prediction
interval that widens honestly when the data is irregular.

It never infers, backfills, corrects or second-guesses what you entered.

## Principles

- Nothing is ever treated as missing, late, forgotten or wrong.
- Estimates are clearly labelled as estimates and can be switched off.
- Entries without an end date are kept as-is and simply left out of length
  figures.
- All data stays on the device. The release build requests no network
  permission and is excluded from Android cloud backup.

## Build

Requires a JDK 21 toolchain; Java 25 is not yet supported by the Android
Gradle Plugin.

```bash
flutter test
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Release signing reads `android/key.properties`, which is not committed. If it
is absent the build falls back to the debug key, which cannot update an
install signed with the real release key.

## Backups

Settings offers JSON export and import. Exports are plain, readable JSON so
the data is never locked inside this app.
