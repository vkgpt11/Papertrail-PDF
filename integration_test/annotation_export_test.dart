import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_reader/annotation_export.dart';
import 'package:pdf_reader/annotations.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  testWidgets('annotated export is readable on the device PDF engine', (
    tester,
  ) async {
    final directory = await getTemporaryDirectory();
    final source = File(
      '${directory.path}${Platform.pathSeparator}integration-source.pdf',
    );
    final pdf = pw.Document()
      ..addPage(pw.Page(build: (_) => pw.Center(child: pw.Text('Original'))));
    await source.writeAsBytes(await pdf.save());
    await File(
      '${source.path}.papertrail-annotations.json',
    ).writeAsString(
      jsonEncode([
        const AnnotationMark(
          tool: AnnotationTool.rectangle,
          page: 1,
          points: [Offset(.1, .1), Offset(.4, .3)],
        ).toJson(),
      ]),
    );

    final exported = await const AnnotationExporter().export(source.path);
    expect(exported.path, isNot(source.path));
    expect(await exported.exists(), isTrue);
    final opened = await PdfDocument.openFile(exported.path);
    try {
      expect(opened.pages, hasLength(1));
    } finally {
      await opened.dispose();
    }
  });
}
