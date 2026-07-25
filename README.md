<div align="center">
  <img src="assets/branding/papertrail-icon-1024.png" alt="Papertrail PDF logo" width="120">

  # Papertrail PDF

  A private, offline-first PDF reader for Android and iOS, built with Flutter.

  [![Flutter](https://img.shields.io/badge/Flutter-3.32%2B-02569B?logo=flutter)](https://flutter.dev)
  [![Android](https://img.shields.io/badge/Android-supported-3DDC84?logo=android&logoColor=white)](#platform-status)
  [![iOS](https://img.shields.io/badge/iOS-source%20available-000000?logo=apple)](#platform-status)
  [![Tests](https://img.shields.io/badge/tests-58%20passing-brightgreen)](#testing)
  [![Privacy](https://img.shields.io/badge/privacy-offline--first-6558D3)](store/PRIVACY_POLICY.md)
</div>

> [!IMPORTANT]
> Papertrail PDF is under active development and is not yet distributed through
> Google Play or the App Store. Release builds currently require your own
> signing configuration.

## ✨ Why Papertrail?

Papertrail is designed for people who want capable PDF reading without creating
an account or sending their document library to a remote service. PDFs, search
indexes, reading progress, signatures, annotations, and crash diagnostics stay
on the device.

## 🚀 Highlights

### 🗂️ Library and file organization

- Import PDFs with the system document picker or from a user-approved folder
- Open PDFs sent through Android **Open with** and supported iOS document flows
- All, Favorites, Uncategorized, custom-folder, and Recently opened sections
- Rename, move, share, remove, or permanently delete library copies
- Multi-select actions for moving, removing, and deleting documents
- Duplicate detection based on document fingerprints
- Sort by name, recent activity, document date, size, or page count
- First-page thumbnails, file metadata, and responsive phone/tablet layouts

### 🔎 Search and smart reading

- Search filenames and text across the PDF library
- Page-numbered result snippets and recent-search history
- Offline OCR indexing for scanned pages
- Cached, serialized indexing to limit repeated CPU, memory, and battery use
- Search filters for folder, date, page count, and file size
- Private on-device extractive summaries with progress and cancellation
- Ranked important-information cards linked to their source pages

### 📖 Reading experience

- Select and copy PDF text
- Search inside an open document with previous/next result navigation
- Password prompts for protected PDFs
- Page thumbnails, jump-to-page, bookmarks, and table of contents
- Vertical, horizontal, and two-page layouts
- Double-tap and pinch zoom, rotation, fit-width, fit-page, and full screen
- Persistent page, zoom, and scroll-position recovery
- Normal, night, and sepia modes
- Brightness, page spacing, background, right-to-left navigation, and
  keep-screen-awake controls
- Configurable header, sorting, reader, notification, and navigation options

### ✍️ Annotations and signatures

- Highlight, underline, strikethrough, freehand drawing, notes, shapes, and stamps
- Draw reusable signatures or import signature images
- Drag annotations and signatures into position
- Page-bound annotation coordinates that follow scrolling, zoom, and rotation
- Undo, redo, atomic saving, and unsaved-change protection
- Annotated Share and Print output through a flattened PDF copy

## 🔐 Privacy

Papertrail does not require an account and does not include advertising,
analytics, or tracking. Library metadata is stored in encrypted platform
storage where available. Search and OCR data remain inside the application
sandbox.

The system document picker controls which files Papertrail can access. Imported
PDFs are copied into the application's private library; deleting a Papertrail
copy does not delete the original file held by Downloads, Drive, WhatsApp, or
another provider.

See the full [Privacy Policy](store/PRIVACY_POLICY.md).

## 📱 Platform status

| Platform | Status | Notes |
|---|---|---|
| Android | Actively tested | Emulator and physical-device workflows supported |
| iOS | Source available | Requires macOS/Xcode signing and final physical-device verification |

## 🛠️ Getting started

### ✅ Prerequisites

- Flutter 3.32.2 or a compatible newer stable release
- Dart 3.8 or later
- JDK 17 and the Android SDK for Android builds
- macOS, Xcode, and an Apple Developer account for iOS builds

Verify your environment:

```sh
flutter doctor -v
```

### 📦 Clone and install dependencies

```sh
git clone https://github.com/vkgpt11/Papertrail-PDF.git
cd Papertrail-PDF
flutter pub get
```

### ▶️ Run the application

List available devices:

```sh
flutter devices
```

Run on a selected emulator or connected device:

```sh
flutter run -d DEVICE_ID
```

To start a configured Android emulator first:

```sh
flutter emulators
flutter emulators --launch EMULATOR_ID
```

## 🧪 Testing

Format, analyze, and run the complete unit/widget suite:

```sh
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
```

Run the annotated-export integration test on an Android emulator:

```sh
flutter test integration_test/annotation_export_test.dart -d DEVICE_ID
```

The current suite covers document metadata, sorting and filters, search-index
serialization, summaries, annotation persistence, signatures, responsive
layouts, preferences, platform contracts, and annotated export.

## 🤖 Building Android

### 📲 APK

```sh
flutter build apk --release
```

Output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Windows users can generate a versioned APK, App Bundle, or both with:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\build-release.ps1 -Format apk
.\build-release.ps1 -Format aab
.\build-release.ps1 -Format both
```

### 🏪 Google Play App Bundle

```sh
flutter build appbundle --release
```

Output:

```text
build/app/outputs/bundle/release/app-release.aab
```

> [!WARNING]
> The checked-in Android configuration uses debug signing for local release
> testing. Configure a private upload keystore and secure release-signing
> properties before uploading an App Bundle to Google Play. Never commit
> keystores, passwords, or `key.properties`.

## 🍎 Building iOS

On macOS:

```sh
flutter pub get
open ios/Runner.xcworkspace
```

Configure the development team and signing in Xcode, then build with:

```sh
flutter build ipa --release
```

iOS incoming-document behavior must be verified on a physical iPhone before an
App Store release.

## ⚠️ Known limitations

- Annotated Share/Print output is flattened to preserve its appearance; text in
  the exported copy may no longer be selectable.
- OCR and summarization are intentionally processed on-device and can take time
  for very large scanned documents.
- The repository does not contain signing keys or store credentials.
- App Store and Google Play publication are not yet complete.

## 🧭 Project structure

```text
lib/                 Application, reader, search, summary, and annotation code
test/                Unit, contract, and widget tests
integration_test/    Device-level integration tests
android/             Android host application
ios/                 iOS host application
assets/branding/     Application branding
store/               Store listing and privacy material
tool/                Development utilities
```

## 🤝 Contributing

Issues and pull requests are welcome.

1. Fork the repository.
2. Create a focused feature or fix branch.
3. Run formatting, analysis, and tests.
4. Explain the user impact and verification in the pull request.

Please do not commit PDFs containing personal information, generated APKs,
signing credentials, local SDK paths, or private keys.

## 🏬 Store material

- [Store listing](store/STORE_LISTING.md)
- [Privacy policy](store/PRIVACY_POLICY.md)
