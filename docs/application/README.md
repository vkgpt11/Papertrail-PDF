# Papertrail PDF Application Documentation

Papertrail PDF is a mobile PDF reader and document productivity application for
Android and iOS. It combines reading, searching, annotation, signing, scanning,
organization, and mobile-platform integration in one application.

This document describes the 12 principal functional areas covered by the
application.

For the corresponding defect, improvement, and verification review, see
[Defects and Improvements Audit](DEFECTS_AND_IMPROVEMENTS.md).

For Android signing and automated APK deployment, see
[Android Release Signing and GitHub Deployment](../deployment/ANDROID_RELEASE_SIGNING.md).

## 1. PDF Library Management

The PDF library provides a central place for users to manage documents available
to Papertrail PDF.

Key capabilities include:

- Discovering and listing accessible PDF files
- Opening PDFs from the library or device storage
- Importing PDFs into the application library
- Displaying document metadata such as name, size, page count, and dates
- Renaming individual PDF files
- Deleting individual or multiple PDF files
- Removing documents from the application without deleting the device file
- Selecting multiple PDFs for bulk operations
- Moving documents into application folders
- Sharing and exporting documents
- Detecting and managing duplicate files
- Refreshing document metadata
- Reporting import progress and errors
- Sorting documents by supported metadata

## 2. Folder Organization

Folder organization helps users manage a large document collection without
changing the contents of the PDFs.

Key capabilities include:

- Creating application library folders
- Renaming and deleting library folders
- Moving one or multiple PDFs between folders
- Showing the number of documents in each folder
- Providing an **All** section for the complete library
- Providing an **Uncategorized** section for documents without a folder
- Providing a **Favorites** section for pinned documents
- Hiding folder-dependent actions when no library folder exists
- Providing visual cues when additional folders are available horizontally

Application folders are organizational metadata. They do not necessarily
represent or modify physical folders on the device.

## 3. PDF Reading

The reader is responsible for displaying PDFs clearly and maintaining a
comfortable reading experience across phones, tablets, and foldable devices.

Key capabilities include:

- Vertical, horizontal, and two-page viewing modes
- Fit-width and fit-page controls
- Pinch-to-zoom and configurable double-tap zoom
- Returning from double-tap zoom to a fit-to-screen view
- Page rotation
- Full-screen reading
- Configurable page spacing and background
- Right-to-left document navigation
- Night and sepia reading modes
- Screen-brightness control
- Keeping the screen awake while reading
- Remembering zoom level and reading position
- Optimized handling of large PDFs
- Friendly handling of damaged and password-protected documents

## 4. Document Navigation

Navigation features help users move efficiently through short and long
documents.

Key capabilities include:

- Page-thumbnail navigation
- Jumping directly to a validated page number
- PDF bookmark creation and navigation
- Table-of-contents navigation
- Current-page indicators
- A setting to show or hide bottom page controls
- Recently opened documents
- Recovery of the most recently closed document
- Visual cues when more recent documents are available horizontally

Bookmarks identify important locations inside a document. They do not modify the
original PDF unless explicitly exported into it.

## 5. Text Interaction and Search

Text and search tools help users locate, select, and reuse information.

Key capabilities include:

- Selecting text from text-based PDFs
- Copying selected text
- Searching within the currently open PDF
- Searching across all indexed PDFs
- Displaying page numbers and bounded result snippets
- Remembering recent searches
- Filtering by folder, date, page count, and file size
- OCR-assisted search for scanned documents
- Caching search results and document indexes
- Removing or updating index entries after rename and deletion

Text selection depends on a PDF containing a usable text layer. Image-only scans
require OCR before their text can be searched or selected.

## 6. Annotations

Annotation tools allow users to add review and markup information without losing
the relationship between each annotation and its PDF page.

Key capabilities include:

- Text highlighting
- Underlining and strikethrough
- Freehand drawing
- Text notes and comments
- Shapes and stamps
- Draggable annotation placement
- Page-specific annotation coordinates
- Undo and redo
- Saving only when annotation changes are pending
- Exporting annotations with the visible document
- Visual indicators for selected annotation tools
- Configurable annotation toolbar options
- No annotation tool selected by default

Annotations are stored using page-aware coordinates so that they remain tied to
the correct page during scrolling, zooming, rotation, and layout changes.

## 7. Signatures

Signature functionality allows a user to prepare and place a visual signature
on a PDF.

Key capabilities include:

- Drawing a signature in the application
- Importing a signature from an image file
- Saving reusable signatures securely
- Placing a signature on a specific PDF page
- Dragging and repositioning a signature
- Preserving its position relative to the PDF page
- Saving signature changes through the annotation workflow
- Including signatures when producing an annotated export

A visual signature is not automatically equivalent to a certificate-backed
cryptographic digital signature. The application should clearly distinguish
between these concepts wherever legal assurance is relevant.

## 8. Document Scanning

The scanner converts physical pages or camera images into PDFs that can be added
to the library.

Key capabilities include:

- Manual camera capture
- Multi-page scanning
- Previewing captured pages
- Adjusting the capture width and height
- Dragging four corners to correct document boundaries
- Cropping and perspective correction
- Reordering or removing captured pages
- Producing a persistent PDF
- Reporting capture, processing, and save errors

Scanning should provide clear capture guidance, stable edge detection, readable
output, and a review step before the PDF is saved.

## 9. OCR-Assisted Search

OCR-assisted search keeps scanned and image-only PDFs discoverable without
introducing document summarization. Smart Reading, PDF summaries, and automatic
important-information extraction are intentionally unavailable.

Key capabilities include:

- On-device OCR indexing for scanned documents
- Content-search matches linked to source pages
- No summary generation or summary cache
- No PDF content sent to a summarization service
## 10. Personalization and Accessibility

Personalization lets users adjust the application to their reading needs while
accessibility features keep controls understandable and operable.

Key capabilities include:

- Light, dark, night, and sepia appearance options
- Configurable application font family
- Font size and font weight controls
- Supported Android-friendly font choices
- Configurable reader header actions
- Configurable annotation and sorting controls
- Configurable page indicators, zoom behavior, and notifications
- Clear icons and visible selected states
- Collapsible settings sections
- Settings that save immediately without a separate Done action
- Screen-reader labels and semantic controls
- Responsive phone, tablet, and foldable layouts
- Touch-friendly interaction targets

Reader font preferences affect application controls and labels; they do not
replace fonts embedded inside PDF page content.

## 11. Android and iOS Integration

Platform integration allows Papertrail PDF to participate in normal mobile file
workflows.

Key capabilities include:

- Android **Open with** support across compatible file providers
- Receiving PDFs from the Android Share menu
- Eligibility to become the default PDF application
- Branded loading while an externally opened file is prepared
- Correct back-button and deep-link behavior
- System print-dialog integration
- iOS PDF document-type registration
- Receiving incoming iOS document URLs
- iOS document-provider and share-sheet integration
- Consistent application name, icon, and release information

Platform behavior must be verified on real devices because file providers,
permissions, default-application handling, and share sheets vary by OS version
and installed applications.

## 12. Reliability, Privacy, and Release Management

This area protects user documents, improves recoverability, and ensures that
releases are reproducible.

Key capabilities include:

- Password-protected PDF handling
- Damaged-document error handling
- Low-memory thumbnail caching
- Avoiding unnecessary PDF opening or OCR during scrolling and startup
- Automatic cleanup of bounded temporary files
- Transactional rename, delete, annotation, and recovery behavior
- Keeping annotation sidecars consistent with renamed documents
- Keeping search indexes synchronized with file operations
- Privacy-respecting crash diagnostics
- Encrypted storage for sensitive local preferences and signatures
- Unit, widget, integration, and large-file tests
- Testing across Android versions and screen sizes
- Signed Android release builds
- Versioned APK names
- Continuous-integration checks and build generation after merges

Reliability work gives priority to preventing document loss, annotation loss,
signature loss, and inconsistent on-disk state.

## Product Scope Summary

These areas serve five broader user needs:

1. Reading and navigating documents
2. Searching for and understanding information
3. Annotating and signing documents
4. Scanning, organizing, and managing files
5. Sharing, printing, and integrating with mobile workflows

Papertrail PDF should therefore be treated as a PDF document-management and
productivity application rather than only a basic PDF viewer.
