import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'annotations.dart';
import 'annotation_export.dart';
import 'library_search.dart';
import 'library_logic.dart';
import 'notifications.dart';
import 'pdf_summary.dart';
import 'horizontal_scroll_cue.dart';

const _readerDeletedResult = -1;

const appFontFamilies = <String, String?>{
  'Sans Serif': 'sans-serif',
  'Inter': 'Inter',
  'Noto Sans': 'Noto Sans',
  'Roboto': 'Roboto',
  'Open Sans': 'Open Sans',
  'Lato': 'Lato',
  'Nunito Sans': 'Nunito Sans',
  'Poppins': 'Poppins',
  'Montserrat': 'Montserrat',
  'DM Sans': 'DM Sans',
  'Roboto Condensed': 'Roboto Condensed',
};

const appFontWeights = <String, int>{
  'Regular': 400,
  'Medium': 500,
  'Semi-bold': 600,
  'Bold': 700,
};

const appFontScales = <String, double>{
  'Small': .9,
  'Default': 1,
  'Large': 1.15,
  'Extra large': 1.3,
};

class PapertrailLogo extends StatelessWidget {
  const PapertrailLogo({this.size = 32, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Papertrail PDF logo',
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size * .22),
      child: Image.asset(
        'assets/branding/papertrail-icon-1024.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
    ),
  );
}

class _OpeningPdfOverlay extends StatelessWidget {
  const _OpeningPdfOverlay({required this.fileName});

  final String fileName;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black38,
    child: SafeArea(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: .94, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Card(
            elevation: 14,
            margin: const EdgeInsets.all(28),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PapertrailLogo(size: 52),
                  const SizedBox(height: 20),
                  Text(
                    'Opening PDF…',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const LinearProgressIndicator(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _PdfLoadingView extends StatelessWidget {
  const _PdfLoadingView();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PapertrailLogo(size: 48),
          const SizedBox(height: 18),
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 14),
          const Text(
            'Preparing your document…',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

int? validPageTarget(String value, int pageCount) {
  final page = int.tryParse(value.trim());
  if (page == null || page < 1 || page > pageCount) return null;
  return page;
}

Future<void> deleteDocumentArtifacts(String pdfPath) async {
  for (final path in [pdfPath, '$pdfPath.papertrail-annotations.json']) {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  unawaited(_cleanupTemporaryFiles());
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(_writePrivateCrashLog(details.exceptionAsString()));
  };
  runApp(const PapertrailApp());
}

Future<void> _cleanupTemporaryFiles() async {
  final now = DateTime.now();
  for (final directory in [
    Directory.systemTemp,
    await getTemporaryDirectory(),
  ]) {
    if (!await directory.exists()) continue;
    await for (final entity in directory.list()) {
      if (entity is! File ||
          (!entity.path.contains('papertrail-ocr-') &&
              !entity.path.contains('incoming-') &&
              !entity.path.contains('papertrail-annotated-'))) {
        continue;
      }
      final modified = (await entity.stat()).modified;
      if (now.difference(modified) > const Duration(hours: 24)) {
        await entity.delete();
      }
    }
  }
}

Future<void> _writePrivateCrashLog(String message) async {
  try {
    final directory = await getApplicationSupportDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}papertrail-crash.log',
    );
    await file.writeAsString(
      '${DateTime.now().toIso8601String()} $message\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {
    // Diagnostics are local-only and must never cause another failure.
  }
}

class PapertrailApp extends StatefulWidget {
  const PapertrailApp({super.key});

  @override
  State<PapertrailApp> createState() => _PapertrailAppState();
}

class _PapertrailAppState extends State<PapertrailApp> {
  ThemeMode _themeMode = ThemeMode.system;
  String? _fontFamily;
  int _fontWeight = 400;
  double _fontScale = 1;

  @override
  void initState() {
    super.initState();
    _loadAppearance();
  }

  Future<void> _loadAppearance() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('appearance_theme_mode');
    final savedFont = prefs.getString('appearance_font_family');
    final savedWeight = prefs.getInt('appearance_font_weight');
    final savedScale = prefs.getDouble('appearance_font_scale');
    if (!mounted) return;
    setState(() {
      _themeMode =
          ThemeMode.values
              .where((mode) => mode.name == savedTheme)
              .firstOrNull ??
          ThemeMode.system;
      _fontFamily = appFontFamilies.containsValue(savedFont) ? savedFont : null;
      _fontWeight = appFontWeights.containsValue(savedWeight)
          ? savedWeight!
          : 400;
      _fontScale = appFontScales.containsValue(savedScale) ? savedScale! : 1;
    });
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('appearance_theme_mode', mode.name);
  }

  Future<void> _setFontFamily(String? family) async {
    setState(() => _fontFamily = family);
    final prefs = await SharedPreferences.getInstance();
    if (family == null) {
      await prefs.remove('appearance_font_family');
    } else {
      await prefs.setString('appearance_font_family', family);
    }
  }

  Future<void> _setFontWeight(int weight) async {
    setState(() => _fontWeight = weight);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('appearance_font_weight', weight);
  }

  Future<void> _setFontScale(double scale) async {
    setState(() => _fontScale = scale);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('appearance_font_scale', scale);
  }

  TextTheme _applyAppearance(TextTheme theme) {
    TextStyle? apply(TextStyle? style) => style?.copyWith(
      fontFamily: _fontFamily,
      fontWeight: FontWeight.values[_fontWeight ~/ 100 - 1],
    );
    return theme.copyWith(
      displayLarge: apply(theme.displayLarge),
      displayMedium: apply(theme.displayMedium),
      displaySmall: apply(theme.displaySmall),
      headlineLarge: apply(theme.headlineLarge),
      headlineMedium: apply(theme.headlineMedium),
      headlineSmall: apply(theme.headlineSmall),
      titleLarge: apply(theme.titleLarge),
      titleMedium: apply(theme.titleMedium),
      titleSmall: apply(theme.titleSmall),
      bodyLarge: apply(theme.bodyLarge),
      bodyMedium: apply(theme.bodyMedium),
      bodySmall: apply(theme.bodySmall),
      labelLarge: apply(theme.labelLarge),
      labelMedium: apply(theme.labelMedium),
      labelSmall: apply(theme.labelSmall),
    );
  }

  ThemeData _theme(Brightness brightness) {
    const seed = Color(0xFF5B5BD6);
    final dark = brightness == Brightness.dark;
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
      ),
      useMaterial3: true,
      fontFamily: _fontFamily,
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: seed.withValues(alpha: dark ? .42 : .32),
        selectionHandleColor: seed,
      ),
      scaffoldBackgroundColor: dark
          ? const Color(0xFF111116)
          : const Color(0xFFF7F7FB),
    );
    return base.copyWith(textTheme: _applyAppearance(base.textTheme));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Papertrail PDF',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        final systemScale = mediaQuery.textScaler.scale(1);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(systemScale * _fontScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: LibraryScreen(
        themeMode: _themeMode,
        fontFamily: _fontFamily,
        fontWeight: _fontWeight,
        fontScale: _fontScale,
        onThemeModeChanged: _setThemeMode,
        onFontFamilyChanged: _setFontFamily,
        onFontWeightChanged: _setFontWeight,
        onFontScaleChanged: _setFontScale,
      ),
    );
  }
}

class RecentDocument {
  const RecentDocument({
    required this.name,
    required this.path,
    required this.openedAt,
    required this.documentDate,
    this.fileSize = 0,
    this.pageCount = 0,
    this.page = 1,
    this.hasBeenOpened = true,
    this.fingerprint,
    this.folder,
    this.isFavorite = false,
  });

  final String name;
  final String path;
  final DateTime openedAt;
  final DateTime documentDate;
  final int fileSize;
  final int pageCount;
  final int page;
  final bool hasBeenOpened;
  final String? fingerprint;
  final String? folder;
  final bool isFavorite;

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'openedAt': openedAt.toIso8601String(),
    'documentDate': documentDate.toIso8601String(),
    'fileSize': fileSize,
    'pageCount': pageCount,
    'page': page,
    'hasBeenOpened': hasBeenOpened,
    'fingerprint': fingerprint,
    'folder': folder,
    'isFavorite': isFavorite,
  };

  factory RecentDocument.fromJson(Map<String, dynamic> json) => RecentDocument(
    name: json['name'] as String,
    path: json['path'] as String,
    openedAt: DateTime.parse(json['openedAt'] as String),
    documentDate:
        DateTime.tryParse(json['documentDate'] as String? ?? '') ??
        DateTime.parse(json['openedAt'] as String),
    fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
    pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
    page: (json['page'] as num?)?.toInt() ?? 1,
    hasBeenOpened: json['hasBeenOpened'] as bool? ?? true,
    fingerprint: json['fingerprint'] as String?,
    folder: json['folder'] as String?,
    isFavorite: json['isFavorite'] as bool? ?? false,
  );

  RecentDocument copyWith({
    String? name,
    String? path,
    DateTime? openedAt,
    DateTime? documentDate,
    int? fileSize,
    int? pageCount,
    int? page,
    bool? hasBeenOpened,
    String? fingerprint,
    String? folder,
    bool clearFolder = false,
    bool? isFavorite,
  }) => RecentDocument(
    name: name ?? this.name,
    path: path ?? this.path,
    openedAt: openedAt ?? this.openedAt,
    documentDate: documentDate ?? this.documentDate,
    fileSize: fileSize ?? this.fileSize,
    pageCount: pageCount ?? this.pageCount,
    page: page ?? this.page,
    hasBeenOpened: hasBeenOpened ?? this.hasBeenOpened,
    fingerprint: fingerprint ?? this.fingerprint,
    folder: clearFolder ? null : folder ?? this.folder,
    isFavorite: isFavorite ?? this.isFavorite,
  );
}

class DocumentStore {
  static const _key = 'recent_documents_v1';
  static const _foldersKey = 'library_folders_v1';
  static const _secureStorage = FlutterSecureStorage();

  Future<List<RecentDocument>> load() async {
    final prefs = await SharedPreferences.getInstance();
    String? raw;
    try {
      raw = await _secureStorage.read(key: _key);
    } catch (_) {
      // Unit/widget tests and unsupported desktops may not provide a keychain.
    }
    raw ??= prefs.getString(_key);
    if (raw == null) return [];
    try {
      final stored = (jsonDecode(raw) as List).map(
        (item) => RecentDocument.fromJson(item as Map<String, dynamic>),
      );
      final fingerprints = <String>{};
      final unique = <RecentDocument>[];
      var changed = false;
      for (final document in stored) {
        final file = File(document.path);
        if (!await file.exists()) {
          changed = true;
          continue;
        }
        final fingerprint = document.fingerprint ?? await _fingerprint(file);
        if (!fingerprints.add(fingerprint)) {
          changed = true;
          continue;
        }
        var updated = document.copyWith(fingerprint: fingerprint);
        final recoveredPage = prefs.getInt('resume_$fingerprint');
        if (recoveredPage != null && recoveredPage > 0) {
          updated = updated.copyWith(page: recoveredPage, hasBeenOpened: true);
        }
        if (document.fileSize <= 0 || document.pageCount <= 0) {
          updated = await _withFileDetails(updated, file);
          changed = true;
        }
        unique.add(updated);
        changed = changed || document.fingerprint == null;
      }
      if (changed) {
        await _secureStorage.write(
          key: _key,
          value: jsonEncode(unique.map((item) => item.toJson()).toList()),
        );
      }
      return unique;
    } catch (_) {
      return [];
    }
  }

  Future<String> _fingerprint(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Future<DateTime> _documentDate(File file) async {
    final fallback = (await file.stat()).modified;
    RandomAccessFile? input;
    try {
      input = await file.open();
      final bytes = await input.read((await input.length()).clamp(0, 1048576));
      final text = latin1.decode(bytes, allowInvalid: true);
      final match = RegExp(
        r'/CreationDate\s*\(\s*D:(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})',
      ).firstMatch(text);
      if (match == null) return fallback;
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    } catch (_) {
      return fallback;
    } finally {
      await input?.close();
    }
  }

  Future<RecentDocument> _withFileDetails(
    RecentDocument document,
    File file,
  ) async {
    final fileSize = await file.length();
    var pageCount = document.pageCount;
    PdfDocument? pdf;
    try {
      pdf = await PdfDocument.openFile(file.path);
      pageCount = pdf.pages.length;
    } catch (_) {
      // Keep the document usable even when metadata cannot be read.
    } finally {
      await pdf?.dispose();
    }
    return document.copyWith(fileSize: fileSize, pageCount: pageCount);
  }

  Future<void> save(List<RecentDocument> documents) async {
    await _secureStorage.write(
      key: _key,
      value: jsonEncode(documents.map((item) => item.toJson()).toList()),
    );
  }

  Future<List<String>> loadFolders() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_foldersKey) ?? <String>[];
  }

  Future<void> saveFolders(List<String> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_foldersKey, folders);
  }

  Future<RecentDocument> rename(
    RecentDocument document,
    String requestedName,
  ) async {
    var name = requestedName.trim();
    if (name.isEmpty) throw const FormatException('A name is required.');
    if (!name.toLowerCase().endsWith('.pdf')) name = '$name.pdf';
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
    final source = File(document.path);
    final separator = Platform.pathSeparator;
    final parent = source.parent.path;
    var target = File('$parent$separator$safeName');
    if (target.path.toLowerCase() != source.path.toLowerCase() &&
        await target.exists()) {
      final base = safeName.substring(0, safeName.length - 4);
      target = File(
        '$parent$separator$base-${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    }
    if (target.path != source.path) {
      await source.rename(target.path);
      final sourceAnnotations = File(
        '${source.path}.papertrail-annotations.json',
      );
      if (await sourceAnnotations.exists()) {
        final targetAnnotations = File(
          '${target.path}.papertrail-annotations.json',
        );
        try {
          await sourceAnnotations.rename(targetAnnotations.path);
        } catch (_) {
          await target.rename(source.path);
          rethrow;
        }
      }
    }
    return document.copyWith(name: name, path: target.path);
  }

  Future<({List<RecentDocument> documents, int skipped})> scanFolder(
    List<RecentDocument> existing,
  ) async {
    final selectedPath = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose a folder containing PDFs',
    );
    if (selectedPath == null) {
      return (documents: <RecentDocument>[], skipped: 0);
    }
    final appDir = await getApplicationDocumentsDirectory();
    final library = Directory('${appDir.path}${Platform.pathSeparator}library');
    await library.create(recursive: true);
    final known = existing
        .map((document) => document.fingerprint)
        .whereType<String>()
        .toSet();
    final imported = <RecentDocument>[];
    var skipped = 0;
    await for (final entity in Directory(
      selectedPath,
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.pdf')) {
        continue;
      }
      final fingerprint = await _fingerprint(entity);
      final documentDate = await _documentDate(entity);
      if (!known.add(fingerprint)) {
        skipped++;
        continue;
      }
      final name = entity.uri.pathSegments.last;
      final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
      final target = File(
        '${library.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}-$safeName',
      );
      await entity.copy(target.path);
      imported.add(
        await _withFileDetails(
          RecentDocument(
            name: name,
            path: target.path,
            openedAt: DateTime.now(),
            documentDate: documentDate,
            hasBeenOpened: false,
            fingerprint: fingerprint,
          ),
          target,
        ),
      );
    }
    return (documents: imported, skipped: skipped);
  }

  Future<
    ({List<RecentDocument> documents, int skipped, RecentDocument? selected})
  >
  importPdfs(List<RecentDocument> existing) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
    );
    if (result == null) {
      return (documents: <RecentDocument>[], skipped: 0, selected: null);
    }
    final appDir = await getApplicationDocumentsDirectory();
    final library = Directory('${appDir.path}${Platform.pathSeparator}library');
    await library.create(recursive: true);
    final known = existing
        .map((document) => document.fingerprint)
        .whereType<String>()
        .toSet();
    final imported = <RecentDocument>[];
    RecentDocument? selected;
    var skipped = 0;
    for (var index = 0; index < result.files.length; index++) {
      final picked = result.files[index];
      if (picked.path == null) continue;
      final source = File(picked.path!);
      final fingerprint = await _fingerprint(source);
      final documentDate = await _documentDate(source);
      if (!known.add(fingerprint)) {
        skipped++;
        selected = existing
            .where((document) => document.fingerprint == fingerprint)
            .firstOrNull;
        continue;
      }
      final safeName = picked.name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
      final target = File(
        '${library.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}_$index-$safeName',
      );
      await source.copy(target.path);
      final document = await _withFileDetails(
        RecentDocument(
          name: picked.name,
          path: target.path,
          openedAt: DateTime.now(),
          documentDate: documentDate,
          hasBeenOpened: false,
          fingerprint: fingerprint,
        ),
        target,
      );
      imported.add(document);
      selected = document;
    }
    return (documents: imported, skipped: skipped, selected: selected);
  }

  Future<RecentDocument> importExternalPdf(
    String sourcePath,
    String name,
    List<RecentDocument> existing,
  ) async {
    final source = File(sourcePath);
    final fingerprint = await _fingerprint(source);
    for (final document in existing) {
      if (document.fingerprint == fingerprint) return document;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final library = Directory('${appDir.path}${Platform.pathSeparator}library');
    await library.create(recursive: true);
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
    final target = File(
      '${library.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}-$safeName',
    );
    final document = RecentDocument(
      name: name,
      path: (await source.copy(target.path)).path,
      openedAt: DateTime.now(),
      documentDate: await _documentDate(source),
      hasBeenOpened: false,
      fingerprint: fingerprint,
    );
    return _withFileDetails(document, target);
  }
}

enum LibrarySort {
  nameAscending,
  nameDescending,
  recentActivity,
  documentDateNewest,
  documentDateOldest,
  fileSizeLargest,
  fileSizeSmallest,
  pageCountMost,
  pageCountFewest,
}

const essentialLibrarySorts = {
  LibrarySort.nameAscending,
  LibrarySort.recentActivity,
  LibrarySort.documentDateNewest,
};

String librarySortLabel(LibrarySort sort) => switch (sort) {
  LibrarySort.nameAscending => 'Name: A to Z',
  LibrarySort.nameDescending => 'Name: Z to A',
  LibrarySort.recentActivity => 'Recent activity',
  LibrarySort.documentDateNewest => 'Document date: newest',
  LibrarySort.documentDateOldest => 'Document date: oldest',
  LibrarySort.fileSizeLargest => 'File size: largest',
  LibrarySort.fileSizeSmallest => 'File size: smallest',
  LibrarySort.pageCountMost => 'Page count: most',
  LibrarySort.pageCountFewest => 'Page count: fewest',
};

IconData librarySortIcon(LibrarySort sort) => switch (sort) {
  LibrarySort.nameAscending => Icons.sort_by_alpha_rounded,
  LibrarySort.nameDescending => Icons.sort_by_alpha_rounded,
  LibrarySort.recentActivity => Icons.history_rounded,
  LibrarySort.documentDateNewest => Icons.calendar_month_rounded,
  LibrarySort.documentDateOldest => Icons.calendar_month_outlined,
  LibrarySort.fileSizeLargest => Icons.data_usage_rounded,
  LibrarySort.fileSizeSmallest => Icons.data_usage_outlined,
  LibrarySort.pageCountMost => Icons.library_books_rounded,
  LibrarySort.pageCountFewest => Icons.library_books_outlined,
};

enum ReaderTool {
  search,
  bookmarkPage,
  annotations,
  thumbnails,
  jumpToPage,
  savedBookmarks,
  tableOfContents,
  verticalView,
  horizontalView,
  twoPageView,
  rotate,
  fitWidth,
  fitPage,
  fullScreen,
  readingExperience,
  share,
  rename,
  print,
  delete,
}

const essentialReaderTools = {
  ReaderTool.search,
  ReaderTool.bookmarkPage,
  ReaderTool.thumbnails,
  ReaderTool.jumpToPage,
  ReaderTool.fitWidth,
  ReaderTool.fullScreen,
  ReaderTool.readingExperience,
  ReaderTool.share,
  ReaderTool.rename,
};

String readerToolLabel(ReaderTool tool) => switch (tool) {
  ReaderTool.search => 'Search document',
  ReaderTool.bookmarkPage => 'Bookmark current page',
  ReaderTool.annotations => 'Annotation tools',
  ReaderTool.thumbnails => 'Page thumbnails',
  ReaderTool.jumpToPage => 'Jump to page',
  ReaderTool.savedBookmarks => 'Saved bookmarks',
  ReaderTool.tableOfContents => 'Table of contents',
  ReaderTool.verticalView => 'Vertical view',
  ReaderTool.horizontalView => 'Horizontal view',
  ReaderTool.twoPageView => 'Two-page view',
  ReaderTool.rotate => 'Rotate view',
  ReaderTool.fitWidth => 'Fit width',
  ReaderTool.fitPage => 'Fit page',
  ReaderTool.fullScreen => 'Full screen',
  ReaderTool.readingExperience => 'Reading experience',
  ReaderTool.share => 'Share PDF',
  ReaderTool.rename => 'Rename PDF',
  ReaderTool.print => 'Print',
  ReaderTool.delete => 'Delete PDF',
};

IconData readerToolIcon(ReaderTool tool) => switch (tool) {
  ReaderTool.search => Icons.search_rounded,
  ReaderTool.bookmarkPage => Icons.bookmark_add_outlined,
  ReaderTool.annotations => Icons.draw_outlined,
  ReaderTool.thumbnails => Icons.grid_view_rounded,
  ReaderTool.jumpToPage => Icons.pin_outlined,
  ReaderTool.savedBookmarks => Icons.bookmarks_outlined,
  ReaderTool.tableOfContents => Icons.toc_rounded,
  ReaderTool.verticalView => Icons.view_agenda_outlined,
  ReaderTool.horizontalView => Icons.view_carousel_outlined,
  ReaderTool.twoPageView => Icons.menu_book_outlined,
  ReaderTool.rotate => Icons.rotate_right_rounded,
  ReaderTool.fitWidth => Icons.fit_screen_outlined,
  ReaderTool.fitPage => Icons.crop_free_rounded,
  ReaderTool.fullScreen => Icons.fullscreen_rounded,
  ReaderTool.readingExperience => Icons.display_settings_rounded,
  ReaderTool.share => Icons.share_outlined,
  ReaderTool.rename => Icons.drive_file_rename_outline,
  ReaderTool.print => Icons.print_outlined,
  ReaderTool.delete => Icons.delete_outline_rounded,
};

enum HeaderAction {
  documentScanner,
  searchFilters,
  createFolder,
  scanFolder,
  sort,
}

enum PapertrailScanSource { camera, gallery, cameraAndGallery }

enum PapertrailScanMode { automatic, manualCrop, filterControls }

const essentialHeaderActions = {
  HeaderAction.documentScanner,
  HeaderAction.sort,
};

String headerActionLabel(HeaderAction action) => switch (action) {
  HeaderAction.documentScanner => 'Scan paper document',
  HeaderAction.searchFilters => 'Search filters',
  HeaderAction.createFolder => 'Create library folder',
  HeaderAction.scanFolder => 'Scan device folder',
  HeaderAction.sort => 'Sort PDFs',
};

IconData headerActionIcon(HeaderAction action) => switch (action) {
  HeaderAction.documentScanner => Icons.document_scanner_outlined,
  HeaderAction.searchFilters => Icons.filter_alt_outlined,
  HeaderAction.createFolder => Icons.create_new_folder_outlined,
  HeaderAction.scanFolder => Icons.drive_folder_upload_outlined,
  HeaderAction.sort => Icons.sort_rounded,
};

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    required this.themeMode,
    required this.fontFamily,
    required this.fontWeight,
    required this.fontScale,
    required this.onThemeModeChanged,
    required this.onFontFamilyChanged,
    required this.onFontWeightChanged,
    required this.onFontScaleChanged,
    super.key,
  });

  final ThemeMode themeMode;
  final String? fontFamily;
  final int fontWeight;
  final double fontScale;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<String?> onFontFamilyChanged;
  final ValueChanged<int> onFontWeightChanged;
  final ValueChanged<double> onFontScaleChanged;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const _openPdfChannel = MethodChannel(
    'com.papertrail.pdfreader/open_pdf',
  );
  final _store = DocumentStore();
  final _librarySearchController = TextEditingController();
  final _searchIndex = LibrarySearchIndex();
  List<RecentDocument> _documents = [];
  List<LibrarySearchHit> _contentHits = [];
  List<String> _recentSearches = [];
  List<String> _folders = [];
  final Set<String> _selectedDocumentPaths = {};
  String? _selectedFolder;
  bool _favoritesOnly = false;
  bool _uncategorizedOnly = false;
  DateTime? _createdAfter;
  int _minimumPages = 0;
  int _minimumSizeMb = 0;
  LibrarySort _sort = LibrarySort.nameAscending;
  Set<LibrarySort> _enabledSorts = {...essentialLibrarySorts};
  Set<ReaderTool> _enabledReaderTools = {...essentialReaderTools};
  Set<HeaderAction> _enabledHeaderActions = {...essentialHeaderActions};
  bool _showBottomPageControls = false;
  bool _showTextSelectionMagnifier = false;
  bool _showInAppMessages = true;
  bool _showLibrarySearch = true;
  bool _pdfSummariesEnabled = false;
  bool _importantHighlightsEnabled = false;
  String _libraryQuery = '';
  bool _loading = true;
  bool _scanning = false;
  bool _scanningDocument = false;
  String _appVersion = '';
  PapertrailScanMode _scanMode = PapertrailScanMode.automatic;
  bool _scanSinglePage = false;
  int _scanPageLimit = 20;
  PapertrailScanSource _scanSource = PapertrailScanSource.camera;

  @override
  void initState() {
    super.initState();
    _openPdfChannel.setMethodCallHandler((call) async {
      if (call.method == 'openPdf') {
        await _handleExternalPdf(Map<Object?, Object?>.from(call.arguments));
      }
    });
    _load();
  }

  @override
  void dispose() {
    _librarySearchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _store.load(),
      _store.loadFolders(),
      PackageInfo.fromPlatform(),
    ]);
    final documents = results[0] as List<RecentDocument>;
    final folders = results[1] as List<String>;
    final packageInfo = results[2] as PackageInfo;
    if (mounted) {
      setState(() {
        _documents = documents;
        _folders = folders;
        _appVersion =
            'Version ${packageInfo.version} (Build ${packageInfo.buildNumber})';
        _loading = false;
      });
      final prefs = await SharedPreferences.getInstance();
      final savedSorts = prefs.getStringList('enabled_library_sorts');
      final enabledSorts = savedSorts == null
          ? {...essentialLibrarySorts}
          : savedSorts
                .map(
                  (name) => LibrarySort.values
                      .where((sort) => sort.name == name)
                      .firstOrNull,
                )
                .whereType<LibrarySort>()
                .toSet();
      if (enabledSorts.isEmpty) {
        enabledSorts.add(LibrarySort.nameAscending);
      }
      final savedSortName = prefs.getString('selected_library_sort');
      final savedSort = LibrarySort.values
          .where((sort) => sort.name == savedSortName)
          .firstOrNull;
      final savedReaderTools = prefs.getStringList('enabled_reader_tools');
      final enabledReaderTools = savedReaderTools == null
          ? {...essentialReaderTools}
          : savedReaderTools
                .map(
                  (name) => ReaderTool.values
                      .where((tool) => tool.name == name)
                      .firstOrNull,
                )
                .whereType<ReaderTool>()
                .toSet();
      final savedHeaderActions = prefs.getStringList('enabled_header_actions');
      final enabledHeaderActions = savedHeaderActions == null
          ? {...essentialHeaderActions}
          : savedHeaderActions
                .map(
                  (name) => HeaderAction.values
                      .where((action) => action.name == name)
                      .firstOrNull,
                )
                .whereType<HeaderAction>()
                .toSet();
      setState(() {
        _recentSearches = prefs.getStringList('recent_library_searches') ?? [];
        _enabledSorts = enabledSorts;
        _enabledReaderTools = enabledReaderTools;
        _enabledHeaderActions = enabledHeaderActions;
        _showBottomPageControls =
            prefs.getBool('show_bottom_page_controls') ?? false;
        _showTextSelectionMagnifier =
            prefs.getBool('text_selection_magnifier') ?? false;
        _showInAppMessages =
            prefs.getBool(PapertrailNotice.preferenceKey) ?? true;
        _showLibrarySearch = prefs.getBool('show_library_search') ?? true;
        _pdfSummariesEnabled = prefs.getBool('pdf_summaries_enabled') ?? false;
        _importantHighlightsEnabled =
            prefs.getBool('important_highlights_enabled') ?? false;
        final savedScanMode = prefs.getString('scan_capture_mode');
        _scanMode =
            PapertrailScanMode.values
                .where((mode) => mode.name == savedScanMode)
                .firstOrNull ??
            ((prefs.getBool('scan_manual_crop') ?? false)
                ? PapertrailScanMode.manualCrop
                : PapertrailScanMode.automatic);
        _scanSinglePage = prefs.getBool('scan_single_page') ?? false;
        _scanPageLimit =
            const [5, 10, 20, 50].contains(prefs.getInt('scan_page_limit'))
            ? prefs.getInt('scan_page_limit')!
            : 20;
        _scanSource =
            PapertrailScanSource.values
                .where(
                  (source) =>
                      source.name == prefs.getString('scan_capture_source'),
                )
                .firstOrNull ??
            PapertrailScanSource.camera;
        _sort = savedSort != null && _enabledSorts.contains(savedSort)
            ? savedSort
            : _enabledSorts.first;
      });
      unawaited(_indexDocuments(documents));
      final initial = await _openPdfChannel.invokeMapMethod<Object?, Object?>(
        'getInitialPdf',
      );
      if (initial != null) await _handleExternalPdf(initial);
    }
  }

  Future<void> _searchLibrary(String value) async {
    setState(() => _libraryQuery = value);
    final hits = await _searchIndex.search(value);
    if (mounted && value == _librarySearchController.text) {
      setState(() => _contentHits = hits);
    }
  }

  Future<void> _indexDocuments(Iterable<RecentDocument> documents) async {
    for (final document in documents) {
      try {
        await _searchIndex.indexPdf(document.path);
      } catch (_) {
        // One damaged or inaccessible PDF must not stop background indexing.
      }
    }
  }

  Future<void> _rememberSearch(String value) async {
    final query = value.trim();
    if (query.isEmpty) return;
    _recentSearches = [
      query,
      ..._recentSearches.where(
        (item) => item.toLowerCase() != query.toLowerCase(),
      ),
    ].take(8).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_library_searches', _recentSearches);
  }

  Future<void> _showSearchFilters() async {
    var pages = _minimumPages.toDouble();
    var size = _minimumSizeMb.toDouble();
    var date = _createdAfter;
    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Search filters'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  date == null
                      ? 'Any document date'
                      : 'Created after ${date!.day}/${date!.month}/${date!.year}',
                ),
                trailing: const Icon(Icons.calendar_month),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime(1970),
                    lastDate: DateTime.now(),
                    initialDate: date ?? DateTime.now(),
                  );
                  if (picked != null) setDialogState(() => date = picked);
                },
              ),
              Text('Minimum pages: ${pages.round()}'),
              Slider(
                value: pages,
                max: 500,
                divisions: 100,
                onChanged: (value) => setDialogState(() => pages = value),
              ),
              Text('Minimum size: ${size.round()} MB'),
              Slider(
                value: size,
                max: 100,
                divisions: 100,
                onChanged: (value) => setDialogState(() => size = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                date = null;
                pages = 0;
                size = 0;
                Navigator.pop(context, true);
              },
              child: const Text('Clear'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (apply == true && mounted) {
      setState(() {
        _createdAfter = date;
        _minimumPages = pages.round();
        _minimumSizeMb = size.round();
      });
    }
  }

  Future<void> _saveSettingList(String key, Iterable<String> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, values.toList());
  }

  Future<void> _saveSelectedSort(LibrarySort sort) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_library_sort', sort.name);
  }

  Widget _settingsSwitch({
    required String title,
    required IconData icon,
    required bool value,
    required ValueChanged<bool>? onChanged,
    String? subtitle,
  }) => SwitchListTile(
    dense: true,
    contentPadding: const EdgeInsets.only(left: 20, right: 8),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    secondary: Icon(icon),
    selected: value,
    value: value,
    onChanged: onChanged,
  );

  Widget _buildDrawerSettings() => Column(
    children: [
      ExpansionTile(
        key: const PageStorageKey('appearance-settings'),
        initiallyExpanded: true,
        maintainState: true,
        leading: const Icon(Icons.palette_outlined),
        title: const Text(
          'Appearance',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 12, 8),
            child: DropdownButtonFormField<ThemeMode>(
              value: widget.themeMode,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Theme',
                prefixIcon: Icon(Icons.brightness_6_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('Use device setting'),
                ),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
              onChanged: (value) {
                if (value != null) widget.onThemeModeChanged(value);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 12, 8),
            child: DropdownButtonFormField<String?>(
              value: widget.fontFamily,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Application font',
                prefixIcon: Icon(Icons.font_download_outlined),
              ),
              items: appFontFamilies.entries
                  .map(
                    (entry) => DropdownMenuItem<String?>(
                      value: entry.value,
                      child: Text(
                        entry.key,
                        style: TextStyle(fontFamily: entry.value),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: widget.onFontFamilyChanged,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 12, 12),
            child: DropdownButtonFormField<int>(
              value: widget.fontWeight,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Font weight',
                prefixIcon: Icon(Icons.format_bold_rounded),
              ),
              items: appFontWeights.entries
                  .map(
                    (entry) => DropdownMenuItem<int>(
                      value: entry.value,
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          fontWeight: FontWeight.values[entry.value ~/ 100 - 1],
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) widget.onFontWeightChanged(value);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 12, 12),
            child: DropdownButtonFormField<double>(
              value: widget.fontScale,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Font size',
                prefixIcon: Icon(Icons.format_size_rounded),
              ),
              items: appFontScales.entries
                  .map(
                    (entry) => DropdownMenuItem<double>(
                      value: entry.value,
                      child: Text(entry.key),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) widget.onFontScaleChanged(value);
              },
            ),
          ),
        ],
      ),
      ExpansionTile(
        key: const PageStorageKey('general-settings'),
        initiallyExpanded: true,
        maintainState: true,
        leading: const Icon(Icons.tune_rounded),
        title: const Text(
          'General',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        children: [
          _settingsSwitch(
            title: 'Library search',
            icon: Icons.manage_search_rounded,
            subtitle: 'Search PDF names and document contents',
            value: _showLibrarySearch,
            onChanged: (value) async {
              setState(() {
                _showLibrarySearch = value;
                if (!value) {
                  _librarySearchController.clear();
                  _libraryQuery = '';
                  _contentHits = [];
                }
              });
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('show_library_search', value);
            },
          ),
          _settingsSwitch(
            title: 'Bottom page controls',
            icon: Icons.view_day_outlined,
            subtitle: 'Page number and previous/next buttons',
            value: _showBottomPageControls,
            onChanged: (value) async {
              setState(() => _showBottomPageControls = value);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('show_bottom_page_controls', value);
            },
          ),
          _settingsSwitch(
            title: 'Text selection magnifier',
            icon: Icons.zoom_in_rounded,
            subtitle: 'Zoom bubble while adjusting a text selection',
            value: _showTextSelectionMagnifier,
            onChanged: (value) async {
              setState(() => _showTextSelectionMagnifier = value);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('text_selection_magnifier', value);
            },
          ),
          _settingsSwitch(
            title: 'In-app messages',
            icon: Icons.notifications_active_outlined,
            subtitle: 'Show compact success, guidance, and error banners',
            value: _showInAppMessages,
            onChanged: (value) async {
              setState(() => _showInAppMessages = value);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool(PapertrailNotice.preferenceKey, value);
            },
          ),
        ],
      ),
      ExpansionTile(
        key: const PageStorageKey('smart-reading-settings'),
        maintainState: true,
        leading: const Icon(Icons.auto_awesome_outlined),
        title: const Text(
          'Smart reading',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        children: [
          _settingsSwitch(
            title: 'PDF summaries',
            icon: Icons.summarize_outlined,
            subtitle: 'Create a private on-device summary when requested',
            value: _pdfSummariesEnabled,
            onChanged: (value) async {
              setState(() {
                _pdfSummariesEnabled = value;
                if (!value) _importantHighlightsEnabled = false;
              });
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('pdf_summaries_enabled', value);
              if (!value) {
                await prefs.setBool('important_highlights_enabled', false);
              }
            },
          ),
          _settingsSwitch(
            title: 'Important information highlights',
            icon: Icons.auto_awesome_rounded,
            subtitle: 'Show ranked key points with their page numbers',
            value: _pdfSummariesEnabled && _importantHighlightsEnabled,
            onChanged: !_pdfSummariesEnabled
                ? null
                : (value) async {
                    setState(() => _importantHighlightsEnabled = value);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('important_highlights_enabled', value);
                  },
          ),
        ],
      ),
      ExpansionTile(
        key: const PageStorageKey('header-settings'),
        maintainState: true,
        leading: const Icon(Icons.web_asset_outlined),
        title: const Text(
          'Header options',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        children: [
          for (final action in HeaderAction.values)
            _settingsSwitch(
              title: headerActionLabel(action),
              icon: headerActionIcon(action),
              value: _enabledHeaderActions.contains(action),
              onChanged: (value) {
                setState(() {
                  value
                      ? _enabledHeaderActions.add(action)
                      : _enabledHeaderActions.remove(action);
                });
                unawaited(
                  _saveSettingList(
                    'enabled_header_actions',
                    _enabledHeaderActions.map((item) => item.name),
                  ),
                );
              },
            ),
        ],
      ),
      ExpansionTile(
        key: const PageStorageKey('sorting-settings'),
        maintainState: true,
        leading: const Icon(Icons.sort_rounded),
        title: const Text(
          'Sorting options',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        children: [
          for (final sort in LibrarySort.values)
            _settingsSwitch(
              title: librarySortLabel(sort),
              icon: librarySortIcon(sort),
              value: _enabledSorts.contains(sort),
              onChanged: (value) {
                if (!value && _enabledSorts.length == 1) return;
                setState(() {
                  value ? _enabledSorts.add(sort) : _enabledSorts.remove(sort);
                  if (!_enabledSorts.contains(_sort)) {
                    _sort = _enabledSorts.first;
                    unawaited(_saveSelectedSort(_sort));
                  }
                });
                unawaited(
                  _saveSettingList(
                    'enabled_library_sorts',
                    _enabledSorts.map((item) => item.name),
                  ),
                );
              },
            ),
        ],
      ),
      ExpansionTile(
        key: const PageStorageKey('reader-settings'),
        maintainState: true,
        leading: const Icon(Icons.menu_book_outlined),
        title: const Text(
          'Reader options',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        children: [
          for (final tool in ReaderTool.values)
            _settingsSwitch(
              title: readerToolLabel(tool),
              icon: readerToolIcon(tool),
              value: _enabledReaderTools.contains(tool),
              onChanged: (value) {
                setState(() {
                  value
                      ? _enabledReaderTools.add(tool)
                      : _enabledReaderTools.remove(tool);
                });
                unawaited(
                  _saveSettingList(
                    'enabled_reader_tools',
                    _enabledReaderTools.map((item) => item.name),
                  ),
                );
              },
            ),
        ],
      ),
    ],
  );

  Future<void> _handleExternalPdf(Map<Object?, Object?> data) async {
    final path = data['path'] as String?;
    final name = data['name'] as String?;
    if (path == null || name == null || !mounted) return;
    final openingOverlay = OverlayEntry(
      builder: (_) => _OpeningPdfOverlay(fileName: name),
    );
    Overlay.of(context).insert(openingOverlay);
    try {
      final document = await _store.importExternalPdf(path, name, _documents);
      if (_documents.any((item) => item.path == document.path)) {
        setState(() {
          _documents = _documents
              .map((item) => item.path == document.path ? document : item)
              .toList();
        });
        await _store.save(_documents);
      } else {
        setState(() => _documents = [document, ..._documents]);
        await _store.save(_documents);
        unawaited(_indexDocuments([document]));
      }
      if (openingOverlay.mounted) openingOverlay.remove();
      if (mounted) await _open(document);
    } catch (_) {
      if (mounted) {
        PapertrailNotice.show(
          context,
          'Could not open that PDF.',
          isError: true,
        );
      }
    } finally {
      if (openingOverlay.mounted) openingOverlay.remove();
    }
  }

  Future<void> _scanFolder() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final result = await _store.scanFolder(_documents);
      if (!mounted) return;
      if (result.documents.isNotEmpty) {
        setState(() => _documents = [...result.documents, ..._documents]);
        await _store.save(_documents);
        unawaited(_indexDocuments(result.documents));
      }
      if (!mounted) return;
      final message = result.documents.isEmpty
          ? result.skipped > 0
                ? 'No new PDFs found. Existing files were skipped.'
                : 'No PDFs found in that folder.'
          : '${result.documents.length} PDFs added from the folder.';
      PapertrailNotice.show(context, message, icon: Icons.folder_outlined);
    } catch (_) {
      if (mounted) {
        PapertrailNotice.show(
          context,
          'Could not scan that folder. Choose another folder.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _showScannerOptions() async {
    var scanMode = _scanMode;
    var singlePage = _scanSinglePage;
    var pageLimit = _scanPageLimit;
    var source = _scanSource;
    final selection =
        await showModalBottomSheet<
          ({
            PapertrailScanMode scanMode,
            bool singlePage,
            int pageLimit,
            PapertrailScanSource source,
          })
        >(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (context) => StatefulBuilder(
            builder: (context, setSheetState) => SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  20 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Scan a document',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Choose how Papertrail should capture each page.',
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Capture mode',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          avatar: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 18,
                          ),
                          label: const Text('Automatic'),
                          selected: scanMode == PapertrailScanMode.automatic,
                          onSelected: (_) => setSheetState(
                            () => scanMode = PapertrailScanMode.automatic,
                          ),
                        ),
                        ChoiceChip(
                          avatar: const Icon(Icons.crop_free_rounded, size: 18),
                          label: const Text('Manual crop'),
                          selected: scanMode == PapertrailScanMode.manualCrop,
                          onSelected: (_) => setSheetState(
                            () => scanMode = PapertrailScanMode.manualCrop,
                          ),
                        ),
                        ChoiceChip(
                          avatar: const Icon(Icons.filter_rounded, size: 18),
                          label: const Text('Filter controls · Android'),
                          selected:
                              scanMode == PapertrailScanMode.filterControls,
                          onSelected: Platform.isIOS
                              ? null
                              : (_) => setSheetState(
                                  () => scanMode =
                                      PapertrailScanMode.filterControls,
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(switch (scanMode) {
                      PapertrailScanMode.automatic =>
                        'Detect, crop, and enhance document edges automatically.',
                      PapertrailScanMode.manualCrop =>
                        'Capture, then drag all four corners to adjust width and height.',
                      PapertrailScanMode.filterControls =>
                        'Choose original, enhanced color, grayscale, or black and white in the Android scanner.',
                    }),
                    if (Platform.isIOS)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Filter controls are unavailable on iOS because VisionKit does not expose them.',
                        ),
                      ),
                    const SizedBox(height: 20),
                    Text(
                      'Pages',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.looks_one_outlined),
                          label: Text('Single page'),
                        ),
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.library_books_outlined),
                          label: Text('Multiple pages'),
                        ),
                      ],
                      selected: {singlePage},
                      onSelectionChanged: (value) =>
                          setSheetState(() => singlePage = value.first),
                    ),
                    if (!singlePage) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: pageLimit,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Maximum pages',
                          prefixIcon: Icon(Icons.numbers_rounded),
                        ),
                        items: const [5, 10, 20, 50]
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text('$value pages'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setSheetState(() => pageLimit = value);
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 20),
                    DropdownButtonFormField<PapertrailScanSource>(
                      value: source,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Capture source',
                        prefixIcon: Icon(Icons.add_a_photo_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: PapertrailScanSource.camera,
                          child: Text('Camera'),
                        ),
                        DropdownMenuItem(
                          value: PapertrailScanSource.gallery,
                          child: Text('Gallery'),
                        ),
                        DropdownMenuItem(
                          value: PapertrailScanSource.cameraAndGallery,
                          child: Text('Camera and Gallery'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) setSheetState(() => source = value);
                      },
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(context, (
                        scanMode: scanMode,
                        singlePage: singlePage,
                        pageLimit: pageLimit,
                        source: source,
                      )),
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: const Text('Start scanning'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    if (selection != null && mounted) {
      setState(() {
        _scanMode = selection.scanMode;
        _scanSinglePage = selection.singlePage;
        _scanPageLimit = selection.pageLimit;
        _scanSource = selection.source;
      });
      await _saveScannerPreferences();
      await _scanDocument(
        scanMode: selection.scanMode,
        pageLimit: selection.singlePage ? 1 : selection.pageLimit,
        source: selection.source,
      );
    }
  }

  Future<void> _saveScannerPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString('scan_capture_mode', _scanMode.name),
      prefs.setBool('scan_single_page', _scanSinglePage),
      prefs.setInt('scan_page_limit', _scanPageLimit),
      prefs.setString('scan_capture_source', _scanSource.name),
    ]);
  }

  ScannerSource _nativeScannerSource(PapertrailScanSource source) =>
      switch (source) {
        PapertrailScanSource.camera => ScannerSource.camera,
        PapertrailScanSource.gallery => ScannerSource.gallery,
        PapertrailScanSource.cameraAndGallery => ScannerSource.cameraAndGallery,
      };

  AndroidScannerMode _nativeScannerMode(PapertrailScanMode mode) =>
      switch (mode) {
        PapertrailScanMode.automatic => AndroidScannerMode.full,
        PapertrailScanMode.manualCrop => AndroidScannerMode.base,
        PapertrailScanMode.filterControls => AndroidScannerMode.baseWithFilter,
      };

  Future<({String name, String? folder, bool favorite})?>
  _confirmScannedPdfDetails() async {
    final now = DateTime.now();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final suggestedName =
        'Scan ${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)} '
        '${twoDigits(now.hour)}-${twoDigits(now.minute)}-${twoDigits(now.second)}';
    final controller = TextEditingController(text: suggestedName);
    String? folder;
    var favorite = false;
    final result =
        await showDialog<({String name, String? folder, bool favorite})>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Save scanned PDF'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'File name',
                        prefixIcon: Icon(Icons.drive_file_rename_outline),
                        suffixText: '.pdf',
                      ),
                    ),
                    if (_folders.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String?>(
                        value: folder,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Library folder',
                          prefixIcon: Icon(Icons.folder_outlined),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Uncategorized'),
                          ),
                          ..._folders.map(
                            (item) => DropdownMenuItem<String?>(
                              value: item,
                              child: Text(item),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => folder = value),
                      ),
                    ],
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Add to favorites'),
                      secondary: const Icon(Icons.star_outline_rounded),
                      value: favorite,
                      onChanged: (value) =>
                          setDialogState(() => favorite = value ?? false),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    var name = controller.text.trim();
                    if (name.isEmpty) return;
                    name = name.replaceFirst(
                      RegExp(r'(?:\.pdf)+$', caseSensitive: false),
                      '',
                    );
                    Navigator.pop(context, (
                      name: '$name.pdf',
                      folder: folder,
                      favorite: favorite,
                    ));
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save PDF'),
                ),
              ],
            ),
          ),
        );
    controller.dispose();
    return result;
  }

  Future<void> _scanDocument({
    required PapertrailScanMode scanMode,
    required int pageLimit,
    required PapertrailScanSource source,
  }) async {
    if (_scanningDocument) return;
    setState(() => _scanningDocument = true);
    try {
      final scannedPaths = await CunningDocumentScanner.getPictures(
        asPdf: true,
        noOfPages: pageLimit,
        scannerSource: _nativeScannerSource(source),
        androidScannerMode: _nativeScannerMode(scanMode),
      );
      if (scannedPaths == null || scannedPaths.isEmpty || !mounted) return;

      final details = await _confirmScannedPdfDetails();
      if (details == null || !mounted) return;
      var document = await _store.importExternalPdf(
        scannedPaths.first,
        details.name,
        _documents,
      );
      document = document.copyWith(
        folder: details.folder,
        isFavorite: details.favorite,
      );
      if (!_documents.any((item) => item.path == document.path)) {
        setState(() => _documents = [document, ..._documents]);
        await _store.save(_documents);
        unawaited(_indexDocuments([document]));
      }
      if (!mounted) return;
      PapertrailNotice.show(
        context,
        'Scan saved to your library.',
        icon: Icons.document_scanner_outlined,
      );
      await _open(document);
    } on CunningDocumentScannerException catch (error) {
      if (mounted) {
        PapertrailNotice.show(
          context,
          error.message.isEmpty
              ? 'Could not scan the document.'
              : error.message,
          isError: true,
        );
      }
    } catch (_) {
      if (mounted) {
        PapertrailNotice.show(
          context,
          'Could not scan the document. Check camera access and try again.',
          isError: true,
        );
      }
    } finally {
      try {
        await CunningDocumentScanner.cleanCache();
      } catch (_) {
        // Cache cleanup must not hide a successfully saved scan.
      }
      if (mounted) setState(() => _scanningDocument = false);
    }
  }

  Future<void> _import() async {
    try {
      final result = await _store.importPdfs(_documents);
      if (!mounted || (result.documents.isEmpty && result.skipped == 0)) {
        return;
      }
      if (result.documents.isNotEmpty) {
        setState(() => _documents = [...result.documents, ..._documents]);
        await _store.save(_documents);
        unawaited(_indexDocuments(result.documents));
      }
      if (result.selected != null && mounted) {
        await _open(result.selected!);
      }
    } catch (_) {
      if (mounted) {
        PapertrailNotice.show(
          context,
          'Could not import that PDF.',
          isError: true,
        );
      }
    }
  }

  Future<void> _open(RecentDocument document) async {
    final page = await Navigator.of(context).push<int>(
      PageRouteBuilder<int>(
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, __) =>
            ReaderScreen(document: document, onRename: _rename),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, .025),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    if (page == null || !mounted) return;
    final currentDocument =
        _documents
            .where(
              (item) =>
                  item.fingerprint != null &&
                  item.fingerprint == document.fingerprint,
            )
            .firstOrNull ??
        document;
    if (page == _readerDeletedResult) {
      setState(
        () =>
            _documents.removeWhere((item) => item.path == currentDocument.path),
      );
      await _store.save(_documents);
      await deleteDocumentArtifacts(currentDocument.path);
      await _searchIndex.remove(currentDocument.path);
      return;
    }
    setState(() {
      _documents = [
        currentDocument.copyWith(
          page: page,
          openedAt: DateTime.now(),
          hasBeenOpened: true,
        ),
        ..._documents.where((item) => item.path != currentDocument.path),
      ];
    });
    await _store.save(_documents);
  }

  Future<void> _remove(RecentDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete PDF from Papertrail?'),
        content: Text(
          '"${document.name}" will be deleted from this app and its '
          'Papertrail library copy will be removed from the device. '
          'The original file in Downloads, Drive, or another app will not '
          'be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(
      () => _documents.removeWhere((item) => item.path == document.path),
    );
    await _store.save(_documents);
    await deleteDocumentArtifacts(document.path);
    await _searchIndex.remove(document.path);
  }

  Future<RecentDocument?> _rename(RecentDocument document) async {
    final currentName = document.name.toLowerCase().endsWith('.pdf')
        ? document.name.substring(0, document.name.length - 4)
        : document.name;
    final controller = TextEditingController(text: currentName);
    final requestedName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename PDF'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'File name',
            suffixText: '.pdf',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (requestedName == null || requestedName.trim().isEmpty || !mounted) {
      return null;
    }
    try {
      final renamed = await _store.rename(document, requestedName);
      if (!mounted) return null;
      setState(() {
        _documents = _documents
            .map((item) => item.path == document.path ? renamed : item)
            .toList();
      });
      await _store.save(_documents);
      await _searchIndex.rename(document.path, renamed.path);
      return renamed;
    } catch (_) {
      if (mounted) {
        PapertrailNotice.show(
          context,
          'Could not rename that PDF.',
          isError: true,
        );
      }
      return null;
    }
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Folder name'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty || !mounted) return;
    if (_folders.any(
      (folder) => folder.toLowerCase() == trimmed.toLowerCase(),
    )) {
      PapertrailNotice.show(
        context,
        'A folder with that name already exists.',
        isError: true,
      );
      return;
    }
    setState(() {
      _folders = [..._folders, trimmed]
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _selectedFolder = trimmed;
      _favoritesOnly = false;
      _uncategorizedOnly = false;
    });
    await _store.saveFolders(_folders);
  }

  Future<void> _moveToFolder(RecentDocument document) async {
    if (_folders.isEmpty) return;
    final folder = await showDialog<String?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Move to folder'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ''),
            child: const ListTile(
              leading: Icon(Icons.folder_off_outlined),
              title: Text('Unfiled'),
            ),
          ),
          ..._folders.map(
            (name) => SimpleDialogOption(
              onPressed: () => Navigator.pop(context, name),
              child: ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(name),
              ),
            ),
          ),
        ],
      ),
    );
    if (folder == null || !mounted) return;
    final moved = document.copyWith(
      folder: folder.isEmpty ? null : folder,
      clearFolder: folder.isEmpty,
    );
    setState(() {
      _documents = _documents
          .map((item) => item.path == document.path ? moved : item)
          .toList();
    });
    await _store.save(_documents);
  }

  List<RecentDocument> get _selectedDocuments => _documents
      .where((document) => _selectedDocumentPaths.contains(document.path))
      .toList();

  void _toggleDocumentSelection(RecentDocument document) {
    setState(() {
      if (!_selectedDocumentPaths.remove(document.path)) {
        _selectedDocumentPaths.add(document.path);
      }
    });
  }

  void _clearDocumentSelection() => setState(_selectedDocumentPaths.clear);

  Future<void> _moveSelectedToFolder() async {
    if (_selectedDocumentPaths.isEmpty ||
        _folders.isEmpty ||
        !_enabledHeaderActions.contains(HeaderAction.createFolder)) {
      return;
    }
    final folder = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Move ${_selectedDocumentPaths.length} PDFs'),
        children: _folders
            .map(
              (name) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, name),
                child: ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(name),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (folder == null || !mounted) return;
    setState(() {
      _documents = _documents
          .map(
            (document) => _selectedDocumentPaths.contains(document.path)
                ? document.copyWith(folder: folder)
                : document,
          )
          .toList();
      _selectedDocumentPaths.clear();
    });
    await _store.save(_documents);
  }

  Future<void> _removeSelectedFromLibrary() async {
    if (_selectedDocumentPaths.isEmpty) return;
    final count = _selectedDocumentPaths.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove $count PDFs from Papertrail?'),
        content: const Text(
          'The files will no longer appear in the library. '
          'This does not delete the files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final removedPaths = {..._selectedDocumentPaths};
    setState(() {
      _documents.removeWhere(
        (document) => _selectedDocumentPaths.contains(document.path),
      );
      _selectedDocumentPaths.clear();
    });
    await _store.save(_documents);
    for (final path in removedPaths) {
      await _searchIndex.remove(path);
    }
  }

  Future<void> _deleteSelectedFromDevice() async {
    if (_selectedDocumentPaths.isEmpty) return;
    final selected = _selectedDocuments;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${selected.length} PDFs?'),
        content: const Text(
          'The selected PDF files and their saved annotations will be '
          'permanently deleted from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    for (final document in selected) {
      await deleteDocumentArtifacts(document.path);
      await _searchIndex.remove(document.path);
    }
    if (!mounted) return;
    setState(() {
      _documents.removeWhere(
        (document) => _selectedDocumentPaths.contains(document.path),
      );
      _selectedDocumentPaths.clear();
    });
    await _store.save(_documents);
  }

  Future<void> _toggleFavorite(RecentDocument document) async {
    setState(() {
      _documents = _documents
          .map(
            (item) => item.path == document.path
                ? item.copyWith(isFavorite: !item.isFavorite)
                : item,
          )
          .toList();
    });
    await _store.save(_documents);
  }

  Future<void> _sharePdf(RecentDocument document) async {
    final exported = await const AnnotationExporter().export(document.path);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(exported.path)], text: document.name),
    );
  }

  String _formatLastOpened(RecentDocument document) {
    if (!document.hasBeenOpened) return 'Not opened yet';
    final date = document.openedAt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final prefix = day == today
        ? 'Today'
        : day == today.subtract(const Duration(days: 1))
        ? 'Yesterday'
        : '${date.day}/${date.month}/${date.year}';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour < 12 ? 'AM' : 'PM';
    return 'Last opened $prefix at $hour:$minute $period';
  }

  Widget _thumbnail(RecentDocument document, ColorScheme colors) => Container(
    width: 56,
    height: 74,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: colors.errorContainer,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: colors.outlineVariant),
    ),
    child: PdfDocumentViewBuilder.file(
      document.path,
      builder: (context, pdf) {
        if (pdf == null || pdf.pages.isEmpty) {
          return Icon(
            Icons.picture_as_pdf_rounded,
            color: colors.onErrorContainer,
          );
        }
        return PdfPageView(
          document: pdf,
          pageNumber: 1,
          maximumDpi: 72,
          decoration: const BoxDecoration(color: Colors.white),
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final query = _libraryQuery.trim().toLowerCase();
    final filter = LibraryFilter(
      query: query,
      folder: _selectedFolder,
      createdAfter: _createdAfter,
      minimumPages: _minimumPages,
      minimumSizeBytes: _minimumSizeMb * 1024 * 1024,
      contentMatchPaths: _contentHits.map((hit) => hit.path).toSet(),
    );
    bool matchesQuery(RecentDocument document) =>
        filter.matches(document) &&
        (!_favoritesOnly || document.isFavorite) &&
        (!_uncategorizedOnly ||
            document.folder == null ||
            document.folder!.trim().isEmpty);
    final recentDocuments =
        _documents
            .where(
              (document) => document.hasBeenOpened && matchesQuery(document),
            )
            .toList()
          ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    final allDocuments = _documents.where(matchesQuery).toList()
      ..sort((a, b) => compareDocuments(a, b, _sort));
    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                child: Row(
                  children: [
                    const PapertrailLogo(size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Papertrail PDF',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close settings',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Settings',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [_buildDrawerSettings()],
                ),
              ),
              if (_appVersion.isNotEmpty) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _appVersion,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      appBar: AppBar(
        leading: _selectedDocumentPaths.isEmpty
            ? null
            : IconButton(
                tooltip: 'Cancel selection',
                onPressed: _clearDocumentSelection,
                icon: const Icon(Icons.close_rounded),
              ),
        title: _selectedDocumentPaths.isNotEmpty
            ? Text(
                '${_selectedDocumentPaths.length} selected',
                style: const TextStyle(fontWeight: FontWeight.w800),
              )
            : const Row(
                children: [
                  PapertrailLogo(size: 26),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Papertrail',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
        centerTitle: false,
        actions: _selectedDocumentPaths.isNotEmpty
            ? [
                if (_enabledHeaderActions.contains(HeaderAction.createFolder) &&
                    _folders.isNotEmpty)
                  IconButton(
                    tooltip: 'Move selected to folder',
                    onPressed: _moveSelectedToFolder,
                    icon: const Icon(Icons.drive_file_move_outline),
                  ),
                IconButton(
                  tooltip: 'Remove selected from Papertrail',
                  onPressed: _removeSelectedFromLibrary,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                IconButton(
                  tooltip: 'Delete selected from device',
                  onPressed: _deleteSelectedFromDevice,
                  icon: const Icon(Icons.delete_outline),
                ),
              ]
            : [
                if (_enabledHeaderActions.contains(
                  HeaderAction.documentScanner,
                ))
                  IconButton(
                    tooltip: 'Scan paper document',
                    onPressed: _scanningDocument ? null : _showScannerOptions,
                    icon: _scanningDocument
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.document_scanner_outlined),
                  ),
                if (_enabledHeaderActions.contains(HeaderAction.searchFilters))
                  IconButton(
                    tooltip: 'Search filters',
                    onPressed: _showSearchFilters,
                    icon: const Icon(Icons.filter_alt_outlined),
                  ),
                if (_enabledHeaderActions.contains(HeaderAction.createFolder))
                  IconButton(
                    tooltip: 'Create library folder',
                    onPressed: _createFolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                  ),
                if (_enabledHeaderActions.contains(HeaderAction.scanFolder))
                  IconButton(
                    tooltip: 'Scan a folder for PDFs',
                    onPressed: _scanning ? null : _scanFolder,
                    icon: _scanning
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.drive_folder_upload_outlined),
                  ),
                if (_enabledHeaderActions.contains(HeaderAction.sort))
                  PopupMenuButton<LibrarySort>(
                    tooltip: 'Sort PDFs',
                    icon: const Icon(Icons.sort),
                    onSelected: (sort) {
                      setState(() => _sort = sort);
                      unawaited(_saveSelectedSort(sort));
                    },
                    itemBuilder: (_) => LibrarySort.values
                        .where(_enabledSorts.contains)
                        .map(
                          (sort) => CheckedPopupMenuItem(
                            value: sort,
                            checked: _sort == sort,
                            child: Row(
                              children: [
                                Icon(librarySortIcon(sort), size: 20),
                                const SizedBox(width: 12),
                                Expanded(child: Text(librarySortLabel(sort))),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
              ],
      ),
      floatingActionButton: _selectedDocumentPaths.isEmpty
          ? FloatingActionButton.extended(
              onPressed: _import,
              tooltip: 'Open PDF',
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Open PDF'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _documents.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Icon(
                        Icons.picture_as_pdf_rounded,
                        size: 46,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Your PDFs, beautifully simple',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Open a document to start reading. Your files stay private and available offline.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: _import,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Choose PDFs'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _scanningDocument ? null : _showScannerOptions,
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: const Text('Scan a document'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
              children: [
                if (_showLibrarySearch) ...[
                  TextField(
                    controller: _librarySearchController,
                    onChanged: _searchLibrary,
                    onSubmitted: _rememberSearch,
                    decoration: InputDecoration(
                      hintText: 'Search PDFs by filename',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _libraryQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _librarySearchController.clear();
                                setState(() => _libraryQuery = '');
                              },
                              icon: const Icon(Icons.close),
                            ),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (_libraryQuery.isEmpty && _recentSearches.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: _recentSearches
                          .map(
                            (query) => ActionChip(
                              avatar: const Icon(Icons.history, size: 16),
                              label: Text(query),
                              onPressed: () {
                                _librarySearchController.text = query;
                                _searchLibrary(query);
                              },
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                HorizontalScrollCue(
                  builder: (scrollController) => SingleChildScrollView(
                    controller: scrollController,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('All'),
                          selected:
                              _selectedFolder == null &&
                              !_favoritesOnly &&
                              !_uncategorizedOnly,
                          onSelected: (_) => setState(() {
                            _selectedFolder = null;
                            _favoritesOnly = false;
                            _uncategorizedOnly = false;
                          }),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          avatar: const Icon(Icons.star_rounded, size: 18),
                          label: const Text('Favorites'),
                          selected: _favoritesOnly,
                          onSelected: (_) => setState(() {
                            _selectedFolder = null;
                            _favoritesOnly = true;
                            _uncategorizedOnly = false;
                          }),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          avatar: const Icon(
                            Icons.folder_off_outlined,
                            size: 18,
                          ),
                          label: const Text('Uncategorized'),
                          selected: _uncategorizedOnly,
                          onSelected: (_) => setState(() {
                            _selectedFolder = null;
                            _favoritesOnly = false;
                            _uncategorizedOnly = true;
                          }),
                        ),
                        const SizedBox(width: 8),
                        ..._folders.map(
                          (folder) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              avatar: const Icon(
                                Icons.folder_outlined,
                                size: 18,
                              ),
                              label: Text(folder),
                              selected: _selectedFolder == folder,
                              onSelected: (_) => setState(() {
                                _selectedFolder = folder;
                                _favoritesOnly = false;
                                _uncategorizedOnly = false;
                              }),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (recentDocuments.isNotEmpty) ...[
                  Text(
                    'Recently opened',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 154,
                    child: HorizontalScrollCue(
                      builder: (scrollController) => ListView.separated(
                        controller: scrollController,
                        scrollDirection: Axis.horizontal,
                        itemCount: recentDocuments.take(5).length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final document = recentDocuments[index];
                          return SizedBox(
                            width: 190,
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => _open(document),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.picture_as_pdf_rounded,
                                        color: colors.error,
                                        size: 34,
                                      ),
                                      const Spacer(),
                                      Text(
                                        document.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text('Page ${document.page}'),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'All PDFs',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text('${allDocuments.length}'),
                  ],
                ),
                const SizedBox(height: 12),
                if (allDocuments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 48,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No PDFs match "$_libraryQuery"',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  )
                else
                  ...allDocuments.map(
                    (document) => _documentTile(document, colors),
                  ),
              ],
            ),
    );
  }

  Widget _documentTile(RecentDocument document, ColorScheme colors) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    clipBehavior: Clip.antiAlias,
    color: _selectedDocumentPaths.contains(document.path)
        ? colors.primaryContainer.withValues(alpha: .55)
        : null,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      leading: _thumbnail(document, colors),
      isThreeLine: false,
      title: Text(
        document.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(() {
        final hit = _contentHits
            .where((item) => item.path == document.path)
            .firstOrNull;
        if (hit != null && _libraryQuery.trim().isNotEmpty) {
          return 'Page ${hit.page}: …${hit.snippet}…';
        }
        final pages = document.pageCount > 0
            ? '${document.pageCount} pages'
            : 'Page count unavailable';
        return '$pages • ${formatFileSize(document.fileSize)}\n'
            '${_formatLastOpened(document)}';
      }()),
      trailing: _selectedDocumentPaths.isNotEmpty
          ? Checkbox(
              value: _selectedDocumentPaths.contains(document.path),
              onChanged: (_) => _toggleDocumentSelection(document),
            )
          : PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'favorite') _toggleFavorite(document);
                if (value == 'rename') _rename(document);
                if (value == 'move') _moveToFolder(document);
                if (value == 'share') _sharePdf(document);
                if (value == 'remove') _remove(document);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'favorite',
                  child: Text(
                    document.isFavorite
                        ? 'Remove from favorites'
                        : 'Add to favorites',
                  ),
                ),
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                if (_folders.isNotEmpty)
                  const PopupMenuItem(
                    value: 'move',
                    child: Text('Move to folder'),
                  ),
                const PopupMenuItem(
                  value: 'share',
                  child: Text('Share or export'),
                ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Delete from device'),
                ),
              ],
            ),
      onTap: () => _selectedDocumentPaths.isNotEmpty
          ? _toggleDocumentSelection(document)
          : _open(document),
      onLongPress: () => _toggleDocumentSelection(document),
    ),
  );
}

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    required this.document,
    required this.onRename,
    super.key,
  });
  final RecentDocument document;
  final Future<RecentDocument?> Function(RecentDocument document) onRename;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

enum ReaderViewMode { vertical, horizontal, twoPage }

enum ReaderColorMode { normal, night, sepia }

class _ReaderScreenState extends State<ReaderScreen> {
  final _controller = PdfViewerController();
  final _annotationKey = GlobalKey<AnnotationLayerState>();
  late final PdfTextSearcher _searcher;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  late RecentDocument _document;
  late int _page;
  int _pageCount = 0;
  bool _chromeVisible = true;
  bool _searchVisible = false;
  bool _fullScreen = false;
  bool _annotationMode = false;
  bool _annotationsDirty = false;
  int _rotation = 0;
  ReaderViewMode _viewMode = ReaderViewMode.vertical;
  Set<int> _bookmarks = {};
  ReaderColorMode _colorMode = ReaderColorMode.normal;
  double _pageSpacing = 12;
  double _brightness = 1;
  bool _keepAwake = false;
  bool _rightToLeft = false;
  bool _showBottomPageControls = false;
  bool _showTextSelectionMagnifier = false;
  bool _pdfSummariesEnabled = false;
  bool _importantHighlightsEnabled = false;
  bool _doubleTapZoomedIn = false;
  bool _summaryLoading = false;
  String? _documentPassword;
  Set<ReaderTool> _enabledReaderTools = {...essentialReaderTools};
  Timer? _positionTimer;

  @override
  void initState() {
    super.initState();
    _document = widget.document;
    _page = _document.page;
    _searcher = PdfTextSearcher(_controller);
    _searcher.addListener(_onSearchChanged);
    _loadBookmarks();
    _loadReaderPreferences();
    _controller.addListener(_schedulePositionSave);
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _searcher.removeListener(_onSearchChanged);
    _controller.removeListener(_schedulePositionSave);
    _positionTimer?.cancel();
    WakelockPlus.disable();
    ScreenBrightness().resetApplicationScreenBrightness();
    _searcher.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String get _readerPreferenceKey => _document.fingerprint ?? _document.path;

  Future<void> _loadReaderPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _readerPreferenceKey;
    _pageSpacing = prefs.getDouble('spacing_$key') ?? 12;
    _rightToLeft = prefs.getBool('rtl_$key') ?? false;
    _keepAwake = prefs.getBool('awake_reader') ?? false;
    _brightness = prefs.getDouble('brightness_reader') ?? 1;
    _colorMode =
        ReaderColorMode.values[(prefs.getInt('color_reader') ?? 0).clamp(
          0,
          ReaderColorMode.values.length - 1,
        )];
    _showBottomPageControls =
        prefs.getBool('show_bottom_page_controls') ?? false;
    _showTextSelectionMagnifier =
        prefs.getBool('text_selection_magnifier') ?? false;
    _pdfSummariesEnabled = prefs.getBool('pdf_summaries_enabled') ?? false;
    _importantHighlightsEnabled =
        prefs.getBool('important_highlights_enabled') ?? false;
    final savedReaderTools = prefs.getStringList('enabled_reader_tools');
    _enabledReaderTools = savedReaderTools == null
        ? {...essentialReaderTools}
        : savedReaderTools
              .map(
                (name) => ReaderTool.values
                    .where((tool) => tool.name == name)
                    .firstOrNull,
              )
              .whereType<ReaderTool>()
              .toSet();
    await WakelockPlus.toggle(enable: _keepAwake);
    await ScreenBrightness().setApplicationScreenBrightness(_brightness);
    if (mounted) setState(() {});
  }

  void _schedulePositionSave() {
    if (!_controller.isReady) return;
    _positionTimer?.cancel();
    _positionTimer = Timer(const Duration(milliseconds: 500), () async {
      final prefs = await SharedPreferences.getInstance();
      final center = _controller.centerPosition;
      final key = _readerPreferenceKey;
      await prefs.setDouble('zoom_$key', _controller.currentZoom);
      await prefs.setDouble('centerX_$key', center.dx);
      await prefs.setDouble('centerY_$key', center.dy);
    });
  }

  Future<void> _restorePosition() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _readerPreferenceKey;
    final zoom = prefs.getDouble('zoom_$key');
    final x = prefs.getDouble('centerX_$key');
    final y = prefs.getDouble('centerY_$key');
    if (zoom != null && x != null && y != null && _controller.isReady) {
      _controller.value = _controller.calcMatrixFor(Offset(x, y), zoom: zoom);
    }
  }

  String get _bookmarkKey =>
      'bookmarks_${_document.fingerprint ?? _document.path}';

  Future<void> _loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _bookmarks = (prefs.getStringList(_bookmarkKey) ?? const <String>[])
          .map(int.tryParse)
          .whereType<int>()
          .toSet();
    });
  }

  Future<void> _toggleBookmark() async {
    setState(() {
      if (!_bookmarks.remove(_page)) _bookmarks.add(_page);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _bookmarkKey,
      (_bookmarks.toList()..sort()).map((page) => '$page').toList(),
    );
  }

  Future<String?> _passwordProvider() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Password required'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'PDF password'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (password != null) _documentPassword = password;
    return password;
  }

  Future<void> _jumpToPage() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    if (!_controller.isReady || _controller.pageCount < 1) {
      PapertrailNotice.show(
        context,
        'The PDF is still loading. Try again.',
        icon: Icons.hourglass_top_rounded,
      );
      return;
    }
    final pageCount = _controller.pageCount;
    final input = TextEditingController(text: '$_page');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Jump to page'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'Page (1-$pageCount)'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    input.dispose();
    if (value == null || !mounted) return;
    final page = validPageTarget(value, pageCount);
    if (page == null) {
      PapertrailNotice.show(
        context,
        'Enter a page number from 1 to $pageCount.',
        isError: true,
      );
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_controller.isReady) return;
    await _controller.goToPage(
      pageNumber: page,
      duration: const Duration(milliseconds: 300),
    );
    if (mounted) setState(() => _page = page);
  }

  void _fitPage() {
    final matrix = _controller.calcMatrixForFit(pageNumber: _page);
    if (matrix != null) {
      _controller.value = matrix;
      _doubleTapZoomedIn = false;
    }
  }

  void _fitWidth() {
    final matrix = _controller.calcMatrixFitWidthForPage(pageNumber: _page);
    if (matrix != null) {
      _controller.value = matrix;
      _doubleTapZoomedIn = false;
    }
  }

  Future<void> _toggleFullScreen() async {
    _fullScreen = !_fullScreen;
    await SystemChrome.setEnabledSystemUIMode(
      _fullScreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    if (mounted) setState(() => _chromeVisible = !_fullScreen);
  }

  Future<void> _printDocument() async {
    try {
      if (_annotationsDirty) await _annotationKey.currentState?.save();
      final exported = await const AnnotationExporter().export(
        _document.path,
        password: _documentPassword,
      );
      final bytes = await exported.readAsBytes();
      await Printing.layoutPdf(
        name: _document.name,
        onLayout: (_) async => bytes,
      );
    } catch (_) {
      if (mounted) {
        PapertrailNotice.show(
          context,
          'This PDF could not be printed.',
          isError: true,
        );
      }
    }
  }

  Future<void> _shareOpenDocument() async {
    try {
      if (_annotationsDirty) await _annotationKey.currentState?.save();
      final exported = await const AnnotationExporter().export(
        _document.path,
        password: _documentPassword,
      );
      await SharePlus.instance.share(
        ShareParams(files: [XFile(exported.path)], text: _document.name),
      );
    } catch (_) {
      if (mounted) {
        PapertrailNotice.show(
          context,
          'This PDF could not be shared.',
          icon: Icons.share_outlined,
          isError: true,
        );
      }
    }
  }

  Future<void> _renameOpenDocument() async {
    if (_annotationsDirty) {
      try {
        await _annotationKey.currentState?.save();
      } catch (_) {
        if (mounted) {
          PapertrailNotice.show(
            context,
            'Save annotations before renaming this PDF.',
            isError: true,
          );
        }
        return;
      }
    }
    final renamed = await widget.onRename(_document);
    if (renamed == null || !mounted) return;
    setState(() => _document = renamed);
    PapertrailNotice.show(
      context,
      'PDF renamed.',
      icon: Icons.drive_file_rename_outline,
    );
  }

  Future<void> _deleteOpenDocument() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this PDF?'),
        content: Text(
          '"${_document.name}" will be removed from Papertrail and its '
          'private device copy will be deleted. The original source file is '
          'not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(_readerDeletedResult);
    }
  }

  Future<void> _showDisplaySettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, updateSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('Reading experience')),
                SegmentedButton<ReaderColorMode>(
                  segments: const [
                    ButtonSegment(
                      value: ReaderColorMode.normal,
                      label: Text('Normal'),
                    ),
                    ButtonSegment(
                      value: ReaderColorMode.night,
                      label: Text('Night'),
                    ),
                    ButtonSegment(
                      value: ReaderColorMode.sepia,
                      label: Text('Sepia'),
                    ),
                  ],
                  selected: {_colorMode},
                  onSelectionChanged: (value) {
                    setState(() => _colorMode = value.first);
                    updateSheet(() {});
                  },
                ),
                Text('Brightness ${(_brightness * 100).round()}%'),
                Slider(
                  value: _brightness,
                  min: .1,
                  onChanged: (value) {
                    setState(() => _brightness = value);
                    updateSheet(() {});
                    ScreenBrightness().setApplicationScreenBrightness(value);
                  },
                ),
                Text('Page spacing ${_pageSpacing.round()}'),
                Slider(
                  value: _pageSpacing,
                  min: 0,
                  max: 40,
                  onChanged: (value) {
                    setState(() => _pageSpacing = value);
                    updateSheet(() {});
                  },
                ),
                SwitchListTile(
                  title: const Text('Keep screen awake'),
                  value: _keepAwake,
                  onChanged: (value) {
                    setState(() => _keepAwake = value);
                    updateSheet(() {});
                    WakelockPlus.toggle(enable: value);
                  },
                ),
                SwitchListTile(
                  title: const Text('Right-to-left navigation'),
                  value: _rightToLeft,
                  onChanged: (value) {
                    setState(() => _rightToLeft = value);
                    updateSheet(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    final key = _readerPreferenceKey;
    await prefs.setDouble('spacing_$key', _pageSpacing);
    await prefs.setBool('rtl_$key', _rightToLeft);
    await prefs.setBool('awake_reader', _keepAwake);
    await prefs.setDouble('brightness_reader', _brightness);
    await prefs.setInt('color_reader', _colorMode.index);
    if (_controller.isReady) _selectViewMode(_viewMode);
  }

  PdfPageLayout _horizontalLayout(List<PdfPage> pages, PdfViewerParams params) {
    final height =
        pages.fold<double>(0, (value, page) => math.max(value, page.height)) +
        params.margin * 2;
    final layouts = <Rect>[];
    var x = params.margin;
    for (final page in pages) {
      layouts.add(
        Rect.fromLTWH(x, (height - page.height) / 2, page.width, page.height),
      );
      x += page.width + params.margin;
    }
    return PdfPageLayout(pageLayouts: layouts, documentSize: Size(x, height));
  }

  PdfPageLayout _twoPageLayout(List<PdfPage> pages, PdfViewerParams params) {
    final layouts = <Rect>[];
    var y = params.margin;
    var maxWidth = 0.0;
    for (var index = 0; index < pages.length; index += 2) {
      final first = pages[index];
      final second = index + 1 < pages.length ? pages[index + 1] : null;
      final rowHeight = math.max(first.height, second?.height ?? 0);
      layouts.add(Rect.fromLTWH(params.margin, y, first.width, first.height));
      if (second != null) {
        layouts.add(
          Rect.fromLTWH(
            params.margin * 2 + first.width,
            y,
            second.width,
            second.height,
          ),
        );
      }
      maxWidth = math.max(
        maxWidth,
        first.width + (second?.width ?? 0) + params.margin * 3,
      );
      y += rowHeight + params.margin;
    }
    return PdfPageLayout(pageLayouts: layouts, documentSize: Size(maxWidth, y));
  }

  void _showSearch() {
    setState(() {
      _chromeVisible = true;
      _searchVisible = true;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  void _hideSearch() {
    _searcher.resetTextSearch();
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() => _searchVisible = false);
  }

  Future<void> _nextMatch() async {
    if (await _searcher.goToNextMatch() == -1 && _searcher.matches.isNotEmpty) {
      await _searcher.goToMatchOfIndex(0);
    }
  }

  Future<void> _previousMatch() async {
    if (await _searcher.goToPrevMatch() == -1 && _searcher.matches.isNotEmpty) {
      await _searcher.goToMatchOfIndex(_searcher.matches.length - 1);
    }
  }

  void _go(int page) {
    if (!_controller.isReady) return;
    final target = page.clamp(1, _controller.pageCount);
    _controller.goToPage(pageNumber: target);
  }

  Future<void> _toggleDoubleTapZoom(Offset documentPosition) async {
    if (!_controller.isReady) return;
    final fitMatrix = _controller.calcMatrixForFit(pageNumber: _page);
    if (fitMatrix == null) return;

    if (_doubleTapZoomedIn) {
      _doubleTapZoomedIn = false;
      await _controller.goTo(fitMatrix);
      return;
    }

    final currentZoom = _controller.currentZoom;
    final targetZoom = math.min(currentZoom * 2, _controller.params.maxScale);
    _doubleTapZoomedIn = true;
    await _controller.setZoom(documentPosition, targetZoom);
  }

  Widget _buildSelectionHandle(
    BuildContext context,
    PdfTextSelectionAnchor anchor,
    PdfViewerTextSelectionAnchorHandleState state,
  ) {
    final colors = Theme.of(context).colorScheme;
    final dragging = state == PdfViewerTextSelectionAnchorHandleState.dragging;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 36,
      height: 36,
      alignment: Alignment.center,
      child: Container(
        width: dragging ? 26 : 22,
        height: dragging ? 26 : 22,
        decoration: BoxDecoration(
          color: colors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: colors.surface, width: 3),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copySelection(PdfViewerContextMenuBuilderParams params) async {
    final copied = await params.textSelectionDelegate.copyTextSelection();
    params.dismissContextMenu();
    if (!mounted || !copied) return;
    PapertrailNotice.show(context, 'Text copied', icon: Icons.copy_rounded);
  }

  Widget? _buildSelectionContextMenu(
    BuildContext context,
    PdfViewerContextMenuBuilderParams params,
  ) {
    final delegate = params.textSelectionDelegate;
    if (!params.isTextSelectionEnabled) return null;
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (delegate.isCopyAllowed && delegate.hasSelectedText)
            TextButton.icon(
              onPressed: () => unawaited(_copySelection(params)),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy'),
            ),
          if (!delegate.isSelectingAllText)
            TextButton.icon(
              onPressed: () => unawaited(delegate.selectAllText()),
              icon: const Icon(Icons.select_all_rounded, size: 18),
              label: const Text('Select all'),
            ),
          IconButton(
            tooltip: 'Clear selection',
            onPressed: () => unawaited(delegate.clearTextSelection()),
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }

  Future<void> _saveRecoveryPage(int page) async {
    final id = _document.fingerprint;
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('resume_$id', page);
  }

  Future<void> _showThumbnails() async {
    if (!_controller.isReady) return;
    final document = _controller.document;
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: .68,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: document.pages.length,
          itemBuilder: (context, index) => InkWell(
            onTap: () => Navigator.pop(context, index + 1),
            child: Column(
              children: [
                Expanded(
                  child: PdfPageView(
                    document: document,
                    pageNumber: index + 1,
                    maximumDpi: 55,
                  ),
                ),
                Text('${index + 1}'),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected != null) _go(selected);
  }

  Future<void> _showOutline() async {
    if (!_controller.isReady) return;
    final outline = await _controller.useDocument(
      (document) => document.loadOutline(),
    );
    if (!mounted || outline == null) return;
    final nodes = <PdfOutlineNode>[];
    void flatten(List<PdfOutlineNode> source) {
      for (final node in source) {
        nodes.add(node);
        flatten(node.children);
      }
    }

    flatten(outline);
    if (nodes.isEmpty) {
      PapertrailNotice.show(
        context,
        'This PDF has no table of contents.',
        icon: Icons.format_list_bulleted_rounded,
      );
      return;
    }
    final destination = await showModalBottomSheet<PdfDest>(
      context: context,
      builder: (context) => ListView(
        children: [
          const ListTile(title: Text('Table of contents')),
          ...nodes.map(
            (node) => ListTile(
              title: Text(node.title),
              enabled: node.dest != null,
              onTap: node.dest == null
                  ? null
                  : () => Navigator.pop(context, node.dest),
            ),
          ),
        ],
      ),
    );
    if (destination != null) await _controller.goToDest(destination);
  }

  Future<void> _showBookmarks() async {
    final page = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => ListView(
        children: [
          const ListTile(title: Text('Bookmarks')),
          if (_bookmarks.isEmpty)
            const ListTile(title: Text('No bookmarked pages yet.')),
          ...(_bookmarks.toList()..sort()).map(
            (page) => ListTile(
              leading: const Icon(Icons.bookmark),
              title: Text('Page $page'),
              onTap: () => Navigator.pop(context, page),
            ),
          ),
        ],
      ),
    );
    if (page != null) _go(page);
  }

  void _selectViewMode(ReaderViewMode mode) {
    setState(() => _viewMode = mode);
  }

  Future<void> _summarizePdf() async {
    if (_summaryLoading) return;
    setState(() => _summaryLoading = true);
    var cancelled = false;
    var dialogVisible = true;
    final progress = ValueNotifier<(int, int)>((0, 0));
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Summarizing PDF'),
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (_, value, __) {
              final (completed, total) = value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: total > 0 ? completed / total : null,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    total > 0
                        ? 'Processing page $completed of $total'
                        : 'Preparing document…',
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancelled = true;
                dialogVisible = false;
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ).then((_) => dialogVisible = false),
    );
    await Future<void>.delayed(Duration.zero);
    try {
      final result = await PdfSummaryService().summarize(
        _document.path,
        password: _documentPassword,
        onProgress: (completed, total) {
          progress.value = (completed, total);
        },
        isCancelled: () => cancelled,
      );
      if (dialogVisible && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogVisible = false;
      }
      if (!mounted) return;
      if (result.summary.isEmpty) {
        PapertrailNotice.show(
          context,
          'No readable text was found in this PDF.',
          icon: Icons.info_outline,
        );
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .72,
          maxChildSize: .94,
          minChildSize: .45,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            children: [
              Text(
                'PDF summary',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Generated privately on this device from ${result.pagesRead} pages.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              for (final sentence in result.summary)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('• $sentence'),
                ),
              if (_importantHighlightsEnabled) ...[
                const SizedBox(height: 14),
                Text(
                  'Important information',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (final point in result.importantPoints)
                  Card(
                    color: Theme.of(
                      context,
                    ).colorScheme.tertiaryContainer.withValues(alpha: .55),
                    child: ListTile(
                      leading: const Icon(Icons.auto_awesome_rounded),
                      title: Text(point.text),
                      subtitle: Text('Page ${point.page}'),
                      onTap: () {
                        Navigator.pop(context);
                        _go(point.page);
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    } on SummaryCancelled {
      // Cancellation is an expected user action.
    } catch (_) {
      if (mounted) {
        PapertrailNotice.show(
          context,
          'This PDF could not be summarized.',
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (dialogVisible && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progress.dispose();
      if (mounted) setState(() => _summaryLoading = false);
    }
  }

  List<PopupMenuEntry<String>> _readerToolMenuItems() {
    const menuTools = <ReaderTool, String>{
      ReaderTool.thumbnails: 'thumbnails',
      ReaderTool.jumpToPage: 'jump',
      ReaderTool.savedBookmarks: 'bookmarks',
      ReaderTool.tableOfContents: 'outline',
      ReaderTool.verticalView: 'vertical',
      ReaderTool.horizontalView: 'horizontal',
      ReaderTool.twoPageView: 'two',
      ReaderTool.rotate: 'rotate',
      ReaderTool.fitWidth: 'fitWidth',
      ReaderTool.fitPage: 'fitPage',
      ReaderTool.fullScreen: 'fullscreen',
      ReaderTool.readingExperience: 'display',
      ReaderTool.share: 'share',
      ReaderTool.rename: 'rename',
      ReaderTool.print: 'print',
      ReaderTool.delete: 'delete',
    };
    final items = menuTools.entries
        .where((entry) => _enabledReaderTools.contains(entry.key))
        .map(
          (entry) => PopupMenuItem<String>(
            value: entry.value,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(readerToolIcon(entry.key)),
              title: Text(readerToolLabel(entry.key)),
              trailing: _isReaderToolSelected(entry.key)
                  ? const Icon(Icons.check_circle_rounded)
                  : null,
              selected: _isReaderToolSelected(entry.key),
            ),
          ),
        )
        .toList();
    if (_pdfSummariesEnabled) {
      items.insert(
        0,
        PopupMenuItem<String>(
          value: 'summarize',
          enabled: !_summaryLoading,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.auto_awesome_rounded),
            title: Text(_summaryLoading ? 'Summarizing…' : 'Summarize PDF'),
          ),
        ),
      );
    }
    return items;
  }

  bool _isReaderToolSelected(ReaderTool tool) => switch (tool) {
    ReaderTool.verticalView => _viewMode == ReaderViewMode.vertical,
    ReaderTool.horizontalView => _viewMode == ReaderViewMode.horizontal,
    ReaderTool.twoPageView => _viewMode == ReaderViewMode.twoPage,
    ReaderTool.fullScreen => _fullScreen,
    _ => false,
  };

  Future<void> _closeReader() async {
    if (_annotationsDirty) {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Save annotation changes?'),
          content: const Text(
            'Your latest annotation changes have not been saved yet.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text('Discard'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, 'save'),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
            ),
          ],
        ),
      );
      if (action == null || !mounted) return;
      if (action == 'save') {
        try {
          await _annotationKey.currentState?.save();
        } catch (_) {
          if (mounted) {
            PapertrailNotice.show(
              context,
              'Annotations could not be saved. The document remains open.',
              isError: true,
            );
          }
          return;
        }
      }
    }
    if (mounted) Navigator.of(context).pop(_page);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_closeReader());
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: _chromeVisible
            ? AppBar(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: .94),
                title: _searchVisible
                    ? TextField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          hintText: 'Search this document',
                          border: InputBorder.none,
                        ),
                        onChanged: (query) => _searcher.startTextSearch(query),
                      )
                    : Text(
                        _document.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                leading: IconButton(
                  tooltip: _searchVisible ? 'Close search' : 'Back',
                  icon: Icon(_searchVisible ? Icons.close : Icons.arrow_back),
                  onPressed: _searchVisible ? _hideSearch : _closeReader,
                ),
                actions: _searchVisible
                    ? [
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: _searcher.isSearching
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _searchController.text.isEmpty
                                        ? ''
                                        : _searcher.matches.isEmpty
                                        ? '0 / 0'
                                        : '${(_searcher.currentIndex ?? 0) + 1} / ${_searcher.matches.length}',
                                  ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Previous match',
                          onPressed: _searcher.hasMatches
                              ? _previousMatch
                              : null,
                          icon: const Icon(Icons.keyboard_arrow_up),
                        ),
                        IconButton(
                          tooltip: 'Next match',
                          onPressed: _searcher.hasMatches ? _nextMatch : null,
                          icon: const Icon(Icons.keyboard_arrow_down),
                        ),
                      ]
                    : [
                        if (_annotationsDirty)
                          IconButton(
                            tooltip: 'Save annotation changes',
                            onPressed: () =>
                                _annotationKey.currentState?.save(),
                            icon: const Icon(Icons.save_outlined),
                          ),
                        if (_enabledReaderTools.contains(ReaderTool.search))
                          IconButton(
                            tooltip: 'Search document',
                            onPressed: _showSearch,
                            icon: const Icon(Icons.search),
                          ),
                        if (_enabledReaderTools.contains(
                          ReaderTool.bookmarkPage,
                        ))
                          IconButton(
                            tooltip: _bookmarks.contains(_page)
                                ? 'Remove bookmark'
                                : 'Bookmark page',
                            onPressed: _toggleBookmark,
                            icon: Icon(
                              _bookmarks.contains(_page)
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                            ),
                          ),
                        if (_enabledReaderTools.contains(
                          ReaderTool.annotations,
                        ))
                          IconButton(
                            tooltip: _annotationMode
                                ? 'Close annotation tools'
                                : 'Annotate',
                            onPressed: () => setState(
                              () => _annotationMode = !_annotationMode,
                            ),
                            icon: Icon(
                              _annotationMode ? Icons.edit_off : Icons.edit,
                            ),
                          ),
                        if (_readerToolMenuItems().isNotEmpty)
                          PopupMenuButton<String>(
                            tooltip: 'Reader tools',
                            onSelected: (value) {
                              switch (value) {
                                case 'summarize':
                                  _summarizePdf();
                                case 'thumbnails':
                                  _showThumbnails();
                                case 'jump':
                                  _jumpToPage();
                                case 'bookmarks':
                                  _showBookmarks();
                                case 'outline':
                                  _showOutline();
                                case 'vertical':
                                  _selectViewMode(ReaderViewMode.vertical);
                                case 'horizontal':
                                  _selectViewMode(ReaderViewMode.horizontal);
                                case 'two':
                                  _selectViewMode(ReaderViewMode.twoPage);
                                case 'rotate':
                                  setState(
                                    () => _rotation = (_rotation + 1) % 4,
                                  );
                                case 'fitPage':
                                  _fitPage();
                                case 'fitWidth':
                                  _fitWidth();
                                case 'fullscreen':
                                  _toggleFullScreen();
                                case 'display':
                                  _showDisplaySettings();
                                case 'share':
                                  _shareOpenDocument();
                                case 'rename':
                                  _renameOpenDocument();
                                case 'print':
                                  _printDocument();
                                case 'delete':
                                  _deleteOpenDocument();
                              }
                            },
                            itemBuilder: (_) => _readerToolMenuItems(),
                          ),
                      ],
              )
            : null,
        body: Stack(
          children: [
            Positioned.fill(
              child: RotatedBox(
                quarterTurns: _rotation,
                child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(switch (_colorMode) {
                    ReaderColorMode.normal => const <double>[
                      1,
                      0,
                      0,
                      0,
                      0,
                      0,
                      1,
                      0,
                      0,
                      0,
                      0,
                      0,
                      1,
                      0,
                      0,
                      0,
                      0,
                      0,
                      1,
                      0,
                    ],
                    ReaderColorMode.night => const <double>[
                      -1,
                      0,
                      0,
                      0,
                      255,
                      0,
                      -1,
                      0,
                      0,
                      255,
                      0,
                      0,
                      -1,
                      0,
                      255,
                      0,
                      0,
                      0,
                      1,
                      0,
                    ],
                    ReaderColorMode.sepia => const <double>[
                      .393,
                      .769,
                      .189,
                      0,
                      0,
                      .349,
                      .686,
                      .168,
                      0,
                      0,
                      .272,
                      .534,
                      .131,
                      0,
                      0,
                      0,
                      0,
                      0,
                      1,
                      0,
                    ],
                  }),
                  child: PdfViewer.file(
                    _document.path,
                    key: ValueKey(_viewMode),
                    passwordProvider: _passwordProvider,
                    controller: _controller,
                    initialPageNumber: _page,
                    params: PdfViewerParams(
                      buildContextMenu: _buildSelectionContextMenu,
                      loadingBannerBuilder: (_, __, ___) =>
                          const _PdfLoadingView(),
                      layoutPages: switch (_viewMode) {
                        ReaderViewMode.vertical => null,
                        ReaderViewMode.horizontal => _horizontalLayout,
                        ReaderViewMode.twoPage => _twoPageLayout,
                      },
                      backgroundColor: dark
                          ? const Color(0xFF0B0B0E)
                          : const Color(0xFFE9E9EF),
                      margin: _pageSpacing,
                      limitRenderingCache: true,
                      useAlternativeFitScaleAsMinScale: false,
                      maxImageBytesCachedOnMemory: 48 * 1024 * 1024,
                      horizontalCacheExtent: .5,
                      verticalCacheExtent: .5,
                      textSelectionParams: PdfTextSelectionParams(
                        enabled: true,
                        enableSelectionHandles: true,
                        showContextMenuAutomatically: true,
                        buildSelectionHandle: _buildSelectionHandle,
                        magnifier: PdfViewerSelectionMagnifierParams(
                          enabled: _showTextSelectionMagnifier,
                          magnifierSizeThreshold: 96,
                        ),
                      ),
                      pagePaintCallbacks: [
                        _searcher.pageTextMatchPaintCallback,
                      ],
                      pageOverlaysBuilder: (_, __, page) {
                        final layer = _annotationKey.currentState;
                        return layer == null
                            ? const <Widget>[]
                            : <Widget>[layer.buildPageOverlay(page.pageNumber)];
                      },
                      onViewerReady: (document, controller) {
                        setState(() => _pageCount = document.pages.length);
                        _restorePosition();
                      },
                      onPageChanged: (page) {
                        if (page == null) return;
                        setState(() {
                          _page = page;
                          _doubleTapZoomedIn = false;
                        });
                        _saveRecoveryPage(page);
                      },
                      onGeneralTap: (_, __, details) {
                        // Let pdfrx handle long presses so it can select a word
                        // and display the native Copy/Select All context menu.
                        if (details.type == PdfViewerGeneralTapType.doubleTap) {
                          unawaited(
                            _toggleDoubleTapZoom(details.documentPosition),
                          );
                          return true;
                        }
                        if (details.type != PdfViewerGeneralTapType.tap) {
                          return false;
                        }
                        if (!_searchVisible) {
                          setState(() => _chromeVisible = !_chromeVisible);
                        }
                        return true;
                      },
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: AnnotationLayer(
                key: _annotationKey,
                pdfPath: _document.path,
                page: _page,
                enabled: _annotationMode,
                onDirtyChanged: (dirty) {
                  if (mounted && _annotationsDirty != dirty) {
                    setState(() => _annotationsDirty = dirty);
                  }
                },
              ),
            ),
            if (_chromeVisible && _showBottomPageControls)
              Positioned(
                left: 20,
                right: 20,
                bottom: 24 + MediaQuery.paddingOf(context).bottom,
                child: Material(
                  elevation: 8,
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: .96),
                  borderRadius: BorderRadius.circular(22),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous page',
                          onPressed: _rightToLeft
                              ? (_pageCount == 0 || _page < _pageCount
                                    ? () => _go(_page + 1)
                                    : null)
                              : (_page > 1 ? () => _go(_page - 1) : null),
                          icon: Icon(
                            _rightToLeft
                                ? Icons.chevron_right
                                : Icons.chevron_left,
                            semanticLabel: 'Previous page',
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '$_page${_pageCount > 0 ? '  /  $_pageCount' : ''}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next page',
                          onPressed: _rightToLeft
                              ? (_page > 1 ? () => _go(_page - 1) : null)
                              : (_pageCount == 0 || _page < _pageCount
                                    ? () => _go(_page + 1)
                                    : null),
                          icon: Icon(
                            _rightToLeft
                                ? Icons.chevron_left
                                : Icons.chevron_right,
                            semanticLabel: 'Next page',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
