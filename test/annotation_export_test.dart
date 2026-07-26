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
}
