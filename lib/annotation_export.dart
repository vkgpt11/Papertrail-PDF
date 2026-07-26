import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import 'annotations.dart';
import 'signatures.dart';

class AnnotationExporter {
  const AnnotationExporter({Directory? temporaryDirectory})
    : _temporaryDirectory = temporaryDirectory;

  final Directory? _temporaryDirectory;

  Future<File> export(String pdfPath, {String? password}) async {
    final marks = await _loadMarks(pdfPath);
    if (marks.isEmpty) return File(pdfPath);
    PdfDocument? source;
    try {
      source = await PdfDocument.openFile(
        pdfPath,
        passwordProvider: password == null ? null : () => password,
      );
      final output = pw.Document();
      var exportedPages = 0;
      for (final page in source.pages) {
        final pageMarks = marks
            .where((mark) => mark.page == page.pageNumber)
            .toList();
        final scale = (1600 / page.width).clamp(1.0, 2.0);
        final rendered = await page.render(
          fullWidth: page.width * scale,
          fullHeight: page.height * scale,
        );
        if (rendered == null) {
          throw StateError(
            'Page ${page.pageNumber} could not be rendered for export.',
          );
        }
        ui.Image? base;
        ui.Image? flattened;
        try {
          base = await rendered.createImage();
          flattened = await _flattenPage(base, pageMarks);
          final data = await flattened.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (data == null) {
            throw StateError(
              'Page ${page.pageNumber} could not be encoded for export.',
            );
          }
          final image = pw.MemoryImage(data.buffer.asUint8List());
          output.addPage(
            pw.Page(
              pageFormat: pdf.PdfPageFormat(page.width, page.height),
              margin: pw.EdgeInsets.zero,
              build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
            ),
          );
          exportedPages++;
        } finally {
          flattened?.dispose();
          base?.dispose();
          rendered.dispose();
        }
        await Future<void>.delayed(Duration.zero);
      }
      if (exportedPages != source.pages.length) {
        throw StateError('The annotated export is incomplete.');
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

  Future<List<AnnotationMark>> _loadMarks(String pdfPath) async {
    try {
      final sidecar = File('$pdfPath.papertrail-annotations.json');
      if (!await sidecar.exists()) return const [];
      final decoded = jsonDecode(await sidecar.readAsString()) as List;
      return decoded
          .map((item) => AnnotationMark.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
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
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
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
