import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'library_search.dart';

class PdfSummaryPoint {
  const PdfSummaryPoint({required this.text, required this.page});

  final String text;
  final int page;
}

class PdfSummaryResult {
  const PdfSummaryResult({
    required this.summary,
    required this.importantPoints,
    required this.pagesRead,
  });

  final List<String> summary;
  final List<PdfSummaryPoint> importantPoints;
  final int pagesRead;
}

class PdfSummaryService {
  PdfSummaryService({LibrarySearchIndex? searchIndex})
    : _searchIndex = searchIndex ?? LibrarySearchIndex();

  final LibrarySearchIndex _searchIndex;

  Future<PdfSummaryResult> summarize(
    String path, {
    String? password,
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final cached = await _loadCached(path);
    if (cached != null) return cached;
    if (isCancelled?.call() ?? false) throw const SummaryCancelled();
    await _searchIndex.indexPdf(
      path,
      password: password,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    if (isCancelled?.call() ?? false) throw const SummaryCancelled();
    final indexedPages = await _searchIndex.pages(path);
    if (indexedPages != null) {
      final result = summarizePages(indexedPages);
      await _saveCached(path, result);
      return result;
    }

    PdfDocument? document;
    try {
      document = await PdfDocument.openFile(
        path,
        passwordProvider: password == null ? null : () => password,
      );
      final pages = <String>[];
      for (final page in document.pages) {
        if (isCancelled?.call() ?? false) throw const SummaryCancelled();
        pages.add(
          (await page.loadText()).replaceAll(RegExp(r'\s+'), ' ').trim(),
        );
        onProgress?.call(pages.length, document.pages.length);
        await Future<void>.delayed(Duration.zero);
      }
      final result = summarizePages(pages);
      await _saveCached(path, result);
      return result;
    } finally {
      await document?.dispose();
    }
  }

  Future<File> _cacheFile(String path) async {
    final file = File(path);
    final stat = await file.stat();
    final key = sha256
        .convert(
          utf8.encode(
            '$path|${stat.size}|${stat.modified.millisecondsSinceEpoch}|v2',
          ),
        )
        .toString();
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}'
      'papertrail-summaries',
    );
    await directory.create(recursive: true);
    return File('${directory.path}${Platform.pathSeparator}$key.json');
  }

  Future<PdfSummaryResult?> _loadCached(String path) async {
    try {
      final file = await _cacheFile(path);
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return PdfSummaryResult(
        summary: (json['summary'] as List).cast<String>(),
        importantPoints: (json['importantPoints'] as List)
            .map(
              (item) => PdfSummaryPoint(
                text: (item as Map<String, dynamic>)['text'] as String,
                page: item['page'] as int,
              ),
            )
            .toList(),
        pagesRead: json['pagesRead'] as int,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCached(String path, PdfSummaryResult result) async {
    try {
      final file = await _cacheFile(path);
      await file.writeAsString(
        jsonEncode({
          'summary': result.summary,
          'importantPoints': result.importantPoints
              .map((point) => {'text': point.text, 'page': point.page})
              .toList(),
          'pagesRead': result.pagesRead,
        }),
        flush: true,
      );
    } catch (_) {
      // Cache failures must not prevent a summary from being displayed.
    }
  }

  static PdfSummaryResult summarizePages(List<String> pages) {
    final candidates = <_Sentence>[];
    for (var page = 0; page < pages.length; page++) {
      final normalized = pages[page].replaceAll(RegExp(r'\s+'), ' ').trim();
      for (final value in normalized.split(RegExp(r'(?<=[.!?])\s+'))) {
        final sentence = value.trim();
        if (sentence.length >= 35 && sentence.length <= 500) {
          candidates.add(_Sentence(sentence, page + 1, candidates.length));
        }
      }
    }
    if (candidates.isEmpty) {
      return PdfSummaryResult(
        summary: const [],
        importantPoints: const [],
        pagesRead: pages.length,
      );
    }

    final frequencies = <String, int>{};
    for (final sentence in candidates) {
      for (final word in _words(sentence.text)) {
        if (!_stopWords.contains(word) && word.length > 2) {
          frequencies.update(word, (count) => count + 1, ifAbsent: () => 1);
        }
      }
    }
    final maximum = frequencies.values.fold<int>(1, (a, b) => a > b ? a : b);
    for (final sentence in candidates) {
      final words = _words(
        sentence.text,
      ).where((word) => !_stopWords.contains(word)).toList();
      final frequencyScore = words.isEmpty
          ? 0.0
          : words
                    .map((word) => (frequencies[word] ?? 0) / maximum)
                    .fold<double>(0, (a, b) => a + b) /
                words.length;
      final cueScore = _importantPattern.hasMatch(sentence.text) ? .35 : 0;
      final numberScore =
          RegExp(
            r'\b\d+(?:\.\d+)?%|\$\s?\d+|\b(?:19|20)\d{2}\b',
          ).hasMatch(sentence.text)
          ? .18
          : 0;
      sentence.score = frequencyScore + cueScore + numberScore;
    }

    final ranked = [...candidates]
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        return score == 0 ? a.order.compareTo(b.order) : score;
      });
    final summary = ranked.take(5).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return PdfSummaryResult(
      summary: summary.map((item) => item.text).toList(),
      importantPoints: ranked
          .take(8)
          .map((item) => PdfSummaryPoint(text: item.text, page: item.page))
          .toList(),
      pagesRead: pages.length,
    );
  }

  static Iterable<String> _words(String value) sync* {
    for (final match in RegExp(r"[A-Za-z][A-Za-z'-]+").allMatches(value)) {
      yield match.group(0)!.toLowerCase();
    }
  }

  static final _importantPattern = RegExp(
    r'\b(important|must|required|deadline|risk|warning|conclusion|result|'
    r'recommend|shall|effective|total|key|critical|action)\b',
    caseSensitive: false,
  );

  static const _stopWords = {
    'the',
    'and',
    'for',
    'that',
    'this',
    'with',
    'from',
    'are',
    'was',
    'were',
    'have',
    'has',
    'had',
    'not',
    'but',
    'you',
    'your',
    'their',
    'they',
    'its',
    'into',
    'than',
    'then',
    'also',
    'can',
    'will',
    'would',
    'should',
    'could',
    'about',
    'which',
    'when',
    'where',
    'what',
    'who',
    'how',
    'all',
    'any',
  };
}

class SummaryCancelled implements Exception {
  const SummaryCancelled();
}

class _Sentence {
  _Sentence(this.text, this.page, this.order);

  final String text;
  final int page;
  final int order;
  double score = 0;
}
