import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader/annotation_export.dart';

void main() {
  test(
    'damaged annotations stop export instead of silently disappearing',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'papertrail-damaged-annotations-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final pdf = File('${directory.path}/document.pdf');
      await pdf.writeAsBytes([1, 2, 3]);
      await File('${pdf.path}.papertrail-annotations.json').writeAsString('{');

      await expectLater(
        AnnotationExporter(temporaryDirectory: directory).export(pdf.path),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('oversized annotated export is rejected before rendering pages', () {
    expect(
      () => const AnnotationExporter(maximumPages: 1).validatePageCount(2),
      throwsA(isA<AnnotationExportTooLarge>()),
    );
  });

  test('render failure stops export with the affected page number', () {
    expect(
      () => requireRenderedAnnotationPage(null, 7),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Page 7'),
        ),
      ),
    );
  });

  test('encode failure stops export with the affected page number', () {
    expect(
      () => requireEncodedAnnotationPage(null, 9),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Page 9'),
        ),
      ),
    );
  });
}
