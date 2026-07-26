import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest registers PDF open and share contracts', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android.intent.action.VIEW'));
    expect(manifest, contains('android.intent.action.SEND'));
    expect(manifest, contains('application/pdf'));
    expect(manifest, contains('android.intent.category.BROWSABLE'));
    expect(manifest, contains('android.permission.CAMERA'));
  });

  test('main branch produces a downloadable versioned Android build', () {
    final workflow = File(
      '.github/workflows/android-build-after-merge.yml',
    ).readAsStringSync();
    expect(workflow, contains('branches:'));
    expect(workflow, contains('- main'));
    expect(workflow, contains('flutter analyze'));
    expect(workflow, contains('flutter test'));
    expect(workflow, contains('flutter build apk --release'));
    expect(workflow, contains('100000 + GITHUB_RUN_NUMBER'));
    expect(workflow, contains('Papertrail-PDF-v\${VERSION_NAME}'));
    expect(workflow, contains('actions/upload-artifact@v4'));
    expect(workflow, contains('retention-days: 30'));
    expect(workflow, contains('PAPERTRAIL_KEYSTORE_BASE64'));
    expect(workflow, contains('PAPERTRAIL_KEYSTORE_PASSWORD'));
    expect(workflow, contains('PAPERTRAIL_KEY_ALIAS'));
    expect(workflow, contains('PAPERTRAIL_KEY_PASSWORD'));
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('releaseSigningConfigured'));
    expect(gradle, contains('signingConfigs.getByName("release")'));
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(File('android/key.properties.example').existsSync(), isTrue);
  });

  test('runtime reliability paths retain data and fail safely', () {
    final source = File('lib/main.dart').readAsStringSync();
    final android = File(
      'android/app/src/main/kotlin/com/papertrail/pdfreader/MainActivity.kt',
    ).readAsStringSync();
    final exporter = File('lib/annotation_export.dart').readAsStringSync();
    final summary = File('lib/pdf_summary.dart').readAsStringSync();
    final signatures = File('lib/signatures.dart').readAsStringSync();
    final ios = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final iosPlist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(source, contains('Future<void> _saveRaw(String raw)'));
    expect(source, contains('await prefs.setString(_key, raw)'));
    expect(source, contains('await _renameFile(source, target)'));
    expect(source, contains('await _performCopy(target, source)'));
    expect(source, contains('annotationSidecarPath'));
    expect(source, contains('late final Future<void> _initialization'));
    expect(source, contains('await _initialization'));
    expect(source, contains('setMethodCallHandler(null)'));
    expect(source, contains('result.failed'));
    expect(source, contains('fingerprint: document.fingerprint'));
    expect(source, contains('Override system brightness'));
    expect(source, contains('prefs.remove(\'brightness_reader\')'));
    expect(source, contains('_brightnessOverride = true'));
    expect(source, contains('PdfSummaryService.clearCache()'));
    expect(source, contains('Keep loading valid entries'));
    expect(source, contains('known.remove(fingerprint)'));
    expect(source, contains('Papertrail could not load the library.'));
    expect(source, contains('One locked temporary file'));
    expect(source, contains('512 * 1024'));
    expect(source, contains('sanitizeCrashMessage'));
    expect(summary, contains('static Future<void> clearCache()'));

    expect(android, contains('pendingPdf = pdf'));
    expect(android, contains('object : MethodChannel.Result'));
    expect(android, contains('catch (_: Exception)'));
    expect(android, contains('intent.clipData?.getItemAt(0)?.uri'));

    expect(exporter, contains('could not be rendered for export'));
    expect(exporter, contains('could not be encoded for export'));
    expect(exporter, contains('requireRenderedAnnotationPage'));
    expect(exporter, contains('requireEncodedAnnotationPage'));
    expect(exporter, contains('maximumTotalPixels'));
    expect(source, contains('Saved annotations are damaged'));
    expect(signatures, contains('AesGcm.with256bits()'));
    expect(signatures, contains('FlutterSecureStorage'));
    expect(signatures, contains('.ptsig'));
    expect(ios, contains('self?.pendingPdf = nil'));
    expect(iosPlist, isNot(contains('UIFileSharingEnabled')));
  });

  test('installation, launch, and in-app branding share one logo', () {
    final source = File('lib/main.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final adaptiveIcon = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    final androidLaunch = File(
      'android/app/src/main/res/drawable/launch_background.xml',
    ).readAsStringSync();
    final android31Launch = File(
      'android/app/src/main/res/values-v31/styles.xml',
    ).readAsStringSync();
    final iosLaunch = File(
      'ios/Runner/Base.lproj/LaunchScreen.storyboard',
    ).readAsStringSync();
    final masterIcon = File(
      'assets/branding/papertrail-icon-1024.png',
    ).readAsBytesSync();

    expect(source, contains("'assets/branding/papertrail-icon-1024.png'"));
    expect(source, isNot(contains('_PapertrailLogoPainter')));
    expect(pubspec, contains('- assets/branding/papertrail-icon-1024.png'));
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher_round"'));
    expect(adaptiveIcon, contains('@color/papertrail_brand'));
    expect(adaptiveIcon, contains('@drawable/ic_launcher_foreground'));
    expect(androidLaunch, contains('@mipmap/ic_launcher'));
    expect(android31Launch, contains('windowSplashScreenAnimatedIcon'));
    expect(iosLaunch, contains('contentMode="scaleAspectFit"'));

    for (final launchIcon in [
      'LaunchImage.png',
      'LaunchImage@2x.png',
      'LaunchImage@3x.png',
    ]) {
      expect(
        File(
          'ios/Runner/Assets.xcassets/LaunchImage.imageset/$launchIcon',
        ).readAsBytesSync(),
        orderedEquals(masterIcon),
      );
    }
  });

  test('iOS declares PDF document support', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('CFBundleDocumentTypes'));
    expect(plist, contains('com.adobe.pdf'));
    expect(plist, contains('LSSupportsOpeningDocumentsInPlace'));
    expect(plist, contains('NSCameraUsageDescription'));
  });

  test('library can scan multi-page documents into persistent PDFs', () {
    final source = File('lib/main.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('cunning_document_scanner:'));
    expect(source, contains('CunningDocumentScanner.getPictures('));
    expect(source, contains('asPdf: true'));
    expect(source, contains('noOfPages: pageLimit'));
    expect(source, contains("'Manual crop'"));
    expect(source, contains('AndroidScannerMode.base'));
    expect(source, contains('AndroidScannerMode.full'));
    expect(source, contains('AndroidScannerMode.baseWithFilter'));
    expect(source, contains("'Filter controls · Android'"));
    expect(source, contains("'scan_capture_mode'"));
    expect(
      source,
      contains(
        "'Capture, then drag all four corners to adjust width and height.'",
      ),
    );
    expect(source, contains('HeaderAction.documentScanner'));
    expect(source, contains("'Scan saved to your library.'"));
    expect(source, contains('CunningDocumentScanner.cleanCache()'));
    expect(source, contains("'Single page'"));
    expect(source, contains("'Multiple pages'"));
    expect(source, contains("'Maximum pages'"));
    expect(source, contains("'Camera and Gallery'"));
    expect(source, contains("'scan_manual_crop'"));
    expect(source, contains("'scan_single_page'"));
    expect(source, contains("'scan_page_limit'"));
    expect(source, contains("'scan_capture_source'"));
    expect(source, contains("'Save scanned PDF'"));
    expect(source, contains("'Library folder'"));
    expect(source, contains("'Add to favorites'"));
    expect(source, contains("RegExp(r'(?:\\.pdf)+\$'"));
    expect(source, contains('folder: details.folder'));
    expect(source, contains('isFavorite: details.favorite'));
    final requirements = File(
      'docs/SCANNER_IMPROVEMENTS.md',
    ).readAsStringSync();
    expect(
      requirements,
      contains('- [x] Choose single-page or multi-page scanning.'),
    );
  });

  test('settings display the installed release and build number', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('PackageInfo.fromPlatform()'));
    expect(
      source,
      contains(
        "'Version \${packageInfo.version} (Build \${packageInfo.buildNumber})'",
      ),
    );
    expect(source, contains('Icons.info_outline_rounded'));
  });

  test('appearance settings control theme, font family, size, and weight', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains("'Appearance'"));
    expect(source, contains("'Application font'"));
    expect(source, contains("'Font weight'"));
    expect(source, contains("'Font size'"));
    expect(source, contains('appFontFamilies'));
    expect(source, contains("'Sans Serif': 'sans-serif'"));
    expect(source, contains("'Inter': 'Inter'"));
    expect(source, contains("'Noto Sans': 'Noto Sans'"));
    expect(source, contains("'Roboto Condensed': 'Roboto Condensed'"));
    expect(source, contains('appFontWeights'));
    expect(source, contains('appFontScales'));
    expect(source, contains("'appearance_theme_mode'"));
    expect(source, contains("'appearance_font_family'"));
    expect(source, contains("'appearance_font_weight'"));
    expect(source, contains("'appearance_font_scale'"));
    expect(source, contains('systemScale * _fontScale'));
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: Inter'));
    expect(pubspec, contains('family: Poppins'));
    expect(pubspec, isNot(contains('assets/fonts/licenses/')));
    expect(File('assets/fonts/licenses/inter-OFL.txt').existsSync(), isTrue);
    expect(File('assets/fonts/licenses/poppins-OFL.txt').existsSync(), isTrue);
    expect(source, isNot(contains('HeaderAction.theme')));
  });

  test('open reader can rename its current PDF', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('ReaderTool.rename'));
    expect(source, contains('Future<void> _renameOpenDocument()'));
    expect(source, contains('required this.onRename'));
    expect(
      source,
      contains('final renamed = await widget.onRename(_document)'),
    );
    expect(source, contains("case 'rename':"));
  });

  test('reader enables text selection and open-file deletion', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('textSelectionParams: PdfTextSelectionParams'));
    expect(source, contains('details.type != PdfViewerGeneralTapType.tap'));
    expect(source, contains('showContextMenuAutomatically: true'));
    expect(source, contains("case 'delete':"));
    expect(source, contains("ReaderTool.delete => 'Delete PDF'"));
    expect(source, contains('_readerDeletedResult'));
  });

  test('library rows omit reading progress details', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, isNot(contains('% read')));
    expect(source, isNot(contains('document.page} of')));
  });

  test('reader supports double-tap zoom without consuming long presses', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('PdfViewerGeneralTapType.doubleTap'));
    expect(source, contains('_toggleDoubleTapZoom(details.documentPosition)'));
    expect(source, contains('calcMatrixForFit(pageNumber: _page)'));
    expect(source, contains('if (_doubleTapZoomedIn)'));
    expect(source, contains('await _controller.goTo(fitMatrix)'));
    expect(source, contains('currentZoom * 2'));
    expect(source, isNot(contains('final minimumZoom = _controller.minScale')));
    expect(source, isNot(contains('final fitTolerance =')));
    expect(source, contains('details.type != PdfViewerGeneralTapType.tap'));
  });

  test('reader provides touch-friendly text-selection controls', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('buildContextMenu: _buildSelectionContextMenu'));
    expect(source, contains('buildSelectionHandle: _buildSelectionHandle'));
    expect(source, contains('PdfViewerSelectionMagnifierParams'));
    expect(source, contains("PapertrailNotice.show(context, 'Text copied'"));
    expect(source, contains("'text_selection_magnifier'"));
    expect(source, contains('enabled: _showTextSelectionMagnifier'));
  });

  test('move-to-folder is hidden until a library folder exists', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('if (_folders.isNotEmpty)'));
    expect(source, contains('if (_folders.isEmpty) return;'));
  });

  test('settings live in the drawer and save without a Done button', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('children: [_buildDrawerSettings()]'));
    expect(source, contains('_saveSettingList('));
    expect(source, isNot(contains("child: const Text('Done')")));
    expect(source, isNot(contains('_showAppSettings')));
    expect(source, contains("title: 'In-app messages'"));
    expect(source, contains('PapertrailNotice.preferenceKey'));
    expect(source, contains('class PapertrailLogo extends StatelessWidget'));
    expect(source, contains('PapertrailLogo(size: 40)'));
    expect(source, contains('PapertrailLogo(size: 26)'));
  });

  test('signature tool supports saved drawing and image workflows', () {
    final annotations = File('lib/annotations.dart').readAsStringSync();
    expect(annotations, contains("Text('Draw new')"));
    expect(annotations, contains("Text('Import image')"));
    expect(annotations, contains('_selectedSignature'));
    expect(annotations, contains('SignaturePreview'));
    expect(annotations, contains('AnnotationTool? _tool;'));
    expect(annotations, contains('Icons.border_color_outlined'));
    expect(annotations, contains('class _SignatureToolIcon'));
    expect(annotations, contains('Icons.gesture'));
    expect(annotations, contains('Icons.edit_rounded'));
  });

  test('external PDFs use branded loading and reader transitions', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('class _OpeningPdfOverlay'));
    expect(source, contains("'Opening PDF…'"));
    expect(source, contains('PageRouteBuilder<int>'));
    expect(source, contains('loadingBannerBuilder:'));
    expect(source, contains('_PdfLoadingView(fileName: _document.name)'));
    expect(source, contains("label: 'Preparing \$fileName'"));
  });

  test('primary action opens PDFs without routine import banners', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains("label: const Text('Open PDF')"));
    expect(source, contains('Icons.file_open_outlined'));
    expect(source, contains('allowMultiple: false'));
    expect(source, contains('await _open(result.selected!)'));
    expect(source, isNot(contains('PDF added to your library.')));
    expect(source, isNot(contains('This PDF is already in your library.')));
  });

  test('library supports bulk selection actions', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('_selectedDocumentPaths'));
    expect(source, contains('_deleteSelectedFromDevice'));
    expect(source, contains('_removeSelectedFromLibrary'));
    expect(source, contains('_moveSelectedToFolder'));
    expect(source, contains('HeaderAction.createFolder'));
    expect(source, contains('_folders.isNotEmpty'));
  });

  test('reader header saves only dirty annotation changes', () {
    final source = File('lib/main.dart').readAsStringSync();
    final annotations = File('lib/annotations.dart').readAsStringSync();
    expect(source, contains('if (_annotationsDirty)'));
    expect(source, contains("tooltip: 'Save annotation changes'"));
    expect(source, contains('_annotationKey.currentState?.save()'));
    expect(annotations, contains('widget.onDirtyChanged(true)'));
    expect(annotations, contains('widget.onDirtyChanged(false)'));
  });

  test('library exposes a dedicated favorites filter', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('bool _favoritesOnly = false;'));
    expect(source, contains("label: const Text('Favorites')"));
    expect(source, contains('(!_favoritesOnly || document.isFavorite)'));
  });

  test('smart reading is configurable and available in the reader', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains("title: 'PDF summaries'"));
    expect(source, contains("title: 'Important information highlights'"));
    expect(source, contains("'pdf_summaries_enabled'"));
    expect(source, contains("'important_highlights_enabled'"));
    expect(source, contains("value: 'summarize'"));
    expect(source, contains('PdfSummaryService'));
  });

  test('an open PDF can be shared from reader tools', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('ReaderTool.share'));
    expect(source, contains("ReaderTool.share => 'Share PDF'"));
    expect(source, contains("ReaderTool.share: 'share'"));
    expect(source, contains('_shareOpenDocument()'));
    expect(source, contains('AnnotationExporter'));
    expect(source, contains('files: [XFile(exported.path)]'));
  });

  test('selected library sort persists and library search is configurable', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains("'selected_library_sort'"));
    expect(source, contains('await prefs.setString'));
    expect(source, contains('_saveSelectedSort(sort)'));
    expect(source, contains("title: 'Library search'"));
    expect(source, contains("'show_library_search'"));
    expect(source, contains('if (_showLibrarySearch)'));
  });

  test('library exposes an uncategorized PDF section', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('bool _uncategorizedOnly = false;'));
    expect(source, contains("label: const Text('Uncategorized')"));
    expect(source, contains('document.folder == null'));
    expect(source, contains("document.folder!.trim().isEmpty"));
  });

  test('options use icons and expose active selections', () {
    final source = File('lib/main.dart').readAsStringSync();
    final annotations = File('lib/annotations.dart').readAsStringSync();
    expect(source, contains('IconData librarySortIcon'));
    expect(source, contains('IconData readerToolIcon'));
    expect(source, contains('IconData headerActionIcon'));
    expect(source, contains('secondary: Icon(icon)'));
    expect(source, contains('selected: value'));
    expect(source, contains('_isReaderToolSelected'));
    expect(source, contains('Icons.check_circle_rounded'));
    expect(source, contains('Size.square(48)'));
    expect(source, contains('WidgetState.selected'));
    expect(source, contains("'Document actions'"));
    expect(source, contains("'Remove from Papertrail'"));
    expect(source, contains("'Loading your PDF library…'"));
    expect(source, contains("'Preparing \${_document.name} for sharing…'"));
    expect(annotations, contains("'Nothing to undo'"));
    expect(annotations, contains("'No annotation changes to save'"));
    expect(annotations, contains('bool _dirty = false'));
  });

  test('annotations are page-owned and saves are protected', () {
    final source = File('lib/main.dart').readAsStringSync();
    final annotations = File('lib/annotations.dart').readAsStringSync();
    expect(source, contains('pageOverlaysBuilder:'));
    expect(source, contains('layer.buildPageOverlay(page.pageNumber)'));
    expect(source, contains('_closeReader()'));
    expect(source, contains("'Save annotation changes?'"));
    expect(annotations, contains('class _AnnotationPageSurface'));
    expect(annotations, contains('mark.page == page'));
    expect(annotations, contains('_writeAtomically'));
    expect(annotations, contains('while (_saveInProgress != null)'));
    expect(annotations, contains('Future<void> waitForPendingSave()'));
  });

  test('search indexing is cached, serialized, and path-consistent', () {
    final source = File('lib/main.dart').readAsStringSync();
    final search = File('lib/library_search.dart').readAsStringSync();
    expect(source, contains('unawaited(_indexDocuments(documents))'));
    expect(
      source,
      contains('_searchIndex.rename(document.path, renamed.path)'),
    );
    expect(source, contains('_searchIndex.remove(document.path)'));
    expect(search, contains('if (await contains(path)) return;'));
    expect(search, contains('_writeQueue.then'));
    expect(search, contains('await Future<void>.delayed(Duration.zero)'));
  });

  test('iOS forwards opened PDFs through the Flutter channel', () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(delegate, contains('FlutterMethodChannel'));
    expect(delegate, contains('getInitialPdf'));
    expect(delegate, contains('openPdf'));
    expect(delegate, contains('startAccessingSecurityScopedResource'));
    expect(delegate, contains('cachePdf'));
  });

  test('summaries expose progress, cancellation, OCR, and caching', () {
    final source = File('lib/main.dart').readAsStringSync();
    final summary = File('lib/pdf_summary.dart').readAsStringSync();
    expect(source, contains("'Summarizing PDF'"));
    expect(source, contains("child: const Text('Cancel')"));
    expect(summary, contains('onProgress'));
    expect(summary, contains('isCancelled'));
    expect(summary, contains('_searchIndex.indexPdf'));
    expect(summary, contains('_loadCached'));
    expect(summary, contains('_saveCached'));
  });

  test('horizontal sections provide functional navigation buttons', () {
    final source = File('lib/main.dart').readAsStringSync();
    final annotations = File('lib/annotations.dart').readAsStringSync();
    final cues = File('lib/horizontal_scroll_cue.dart').readAsStringSync();
    expect(
      'HorizontalScrollCue'.allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
    expect(annotations, contains('HorizontalScrollCue'));
    expect(cues, contains('Show previous items'));
    expect(cues, contains('Show more items'));
    expect(cues, contains('_controller.animateTo'));
    expect(cues, contains('onPressed: onPressed'));
    expect(cues, contains('TextDirection.rtl'));
    expect(cues, contains('Icons.chevron_right_rounded'));
  });
}
