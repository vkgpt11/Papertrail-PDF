# Papertrail Document Scanner Improvements

This document is the implementation and testing reference for Papertrail's
document-scanning experience on Android and iOS.

## Current implementation

- Scan paper documents using the device camera.
- Capture a configurable number of pages into one PDF.
- Automatic edge detection, cropping, and enhancement.
- Automatic and manual-crop capture choices.
- Four-corner adjustment in manual-crop mode.
- Perspective correction after adjusting the corners.
- Save completed scans into Papertrail's private library.
- Generate a unique timestamped filename.
- Open the new PDF immediately after saving.
- Index the scanned PDF for library search.
- Remove temporary scanner files after completion.
- Friendly handling of cancellation, denied permission, and scanner errors.
- Camera permission declarations for Android and iOS.

## Scanner to-do list

Items marked `[x]` are implemented and tested. Items marked `[ ]` remain in
the implementation backlog.

## Required capture improvements

### Scan setup

- [x] Choose single-page or multi-page scanning.
- [x] Choose Camera, Gallery, or Camera and Gallery.
- [x] Configure the maximum page count instead of always using 50.
- [x] Remember the most recently used scanner settings.
- [x] Provide a short explanation of each scan mode.

### Capture modes

- [x] Automatic: detect, crop, and enhance document edges.
- [x] Manual crop: capture first, then drag all four corners.
- [x] Original color: preserve the captured colors.
- [x] Enhanced color: improve contrast and page readability.
- [x] Grayscale: reduce color noise while preserving detail.
- [x] Black and white: optimize text-heavy documents.
- [x] Clearly identify options that are unavailable on a platform.

### Capture guidance

- [ ] Indicate when the full document is not visible.
- [ ] Warn when the device is too close or too far away.
- [ ] Detect and report blur or camera movement.
- [ ] Warn about low light, shadows, and glare.
- [ ] Provide an optional automatic-capture countdown when the page is stable.
- [ ] Make flash and automatic-flash controls easy to reach.

Real-time blur, glare, lighting, and stability analysis requires a custom
camera pipeline and is not fully exposed by the current native scanner plugin.

### Manual four-corner cropping

- [x] Show large, touch-friendly handles for all four corners.
- [x] Magnify the area beneath the actively dragged handle.
- [x] Keep handles inside the image boundaries.
- [ ] Prevent corner lines from crossing.
- [x] Initialize the handles from automatically detected edges.
- [ ] Provide Reset to detected edges and Reset to full image actions.
- [x] Allow rotation before confirming the crop.
- [x] Apply perspective correction to the selected quadrilateral.
- [x] Preserve each page's crop independently in a multi-page scan.

The checked manual-crop behaviors are supplied by the pinned native scanner
engine. Reset actions and corner-crossing prevention remain open until they are
implemented directly and verified on physical Android and iOS devices.

## Required review experience

Before creating the final PDF, provide a page-review screen that allows users
to:

- [ ] Preview every captured page as a thumbnail.
- [ ] Open a full-page preview.
- [ ] Reorder pages.
- [ ] Rotate individual pages.
- [ ] Re-crop individual pages.
- [ ] Retake an individual page.
- [ ] Delete unwanted pages.
- [ ] Add more pages.
- [ ] Review the selected filter and quality.
- [ ] Cancel without leaving temporary files behind.

## Required output options

- [ ] Compact, Balanced, and High-quality output presets.
- [ ] Display an estimated PDF size before saving when practical.
- [x] Allow the filename to be edited before saving.
- [x] Ensure `.pdf` is added exactly once.
- [x] Select a Papertrail library folder before saving.
- [x] Hide folder selection when library folders are disabled or unavailable.
- [x] Optionally mark the new PDF as a favorite.
- [ ] Report save and indexing progress for large scans.
- [x] Never overwrite an existing PDF without confirmation.

## Accessibility and usability

- [ ] Add screen-reader labels to every capture, crop, and review action.
- [ ] Do not rely on color alone to identify the selected mode.
- [ ] Maintain at least 48-by-48 logical-pixel touch targets.
- [ ] Support large Android accessibility font sizes without overflow.
- [ ] Support portrait and landscape layouts.
- [ ] Support tablets and foldable devices.
- [ ] Respect light, dark, font-family, font-size, and font-weight preferences.
- [ ] Keep destructive actions clearly separated from confirmation actions.

## Privacy, reliability, and performance

- [ ] Perform capture and document processing on-device where supported.
- [ ] Do not upload scanned pages without explicit user consent.
- [ ] Remove abandoned temporary images and PDFs automatically.
- [ ] Avoid holding every full-resolution page in memory simultaneously.
- [ ] Compress pages incrementally for large scans.
- [ ] Handle application backgrounding and interrupted scanner activities.
- [ ] Recover an unfinished scan when safe and practical.
- [ ] Handle camera denial with a clear path to system settings.
- [ ] Handle low storage before beginning final PDF generation.
- [ ] Avoid duplicate library entries when saving or retrying.

## Platform notes

### Android

- The native engine supports automatic, base, and filtered scan modes.
- Manual crop uses the base capture/review flow.
- Camera and gallery availability may vary with Google Play Services and device
  capabilities.
- Verify behavior on Android 6 through the current Android release, including
  low-memory devices.

### iOS

- VisionKit controls much of the native camera and document-capture interface.
- VisionKit does not expose the same scanner-mode and filter controls as
  Android.
- A custom post-processing pipeline is required for identical cross-platform
  color filters.
- Verify camera permission, cancellation, rotation, and multi-page behavior on
  physical iPhones and iPads.

## Acceptance criteria

A scanner improvement is complete only when:

1. Cancellation returns safely to the library without creating a blank entry.
2. Every confirmed page appears once and in the selected order.
3. Manual crop output matches the four selected corners.
4. Rotation and perspective correction are preserved in the final PDF.
5. The completed PDF can be opened, searched, renamed, moved, shared, printed,
   annotated, and deleted like an imported PDF.
6. Temporary source images are removed after success or cancellation.
7. Settings persist across application restarts.
8. The interface has no overflow on supported phone, tablet, and accessibility
   text-size configurations.

## Test coverage required

- [ ] Unit tests for scanner settings, filenames, destination selection, and
  cleanup decisions.
- [ ] Widget tests for scan setup, selected-state indicators, manual-crop
  instructions, review actions, and responsive layouts.
- [ ] Android integration tests for automatic and manual capture results.
- [ ] iOS integration tests on a physical device.
- [ ] Multi-page ordering, rotation, re-crop, retake, and deletion tests.
- [ ] Permission denied, camera unavailable, low storage, damaged output, and
  interrupted activity tests.
- [ ] Large-scan memory and temporary-file cleanup tests.
