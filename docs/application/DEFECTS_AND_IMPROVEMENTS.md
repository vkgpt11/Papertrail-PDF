# Papertrail PDF Defects and Improvements Audit

This document reviews the 12 functional areas of Papertrail PDF and identifies
potential defects, recommended improvements, and areas where product decisions
or real-device testing are required.

The findings are based on the current implementation and automated tests. Some
items are confirmed implementation gaps, while others are risks that require
device testing or representative PDF files to confirm.

## 1. PDF Library Management

### Potential defects

- Folder import calculates a SHA-256 fingerprint for every PDF sequentially.
  Large folders may appear frozen.
- Import cancellation is not available once folder scanning begins.
- Import copies every selected PDF into private storage, potentially doubling
  device storage usage.
- Failure reporting provides counts but does not identify which files failed or
  why.
- File metadata can become stale after another application modifies a document.
- A duplicate-management screen is documented but is not evident in the current
  implementation.
- The multi-file picker currently appears to use `allowMultiple: false`.

### Recommended improvements

- Add cancellable import progress with the filename and percentage.
- Show an import-results screen listing successful files, duplicates, and
  failures.
- Check available storage before copying files.
- Refresh metadata only when file size or modification time has changed.
- Clearly distinguish **Remove from Papertrail** from **Delete from device**.

### How the user can help

- Test folders containing 100 to 500 PDFs.
- Test large files, duplicate files, unusual filenames, and read-only files.
- Decide whether Papertrail should copy PDFs or retain access to their original
  locations.

## 2. Folder Organization

### Potential defects

- Folder creation and document movement are present, but folder rename and
  deletion were not found.
- Deleting a folder could orphan its document-category assignments unless
  migration behavior is defined.
- Folder names may differ only by capitalization or whitespace.
- Folder ordering does not appear independently configurable.
- Application folders are metadata rather than physical device folders, which
  may not match user expectations.

### Recommended improvements

- Define folder-name validation and uniqueness rules.
- When deleting a folder, move its documents to **Uncategorized**.
- Add explicit rename and delete actions with confirmation.
- Persist custom folder ordering.
- Explain in the interface that library folders are organizational categories.

### How the user can help

- Decide whether folders should remain application-only categories or represent
  real device directories.
- Decide what should happen to documents when a folder is deleted.
- Test folder names containing spaces, Unicode characters, and mixed
  capitalization.

## 3. PDF Reading

### Potential defects

- Double-tap zoom remains sensitive to the PDF engine's current transformation
  and fit calculation.
- Restored zoom and scroll position may be inaccurate after rotation or a
  viewing-mode change.
- Two-page mode may behave poorly with differently sized pages.
- Full-screen state may not restore correctly after an interruption or system
  dialog.
- Brightness restoration uses best-effort error handling and requires
  real-device verification.
- Large documents can still create memory pressure during rendering.

### Recommended improvements

- Store reading position as page plus normalized page offset.
- Define double-tap behavior explicitly as
  **fit-to-screen → zoomed → fit-to-screen**.
- Reset incompatible saved transformations after orientation or view-mode
  changes.
- Apply memory-aware rendering quality for large documents.

### How the user can help

- Test double tap in portrait, landscape, rotated, and two-page modes.
- Test documents containing mixed portrait and landscape pages.
- Report the device, PDF page, view mode, and expected zoom result.

## 4. Document Navigation

### Potential defects

- Bookmarks are stored locally rather than embedded in the PDF.
- Bookmark state may be lost if the file fingerprint changes after the PDF is
  modified.
- Jump-to-page relies on the viewer being ready. Using it immediately after
  opening a PDF may fail.
- Thumbnail generation for long documents can consume substantial memory.
- Recently closed recovery may refer to a PDF that has been renamed or deleted.

### Recommended improvements

- Disable navigation actions until the PDF viewer reports readiness.
- Add loading and failure states for thumbnails and table-of-contents data.
- Preserve bookmark mappings during document replacement when identity can be
  established safely.
- Virtualize thumbnail lists and cache only visible or nearby pages.

### How the user can help

- Test jump-to-page immediately after opening a PDF.
- Test invalid, first-page, and last-page inputs.
- Test bookmarks before and after rename, restart, and document modification.
- Test a document containing at least 500 pages.

## 5. Text Interaction and Search

### Potential defects

- Text selection cannot operate on image-only PDFs without OCR-generated text
  and selection geometry.
- OCR indexing renders scanned pages and can consume memory and battery.
- The search-index JSON file is repeatedly loaded and decoded instead of using
  an efficient database.
- The index has no explicit schema migration or user-facing corruption report.
- Search cancellation may discard OCR work that has already completed.
- Password-protected PDFs may not be indexed automatically without a password
  for the current session.
- Search snippets may display private document content on-screen.

### Recommended improvements

- Replace the monolithic JSON index with an incremental database.
- Schedule OCR only on demand or under user-approved conditions.
- Identify whether a result came from PDF text or OCR.
- Add index progress, pause, retry, clear, and rebuild controls.
- Add a separate OCR-selection workflow for scanned documents.

### How the user can help

- Provide safe examples of text-based, scanned, multilingual, and
  password-protected PDFs.
- Test selection across columns, tables, rotated text, and line breaks.
- Decide whether OCR should run automatically or only when requested.

## 6. Annotations

### Potential defects

- Page-relative positioning is safer than screen-relative positioning but still
  requires verification after rotation and two-page layout changes.
- Annotations are stored in application sidecars and may be removed if the
  application is uninstalled before an annotated export is created.
- A malformed sidecar may prevent annotations for that document from loading.
- Highlighting is visual drawing and may not bind semantically to selected PDF
  text.
- Concurrent edit, save, rename, share, and close actions remain sensitive to
  operation timing.
- Flattened export rasterizes pages and may reduce text or image quality.
- Export is currently limited to 200 pages and 180 million rendered pixels.

### Recommended improvements

- Version the annotation-sidecar schema and retain a backup before migration.
- Add permanent identifiers and modification timestamps to annotation marks.
- Bind text markup to text ranges where supported by the PDF engine.
- Display explicit **Unsaved**, **Saving**, **Saved**, and **Save failed**
  states.
- Distinguish **Share original** from **Export annotated copy**.

### How the user can help

- Annotate a page, zoom, rotate, change view mode, restart, and verify placement.
- Test the rapid sequence: annotate, save, rename, and share.
- Compare exported quality with the original on text-heavy documents.

## 7. Signatures

### Potential defects

- Stored signatures are visual signatures, not certificate-backed digital
  signatures.
- An image signature may be unavailable if its encrypted local asset is damaged
  or removed.
- Malformed signature data may be skipped without sufficient user feedback.
- A signature image's aspect ratio may be distorted during resizing.
- It may not be clear whether a signature is still editable or permanently
  flattened.
- Sharing the original PDF without annotation export omits the signature.

### Recommended improvements

- Clearly label this functionality as **Visual signature**.
- Lock the signature aspect ratio by default.
- Warn before flattening a signature into an exported document.
- Display an error when a signature asset is missing or damaged.
- Require confirmation before placing a stored signature.

### How the user can help

- Decide whether certificate-backed cryptographic signatures are within scope.
- Test transparent PNGs, photographs, large images, and rotated signatures.
- Confirm whether signature resizing should preserve proportions.

## 8. Document Scanning

### Potential defects

- Four-corner cropping depends on the scanner plugin and requires physical
  device testing.
- Permanently denied camera permission may not provide a direct route to system
  settings.
- Interrupted scans may leave cached camera images.
- Large multi-page scans may exhaust memory during PDF generation.
- Page rotation, reordering, and per-page enhancement controls require further
  confirmation.
- Automatic edge detection may incorrectly crop receipts or low-contrast pages.

### Recommended improvements

- Add blur, glare, lighting, and capture-quality guidance.
- Provide retake, rotate, reorder, and per-page crop review.
- Downsample images using a selectable scan-quality setting.
- Preserve an interrupted scan as a draft.
- Enlarge crop handles and magnify the corner currently being adjusted.

### How the user can help

- Test receipts, glossy documents, shadows, angled pages, and white paper on a
  white surface.
- Test denied and permanently denied camera permissions.
- Test a 20-page scan on the target Motorola device.

## 9. Smart Reading

### Potential defects

- The current summary is extractive and frequency-based rather than an
  AI-generated semantic summary.
- Ranking uses English-oriented words, patterns, and stop words.
- OCR of every scanned page can be slow and battery intensive.
- Cached summaries do not account for summary-language preferences.
- Cancellation cannot interrupt a page-render or OCR operation already in
  progress.
- Sentences containing numbers or keywords may be marked important even when
  they are not contextually important.

### Recommended improvements

- Label results as **Automatic extractive summary**.
- Display source-page links and limitations.
- Add language-aware sentence and word processing.
- Process large PDFs in bounded batches.
- Allow users to summarize selected pages.
- Show incremental progress and an active Cancel action.

### How the user can help

- Compare summaries with documents whose content is well understood.
- Identify statements that were incorrectly selected or overlooked.
- Decide whether future cloud or AI summarization may send document text
  off-device. This requires an explicit privacy decision.

## 10. Personalization and Accessibility

### Potential defects

- Custom fonts may cause clipping or toolbar overflow at large accessibility
  scales.
- Icon-only controls still require complete semantic-label verification.
- Font preferences affect the application interface, not PDF-embedded text.
- The large number of settings may make features difficult to discover.
- Selected-state colors may not provide sufficient contrast in every theme.
- TalkBack focus order and modal announcements lack meaningful automated
  coverage.

### Recommended improvements

- Add **Reset appearance** and **Reset all preferences** actions.
- Group settings by Library, Reader, Annotation, Scanner, and Accessibility.
- Validate layouts at 200% font scale.
- Give every control an accessible name, hint, role, and selected state.
- Maintain touch targets of at least 48 by 48 logical pixels.

### How the user can help

- Enable Android TalkBack and navigate the application without looking at it.
- Test maximum system font and display sizes.
- Report settings that are difficult to find or understand.

## 11. Android and iOS Integration

### Potential defects

- Android **Open with** behavior varies between WhatsApp, Gmail, Drive,
  Downloads, browsers, and other file providers.
- Some providers send PDFs using a generic MIME type such as
  `application/octet-stream`.
- External files can pass through temporary storage before library import, so an
  interruption may leave temporary copies.
- iOS PDF opening is implemented, but an iOS share extension is not evident.
- iOS native automated coverage is minimal.
- Default-PDF-application selection is controlled by Android rather than the
  application.
- The Android application ID and signing identity must remain stable after
  publication.

### Recommended improvements

- Test content URIs from major Android file providers.
- Handle generic MIME types only after validating that the file is a PDF.
- Add an iOS share extension if receiving files through Share is required.
- Add native cold-start and warm-start document-delivery tests.
- Document package-name and signing-key immutability.

### How the user can help

- Open the same PDF from WhatsApp, Gmail, Google Drive, Files, Chrome, and
  Downloads.
- Report whether Papertrail appears in both **Open with** and **Share**.
- Provide access to a real iPhone and Apple signing environment for iOS
  verification.

## 12. Reliability, Privacy, and Release Management

### Potential defects

- Crash diagnostics are private, but a complete consent-based crash-report
  delivery workflow is not present.
- Broad exception handlers suppress some information needed to diagnose
  unexpected failures.
- Secure-storage fallback stores library metadata in ordinary preferences
  without notifying the user.
- Integration coverage currently contains a library launch test and an
  annotated-export test but does not cover the complete application workflow.
- End-to-end tests do not yet cover rename, delete, external opening, scanning,
  password entry, printing, or process restart.
- Temporary files can remain until a later application launch performs cleanup.
- Release signing depends on permanent keystore management and correctly
  configured repository secrets.

### Recommended improvements

- Introduce structured and privacy-redacted diagnostics.
- Distinguish expected operational errors from unexpected exceptions.
- Add fault-injection tests for disk-full, permission, partial-write, and
  process-interruption failures.
- Expand real-device integration coverage.
- Verify release signature, version progression, package identity, and upgrade
  installation in continuous integration.
- Publish backup and recovery guidance for annotation sidecars and stored
  signatures.

### How the user can help

- Preserve the Android signing key permanently and maintain secure backups.
- Configure and verify the GitHub release secrets.
- Test installing a new release over an older installed version.
- Provide sanitized crash logs and exact reproduction steps.

## Recommended Priority

Address the findings in this order:

1. Data-loss and recovery paths
2. Annotation and signature export consistency
3. Large-library search, OCR, memory, and battery usage
4. Android **Open with** and upgrade installation
5. Scanner reliability
6. Accessibility
7. Folder and duplicate-management completeness
8. Smart-summary accuracy

## Recommended Real-Device Test

The highest-value verification workflow is:

1. Open a PDF.
2. Add annotations and a visual signature.
3. Save the changes.
4. Rename the PDF.
5. Close and reopen the PDF.
6. Share an annotated copy.
7. Print the annotated document.
8. Restart the phone.
9. Open the document again.

This workflow covers the application's highest-risk data-integrity paths.

For every defect, record:

- Application version and build number
- Phone model and Android or iOS version
- PDF type, approximate size, and page count
- Exact reproduction steps
- Expected result
- Actual result
- Screenshot or screen recording
- Whether the problem remains after restarting the application
