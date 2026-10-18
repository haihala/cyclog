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
Gradle Plugin. Point Flutter at it with
`flutter config --jdk-dir=/path/to/jdk-21` if the system default is newer.

```bash
flutter test
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### Building a copy to share

```bash
flutter build apk --release --target-platform android-arm,android-arm64
```

This drops the `x86_64` slice, which only emulators and some ChromeOS
devices use, and roughly halves the file size. Every physical Android phone
is covered by the two ARM targets.

Note that the Dart snapshot embeds the absolute path of the build directory
(it is the URI of Flutter's generated plugin registrant, used only as a
label in stack traces). Building from a path under `/home/<you>` therefore
puts your username in the binary. Harmless, but building from a neutral
directory avoids it.

## Signing

Release builds are signed with a key that is deliberately **not** in this
repository. Without it the project still builds and runs, but the result
cannot update any install signed with the real key.

### What Gradle expects

`android/key.properties`, which is gitignored:

```properties
storePassword=<keystore password>
keyPassword=<same password>
keyAlias=cyclog
storeFile=/home/<you>/.keys/cyclog/cyclog-release.p12
```

If that file is missing, or `storeFile` points at something that does not
exist, the release build **silently falls back to the debug key**. It will
build and install fine on a fresh device, and then refuse to update anyone
running a properly signed build. Always check the signature before sharing.

### Checking which key a build actually used

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

A correctly signed release reports:

```
Signer #1 certificate DN: CN=cyclog, OU=Personal, O=cyclog, C=FI
Signer #1 certificate SHA-256 digest:
  d24ee1b987c6b9d1e1e5524b6b8c08f2eabc1e30bf05826c66370332cc381921
```

That digest identifies the signing certificate and stays the same across
every build. It is unrelated to the checksum of any particular APK file.

The keystore itself can be inspected with:

```bash
keytool -list -v -keystore ~/.keys/cyclog/cyclog-release.p12
```

### If the key is lost

There is no recovery path. Android only allows an update when the new build
carries the same signature, so everyone running the app would have to
uninstall — deleting their entries — before they could install anything
built with a replacement key.

Back up **both** the keystore file and its password, somewhere separate from
this machine. The repository does not and cannot protect them.

### How the key was created

For reference only. Running this again produces a *different* key, which
cannot update existing installs.

```bash
keytool -genkeypair -v \
  -keystore ~/.keys/cyclog/cyclog-release.p12 \
  -storetype PKCS12 -keyalg RSA -keysize 4096 -validity 36500 \
  -alias cyclog \
  -dname "CN=cyclog, OU=Personal, O=cyclog, C=FI"
```

## Backups

Settings offers JSON export and import. Exports are plain, readable JSON so
the data is never locked inside this app.

The database is also included in Android's Auto Backup. The write-ahead log
is checkpointed when the app goes to the background, so the `.db` file on
disk is always complete — Auto Backup copies that file but not its `-wal`
sidecar, and without the checkpoint a restore could silently miss the most
recent entries.
