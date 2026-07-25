# Papertrail PDF

Papertrail PDF is a private, offline-first PDF reader for Android and iOS, built with Flutter.

## Features

- Add one or multiple PDFs using the system document picker
- Scan a user-approved folder and import all PDFs inside it
- Search the PDF library by filename
- Search text across every PDF with page snippets and recent-search history
- Offline OCR indexing for scanned PDFs
- Filter search by folder, document date, page count, and file size
- Sort PDFs by name, recent activity, document date, file size, or page count
- Recently opened section with the five most recent documents
- First-page thumbnails in the PDF library
- Page count and file size for every PDF
- Reading position and percentage progress
- Last-opened date and time
- Rename PDFs inside the Papertrail library
- Create library folders and move PDFs between them
- Delete Papertrail's stored PDF copy from the device with confirmation
- Automatic reading-position restore
- In-document text search with highlighted results
- Previous and next search-result navigation
- Password prompt for protected PDFs
- Page-thumbnail navigation and jump-to-page
- Persistent page bookmarks and PDF table-of-contents navigation
- Vertical, horizontal, and two-page viewing modes
- Rotate, fit-width, fit-page, and full-screen controls
- Reduced-memory rendering for large documents
- Automatic page recovery after an unexpected close
- Remember precise zoom level and scroll position per PDF
- Reader brightness slider and optional keep-screen-awake mode
- Normal, night, and sepia reading modes
- Configurable page spacing and document background
- Right-to-left page navigation
- Screen-reader labels and responsive tablet/foldable layouts
- Optional bottom page-number/navigation controls, disabled by default
- Top-left navigation drawer with application Settings
- Configurable Sort menu with only essential options enabled by default
- Configurable open-reader actions with only essential tools enabled by default
- Collapsible General, Header, Sorting, and Reader sections in Settings
- Configurable library header actions with only Sort and Theme enabled by default
- Persistent annotation layer with highlighting, underline, strikethrough,
  drawing, notes, signatures, shapes, stamps, undo, and redo
- Pinch-to-zoom, links, and text selection
- Light and dark themes
- Open PDFs through Android's **Open with** menu
- Receive PDFs from the Android Share menu and iOS document picker
- Print PDFs using the Android/iOS system print dialog
- Encrypted storage for private library metadata
- Local-only crash diagnostics with no network transmission
- Automatic cleanup of stale incoming and OCR temporary files
- No account, advertising, analytics, or tracking

## Privacy and device files

Android and iOS do not allow an App Store application to silently scan every document on the phone. Use **Add PDFs** to select one or more files. Selected PDFs are copied into Papertrail's private offline library and appear under **All PDFs**. A document appears under **Recently opened** after you open it.

## Requirements

- Windows 11, macOS, or Linux
- Flutter 3.32.2 or a compatible newer stable version
- Dart 3.8 or later
- JDK 17 for Android builds
- Android SDK with platform and build tools installed
- macOS with Xcode for iOS builds

Verify the setup:

```sh
flutter doctor -v
```

## Install dependencies

Open PowerShell in the project directory:

```powershell
cd "C:\Users\vikas\OneDrive\H1B\Documents\PDF Reader"
$env:JAVA_HOME="C:\Program Files\Eclipse Adoptium\jdk-17.0.15.6-hotspot"
flutter pub get
```

## Run on an Android emulator

List available emulators:

```powershell
flutter emulators
```

Start the configured Pixel emulator:

```powershell
flutter emulators --launch Pixel_9
```

Wait for Android to finish booting, then run:

```powershell
flutter run -d emulator-5554
```

If the device identifier differs, find it with `flutter devices` and use that identifier after `-d`.

## Run on a physical Android phone

1. On the phone, open **Settings > About phone**.
2. Tap **Build number** seven times.
3. Open **Settings > System > Developer options**.
4. Enable **USB debugging**.
5. Connect the phone with a data-capable USB cable.
6. Select **File transfer** as the USB mode.
7. Accept the **Allow USB debugging** prompt.
8. Confirm the connection:

```powershell
flutter devices
```

9. Run the app using the displayed device identifier:

```powershell
flutter run -d DEVICE_ID
```

## Run checks

```powershell
dart format lib test
dart analyze lib test
flutter test --no-pub
```

## Build an installable Android APK

### Automatic named release (recommended)

Set the app version in `pubspec.yaml`. Increase the build number after `+` for
every store release:

```yaml
version: 1.1.0+2
```

Run the included release script:

```powershell
cd "C:\Users\vikas\OneDrive\H1B\Documents\PDF Reader"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\build-release.ps1
```

The script reads the version automatically and creates:

```text
release\Papertrail-PDF-v1.1.0-build2.apk
```

Build only an APK, only a Play Store bundle, or both:

```powershell
.\build-release.ps1 -Format apk
.\build-release.ps1 -Format aab
.\build-release.ps1 -Format both
```

### Manual APK build

```powershell
cd "C:\Users\vikas\OneDrive\H1B\Documents\PDF Reader"
$env:JAVA_HOME="C:\Program Files\Eclipse Adoptium\jdk-17.0.15.6-hotspot"
flutter clean
flutter pub get
flutter build apk --release
```

The APK is created at:

```text
build\app\outputs\flutter-apk\app-release.apk
```

Before installing a replacement build, uninstall an older debug build if Android reports a signature conflict.

Install the release APK on the connected emulator or phone:

```powershell
adb install -r "build\app\outputs\flutter-apk\app-release.apk"
```

## Build the Google Play App Bundle

A Play Store release requires a private upload keystore and release signing configuration. The current project still uses debug signing for local release builds and must not be uploaded to Google Play until signing is configured.

After configuring release signing:

```powershell
cd "C:\Users\vikas\OneDrive\H1B\Documents\PDF Reader"
$env:JAVA_HOME="C:\Program Files\Eclipse Adoptium\jdk-17.0.15.6-hotspot"
flutter clean
flutter pub get
flutter build appbundle --release
```

The bundle is created at:

```text
build\app\outputs\bundle\release\app-release.aab
```

## Build for iOS

An iOS build requires macOS, Xcode, an Apple Developer account, and a configured development team.

```sh
flutter pub get
flutter build ipa --release
```

Open `ios/Runner.xcworkspace` in Xcode to configure signing and upload the archive to App Store Connect.

## Using the PDF library

1. Tap **Add PDFs**.
2. Select one or more PDF files in the system picker.
3. The selected files appear alphabetically under **All PDFs**.
4. Tap a document to read it.
5. Opened documents appear under **Recently opened**.
6. Use the search icon inside the reader to search document text.
7. Use the document menu to remove a PDF from Papertrail's private library.

Removing a document from Papertrail deletes the app's private copy. It does not delete the original file selected from Downloads, Drive, or another provider.

## Store material

Store copy and privacy language are available in the `store/` directory. Branding source files are under `assets/branding/`.
