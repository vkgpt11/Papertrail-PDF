import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import 'annotations.dart';
import 'signatures.dart';

class AnnotationExporter {
  const AnnotationExporter({
    Directory? temporaryDirectory,
    this.maximumPages = 200,
    this.maximumTotalPixels = 180000000,
  }) : _temporaryDirectory = temporaryDirectory;

  final Directory? _temporaryDirectory;
  final int maximumPages;
  final int maximumTotalPixels;

  Future<File> export(String pdfPath, {String? password}) async {
    final marks = await _loadMarks(pdfPath);
    if (marks.isEmpty) return File(pdfPath);
    PdfDocument? source;
    try {
      source = await PdfDocument.openFile(
        pdfPath,
        passwordProvider: password == null ? null : () => password,
      );
      validatePageCount(source.pages.length);
      final output = pw.Document();
      var totalPixels = 0;
      for (final page in source.pages) {
        final pageMarks = marks
            .where((mark) => mark.page == page.pageNumber)
            .toList();
        final scale = (1440 / page.width).clamp(.5, 2.0);
        final renderedPixels =
            (page.width * scale).round() * (page.height * scale).round();
        totalPixels += renderedPixels;
        if (totalPixels > maximumTotalPixels) {
          throw const AnnotationExportTooLarge(
            'This annotated PDF is too large to export safely on this device.',
          );
        }
        final rendered = requireRenderedAnnotationPage(
          await page.render(
            fullWidth: page.width * scale,
            fullHeight: page.height * scale,
          ),
          page.pageNumber,
        );
        ui.Image? base;
        ui.Image? flattened;
        try {
          base = await rendered.createImage();
          flattened = await _flattenPage(base, pageMarks);
          final data = requireEncodedAnnotationPage(
            await flattened.toByteData(format: ui.ImageByteFormat.png),
            page.pageNumber,
          );
          final image = pw.MemoryImage(data.buffer.asUint8List());
          final pageText = (await page.loadText()).trim();
          output.addPage(
            pw.Page(
              pageFormat: pdf.PdfPageFormat(page.width, page.height),
              margin: pw.EdgeInsets.zero,
              build: (_) => pw.Stack(
                children: [
                  pw.Positioned.fill(
                    child: pw.Image(image, fit: pw.BoxFit.fill),
                  ),
                  if (pageText.isNotEmpty)
                    pw.Positioned.fill(
                      child: pw.Opacity(
                        opacity: .01,
                        child: pw.Text(
                          pageText,
                          style: const pw.TextStyle(fontSize: 1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        } finally {
          flattened?.dispose();
          base?.dispose();
          rendered.dispose();
        }
        await Future<void>.delayed(Duration.zero);
      }
      final directory = _temporaryDirectory ?? await getTemporaryDirectory();
      final file = File(
        '${directory.path}${Platform.pathSeparator}'
        'papertrail-annotated-${DateTime.now().microsecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes(await output.save(), flush: true);
      return file;
    } finally {
      await source?.dispose();
    }
  }

  void validatePageCount(int pageCount) {
    if (pageCount > maximumPages) {
      throw AnnotationExportTooLarge(
        'Annotated export supports at most $maximumPages pages at once.',
      );
    }
  }

  Future<List<AnnotationMark>> _loadMarks(String pdfPath) async {
    try {
      final sidecar = File('$pdfPath.papertrail-annotations.json');
      if (!await sidecar.exists()) return const [];
      final decoded = jsonDecode(await sidecar.readAsString()) as List;
      return decoded
          .map((item) => AnnotationMark.fromJson(item as Map<String, dynamic>))
          .toList();
    } on FileSystemException {
      rethrow;
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Annotations could not be read: $error');
    }
  }

  Future<ui.Image> _flattenPage(
    ui.Image base,
    List<AnnotationMark> marks,
  ) async {
    final size = Size(base.width.toDouble(), base.height.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(base, Offset.zero, Paint());
    paintAnnotationMarks(canvas, size, marks);
    for (final mark in marks.where(
      (mark) => mark.tool == AnnotationTool.signature,
    )) {
      await _paintSignature(canvas, size, mark);
    }
    return recorder.endRecording().toImage(base.width, base.height);
  }

  Future<void> _paintSignature(
    Canvas canvas,
    Size size,
    AnnotationMark mark,
  ) async {
    if (mark.text == null || mark.points.isEmpty) return;
    StoredSignature signature;
    try {
      signature = StoredSignature.fromJson(
        jsonDecode(mark.text!) as Map<String, dynamic>,
      );
    } catch (_) {
      return;
    }
    final first = mark.points.first;
    final last = mark.points.length > 1 ? mark.points.last : first;
    final rect = Rect.fromPoints(
      Offset(first.dx * size.width, first.dy * size.height),
      Offset(last.dx * size.width, last.dy * size.height),
    );
    if (signature.kind == StoredSignatureKind.image) {
      final path = signature.imagePath;
      if (path == null) return;
      final file = File(path);
      if (!await file.exists()) return;
      final codec = await ui.instantiateImageCodec(
        await SignatureStore.readImageBytes(path),
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          canvas.drawImageRect(
            frame.image,
            Rect.fromLTWH(
              0,
              0,
              frame.image.width.toDouble(),
              frame.image.height.toDouble(),
            ),
            rect,
            Paint(),
          );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
      return;
    }
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in signature.strokes) {
      if (stroke.isEmpty) continue;
      final path = Path()
        ..moveTo(
          rect.left + stroke.first.dx * rect.width,
          rect.top + stroke.first.dy * rect.height,
        );
      for (final point in stroke.skip(1)) {
        path.lineTo(
          rect.left + point.dx * rect.width,
          rect.top + point.dy * rect.height,
        );
      }
      canvas.drawPath(path, paint);
    }
  }
}

PdfImage requireRenderedAnnotationPage(PdfImage? rendered, int pageNumber) {
  if (rendered == null) {
    throw StateError('Page $pageNumber could not be rendered for export.');
  }
  return rendered;
}

ByteData requireEncodedAnnotationPage(ByteData? data, int pageNumber) {
  if (data == null) {
    throw StateError('Page $pageNumber could not be encoded for export.');
  }
  return data;
}

class AnnotationExportTooLarge implements Exception {
  const AnnotationExportTooLarge(this.message);

  final String message;

  @override
  String toString() => message;
}
