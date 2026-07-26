# Android Release Signing and GitHub Deployment

This guide explains how to create and preserve the permanent Papertrail PDF
Android signing key, configure local release builds, configure GitHub Actions,
run the automated build, download the versioned APK, and diagnose common
failures.

## Why the Signing Key Matters

Android requires every APK to be signed. Android permits an installed
application to be upgraded only when the new APK has:

- The same application ID
- A greater version code
- A signature produced by the same signing key

The Papertrail PDF application ID is:

```text
com.papertrail.pdfreader
```

Losing the signing key or its password can prevent existing installations from
being upgraded. Store the keystore and its password as permanent release
credentials.

## Security Rules

- Never commit a `.jks` file to Git.
- Never commit a populated `android/key.properties` file.
- Never paste a keystore, Base64 keystore, or password into an issue, pull
  request, chat, build log, or documentation.
- Do not print Base64 keystore data in the terminal.
- Keep at least two encrypted backups in separate locations.
- Use the same permanent key for every future Papertrail PDF release.
- Limit GitHub repository administration and Actions-secret access.

## Prerequisites

The Windows development environment requires:

- Flutter
- Java Development Kit 17
- GitHub CLI authenticated to `github.com`
- Access to the `vkgpt11/Papertrail-PDF` repository

Confirm the tools:

```powershell
flutter --version
java -version
gh auth status
```

The commands below use this JDK path:

```text
C:\Program Files\Eclipse Adoptium\jdk-17.0.15.6-hotspot
```

Adjust the path if a different JDK 17 installation is active.

## 1. Choose a Secure Writable Directory

Do not place the keystore inside the Git repository. Use a private directory
that the current Windows account can write.

Recommended example:

```powershell
$signingFolder = "C:\Dev\Papertrail-Signing"
New-Item -ItemType Directory -Path $signingFolder -Force

$newKeystore = "$signingFolder\papertrail-upload-2026.jks"
$keytool = "C:\Program Files\Eclipse Adoptium\jdk-17.0.15.6-hotspot\bin\keytool.exe"
```

Verify that the directory is writable:

```powershell
$permissionTest = Join-Path $signingFolder "write-test.tmp"
New-Item -ItemType File -Path $permissionTest -Force
Remove-Item -LiteralPath $permissionTest
```

If this fails with `Access is denied`, choose another private directory or
correct the directory permissions before generating the key.

## 2. Generate the Permanent Upload Keystore

Run:

```powershell
& $keytool -genkeypair -v `
  -keystore $newKeystore `
  -storetype PKCS12 `
  -alias papertrail-upload `
  -keyalg RSA `
  -keysize 4096 `
  -validity 10000 `
  -dname "CN=Papertrail PDF, OU=Mobile Apps, O=Papertrail, L=Hyderabad, ST=Telangana, C=IN"
```

When prompted:

1. Enter a strong, unique keystore password.
2. Enter the same password again.
3. Store the password immediately in an approved password manager.

PKCS12 commonly uses the store password as the private-key password. The
Papertrail GitHub configuration therefore uses the same verified password for
both password secrets unless the keystore was deliberately created differently.

The expected success message includes:

```text
[Storing C:\Dev\Papertrail-Signing\papertrail-upload-2026.jks]
```

## 3. Verify the Keystore

Confirm that the file exists and has non-zero length:

```powershell
Get-Item -LiteralPath $newKeystore |
  Select-Object FullName, Length, LastWriteTime
```

Inspect the keystore:

```powershell
& $keytool -list -v -keystore $newKeystore
```

Enter the new password. Verify:

- Keystore type is `PKCS12`
- Alias is `papertrail-upload`
- Entry type is `PrivateKeyEntry`
- The certificate owner identifies Papertrail PDF
- The validity period is appropriate

Do not upload or use a keystore that fails this verification.

## 4. Back Up the Keystore

Before producing a release:

1. Keep the working copy outside the repository.
2. Store one encrypted backup in a trusted cloud vault.
3. Store another encrypted backup offline or in a separate secure location.
4. Save the password and alias in a password manager.
5. Record which application ID uses the key.

Recommended credential record:

```text
Application: Papertrail PDF
Application ID: com.papertrail.pdfreader
Keystore filename: papertrail-upload-2026.jks
Keystore type: PKCS12
Alias: papertrail-upload
Store password: stored securely
Key password: stored securely
Created date: recorded by the owner
```

Do not include actual passwords in this document.

## 5. Configure GitHub Actions Secrets

The workflow reads these repository secrets:

| GitHub secret | Content |
|---|---|
| `PAPERTRAIL_KEYSTORE_BASE64` | Base64 representation of the complete `.jks` file |
| `PAPERTRAIL_KEYSTORE_PASSWORD` | Verified keystore password |
| `PAPERTRAIL_KEY_ALIAS` | `papertrail-upload` |
| `PAPERTRAIL_KEY_PASSWORD` | Verified private-key password |

### Upload the keystore without printing it

```powershell
[Convert]::ToBase64String(
    [IO.File]::ReadAllBytes($newKeystore)
) | gh secret set PAPERTRAIL_KEYSTORE_BASE64 `
    --repo vkgpt11/Papertrail-PDF
```

Do not run `ToBase64String(...)` without the pipeline because that prints the
encoded keystore to the terminal.

### Upload the passwords securely

Read the password without displaying it or storing it in PowerShell history:

```powershell
$securePassword = Read-Host "Enter the new keystore password" -AsSecureString
$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
  $securePassword
)

try {
    $plainPassword =
      [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)

    $plainPassword |
      gh secret set PAPERTRAIL_KEYSTORE_PASSWORD `
        --repo vkgpt11/Papertrail-PDF

    $plainPassword |
      gh secret set PAPERTRAIL_KEY_PASSWORD `
        --repo vkgpt11/Papertrail-PDF
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    Remove-Variable plainPassword -ErrorAction SilentlyContinue
    Remove-Variable securePassword -ErrorAction SilentlyContinue
    Remove-Variable passwordPointer -ErrorAction SilentlyContinue
}
```

### Upload the alias

```powershell
"papertrail-upload" |
  gh secret set PAPERTRAIL_KEY_ALIAS --repo vkgpt11/Papertrail-PDF
```

### Verify secret names

```powershell
gh secret list --repo vkgpt11/Papertrail-PDF
```

The output must list all four names:

```text
PAPERTRAIL_KEYSTORE_BASE64
PAPERTRAIL_KEYSTORE_PASSWORD
PAPERTRAIL_KEY_ALIAS
PAPERTRAIL_KEY_PASSWORD
```

GitHub does not display stored secret values.

## 6. Configure Local Release Signing

Create the ignored file:

```text
android/key.properties
```

Use the following structure:

```properties
storeFile=C:/Dev/Papertrail-Signing/papertrail-upload-2026.jks
storePassword=YOUR_PRIVATE_STORE_PASSWORD
keyAlias=papertrail-upload
keyPassword=YOUR_PRIVATE_KEY_PASSWORD
```

Use forward slashes in the Windows path. Replace the password placeholders
locally. Never commit the populated file.

Confirm Git ignores it:

```powershell
git check-ignore -v android/key.properties
git status --short
```

`android/key.properties` must not appear as an untracked or staged file.

## 7. Verify the Local Build

From the repository:

```powershell
cd "C:\Users\vikas\OneDrive\H1B\Documents\PDF Reader"
$env:JAVA_HOME =
  "C:\Program Files\Eclipse Adoptium\jdk-17.0.15.6-hotspot"

flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Expected APK:

```text
build\app\outputs\flutter-apk\app-release.apk
```

Verify it exists:

```powershell
Get-Item "build\app\outputs\flutter-apk\app-release.apk" |
  Select-Object FullName, Length, LastWriteTime
```

## 8. Run the GitHub Deployment Workflow

The workflow runs automatically after a push or merged pull request reaches
`main`. It can also be started from the Actions page or rerun using GitHub CLI.

List recent runs:

```powershell
gh run list `
  --workflow android-build-after-merge.yml `
  --repo vkgpt11/Papertrail-PDF `
  --limit 5
```

Rerun a failed run:

```powershell
gh run rerun RUN_ID --failed --repo vkgpt11/Papertrail-PDF
```

Monitor it:

```powershell
gh run watch RUN_ID --repo vkgpt11/Papertrail-PDF
```

Inspect failed logs:

```powershell
gh run view RUN_ID --log-failed --repo vkgpt11/Papertrail-PDF
```

Replace `RUN_ID` with the numeric Actions run ID.

## 9. Download the Versioned APK

After success, open the completed Actions run and download its artifact.

The artifact contains:

```text
Papertrail-PDF-v<version>-build<build-number>.apk
Papertrail-PDF-v<version>-build<build-number>.apk.sha256
```

Artifacts are retained according to the workflow retention policy.

To download using GitHub CLI:

```powershell
gh run download RUN_ID `
  --repo vkgpt11/Papertrail-PDF `
  --dir "C:\Dev\Papertrail-Builds"
```

Verify the checksum after download:

```powershell
Get-FileHash `
  -Algorithm SHA256 `
  -LiteralPath "C:\Dev\Papertrail-Builds\PATH-TO-APK"
```

Compare the result with the `.sha256` file.

## 10. Verify the APK Signature

Locate `apksigner` in the installed Android SDK and run:

```powershell
apksigner verify --verbose --print-certs "PATH-TO-APK"
```

Record the signing-certificate SHA-256 fingerprint. Future releases must report
the same certificate fingerprint.

Also verify:

- Application ID remains `com.papertrail.pdfreader`
- Version code increases
- Version name is correct
- Installation over the previous release succeeds
- Existing Papertrail data remains available after upgrade

## 11. Installation Conflicts

Android displays:

```text
App not installed as package conflicts with an existing package
```

when an installed application has the same application ID but a different
signature.

If Papertrail has not been published and the installed copy uses an obsolete
test key:

1. Export or back up important PDFs and annotations.
2. Uninstall the old Papertrail installation.
3. Install the APK signed with the new permanent key.
4. Use the new permanent key for all subsequent upgrades.

Uninstalling an application can remove its private application data.

## 12. Troubleshooting

### `Required signing secret KEYSTORE_BASE64 is missing`

Cause:

- One or more `PAPERTRAIL_*` GitHub secrets are absent.

Resolution:

```powershell
gh secret list --repo vkgpt11/Papertrail-PDF
```

Configure all four required secrets before rerunning the workflow.

### `fatal: not a git repository`

Cause:

- `gh secret set` was run outside the repository without identifying a
  repository.

Resolution:

- Add `--repo vkgpt11/Papertrail-PDF`, or
- Change into the repository first.

### `Paste your secret`

Cause:

- `gh secret set` was run without piped input.

For the keystore secret, cancel with `Ctrl+C` and use:

```powershell
[Convert]::ToBase64String(
    [IO.File]::ReadAllBytes($newKeystore)
) | gh secret set PAPERTRAIL_KEYSTORE_BASE64 `
    --repo vkgpt11/Papertrail-PDF
```

### `Access to the path is denied`

Cause:

- The signing directory or keystore has an incorrect Windows ACL.

Resolution:

- Use a new private directory writable by the current account, such as
  `C:\Dev\Papertrail-Signing`, or
- Have a Windows administrator repair the exact directory ACL.

Always verify directory write access before generating a new key.

### `keystore password was incorrect`

Cause:

- `PAPERTRAIL_KEYSTORE_PASSWORD` does not match the uploaded keystore.
- The Base64 secret contains a different keystore.

Resolution:

1. Verify the local keystore interactively with `keytool -list`.
2. Re-upload that verified keystore.
3. Update both password secrets using the verified password.
4. Rerun the workflow.

Do not repeatedly guess passwords against a production keystore.

### The keystore password is lost

A keystore password cannot be reset from the keystore.

- If the application has never been published, create a new permanent key and
  uninstall obsolete test builds before installing the new release.
- If Google Play App Signing is enabled, request an upload-key reset.
- If the application was distributed without Play App Signing, a different key
  cannot upgrade installations signed with the old key.

### Release build fails after signing succeeds

Signing configuration is only one build stage. Inspect the failed step:

```powershell
gh run view RUN_ID --log-failed --repo vkgpt11/Papertrail-PDF
```

Treat dependency, R8, Gradle, lint, disk, and test failures separately from
signing failures.

## 13. Release Checklist

Before every public release:

- [ ] Permanent keystore exists in two secure backup locations
- [ ] Keystore password is available in the password manager
- [ ] GitHub lists all four required signing secrets
- [ ] `flutter analyze` passes
- [ ] Unit and widget tests pass
- [ ] Release APK builds successfully
- [ ] APK signature fingerprint matches the permanent certificate
- [ ] Version code is greater than the previous release
- [ ] APK checksum is generated and verified
- [ ] Upgrade installation is tested on a physical Android device
- [ ] Open-with, annotation, signature, share, print, and restart workflows are tested
- [ ] No keystore, password, or populated properties file is committed

## 14. Ownership and Recovery Record

The application owner should maintain a private recovery record containing:

- Keystore backup locations
- Password-manager entry name
- Certificate SHA-256 fingerprint
- Creation date and responsible owner
- Google Play App Signing status
- GitHub repository administrators
- Procedure for rotating an upload key, if Play App Signing is later enabled

Review this record before transferring application ownership or changing release
administrators.
