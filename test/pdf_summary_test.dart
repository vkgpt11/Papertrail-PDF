import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader/pdf_summary.dart';

void main() {
  test('summary ranks important sentences and retains page references', () {
    final result = PdfSummaryService.summarizePages([
      'This document describes the ordinary background of the project. '
          'The critical deadline is 30 June 2027 and all applications must be received before that date.',
      'The project provides several routine administrative services. '
          'Important: the total approved budget is \$250,000 and spending requires written approval.',
    ]);

    expect(result.pagesRead, 2);
    expect(result.summary, isNotEmpty);
    expect(
      result.importantPoints.first.text.toLowerCase(),
      anyOf(contains('critical'), contains('important')),
    );
    expect(result.importantPoints.map((point) => point.page), contains(2));
  });

  test('empty and scanned pages produce an empty result', () {
    final result = PdfSummaryService.summarizePages(['', '   ']);
    expect(result.summary, isEmpty);
    expect(result.importantPoints, isEmpty);
  });

  test('summary work can be cancelled before opening a document', () async {
    expect(
      () =>
          PdfSummaryService().summarize('missing.pdf', isCancelled: () => true),
      throwsA(isA<SummaryCancelled>()),
    );
  });
}
