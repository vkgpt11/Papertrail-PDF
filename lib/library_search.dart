import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

class LibrarySearchHit {
  const LibrarySearchHit({
    required this.path,
    required this.page,
    required this.snippet,
  });
  final String path;
  final int page;
  final String snippet;
}

class LibrarySearchIndex {
  LibrarySearchIndex({File? indexFile}) : _providedFile = indexFile;

  final File? _providedFile;
  Future<void> _writeQueue = Future.value();

  Future<File> get _file async =>
      _providedFile ??
      File(
        '${(await getApplicationDocumentsDirectory()).path}'
        '${Platform.pathSeparator}papertrail-search-index.json',
      );

  Future<Map<String, List<String>>> _load() async {
    try {
      final file = await _file;
      if (!await file.exists()) return {};
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return map.map(
        (key, value) => MapEntry(key, (value as List).cast<String>()),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> indexPdf(
    String path, {
    String? password,
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (await contains(path)) return;
    PdfDocument? document;
    final recognizer = TextRecognizer();
    try {
      document = await PdfDocument.openFile(
        path,
        passwordProvider: password == null ? null : () => password,
      );
      final pages = <String>[];
      for (final page in document.pages) {
        if (isCancelled?.call() ?? false) return;
        var text = (await page.loadText()).trim();
        if (text.isEmpty) {
          final rendered = await page.render(
            fullWidth: page.width,
            fullHeight: page.height,
          );
          if (rendered != null) {
            ui.Image? image;
            File? temporary;
            try {
              image = await rendered.createImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (bytes != null) {
                temporary = File(
                  '${Directory.systemTemp.path}${Platform.pathSeparator}'
                  'papertrail-ocr-${DateTime.now().microsecondsSinceEpoch}.png',
                );
                await temporary.writeAsBytes(bytes.buffer.asUint8List());
                text = (await recognizer.processImage(
                  InputImage.fromFilePath(temporary.path),
                )).text;
              }
            } finally {
              if (temporary != null && await temporary.exists()) {
                await temporary.delete();
              }
              image?.dispose();
              rendered.dispose();
            }
          }
        }
        pages.add(text);
        onProgress?.call(pages.length, document.pages.length);
        await Future<void>.delayed(Duration.zero);
      }
      if (isCancelled?.call() ?? false) return;
      await _update((index) => index[path] = pages);
    } finally {
      await recognizer.close();
      await document?.dispose();
    }
  }

  Future<bool> contains(String path) async => (await _load()).containsKey(path);

  Future<List<String>?> pages(String path) async => (await _load())[path];

  Future<void> indexTextPages(String path, List<String> pages) async {
    await _update((index) => index[path] = pages);
  }

  Future<void> remove(String path) async {
    await _update((index) => index.remove(path));
  }

  Future<void> rename(String oldPath, String newPath) async {
    await _update((index) {
      final pages = index.remove(oldPath);
      if (pages != null) index[newPath] = pages;
    });
  }

  Future<void> _update(void Function(Map<String, List<String>> index) change) {
    final operation = _writeQueue.then((_) async {
      final index = await _load();
      change(index);
      final target = await _file;
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsString(jsonEncode(index), flush: true);
      if (Platform.isWindows && await target.exists()) {
        await target.delete();
      }
      await temporary.rename(target.path);
    });
    _writeQueue = operation.catchError((_) {});
    return operation;
  }

  Future<List<LibrarySearchHit>> search(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return [];
    final index = await _load();
    final hits = <LibrarySearchHit>[];
    for (final entry in index.entries) {
      for (var page = 0; page < entry.value.length; page++) {
        final text = entry.value[page];
        final position = text.toLowerCase().indexOf(normalized);
        if (position < 0) continue;
        final start = (position - 55).clamp(0, text.length);
        final end = (position + normalized.length + 90).clamp(0, text.length);
        hits.add(
          LibrarySearchHit(
            path: entry.key,
            page: page + 1,
            snippet: text.substring(start, end).replaceAll(RegExp(r'\s+'), ' '),
          ),
        );
      }
    }
    return hits;
  }
}
