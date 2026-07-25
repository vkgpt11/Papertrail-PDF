import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum StoredSignatureKind { drawn, image }

class StoredSignature {
  const StoredSignature({
    required this.id,
    required this.name,
    required this.kind,
    this.strokes = const [],
    this.imagePath,
  });

  final String id;
  final String name;
  final StoredSignatureKind kind;
  final List<List<Offset>> strokes;
  final String? imagePath;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'strokes': strokes
        .map((stroke) => stroke.map((point) => [point.dx, point.dy]).toList())
        .toList(),
    'imagePath': imagePath,
  };

  factory StoredSignature.fromJson(Map<String, dynamic> json) =>
      StoredSignature(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Signature',
        kind: StoredSignatureKind.values.byName(json['kind'] as String),
        strokes:
            (json['strokes'] as List?)
                ?.map(
                  (stroke) => (stroke as List)
                      .map(
                        (point) => Offset(
                          ((point as List)[0] as num).toDouble(),
                          (point[1] as num).toDouble(),
                        ),
                      )
                      .toList(),
                )
                .toList() ??
            const [],
        imagePath: json['imagePath'] as String?,
      );
}

class SignatureStore {
  static const _key = 'papertrail_saved_signatures_v1';

  Future<List<StoredSignature>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_key) ?? const [];
    final signatures = <StoredSignature>[];
    for (final value in values) {
      try {
        final signature = StoredSignature.fromJson(
          jsonDecode(value) as Map<String, dynamic>,
        );
        if (signature.kind == StoredSignatureKind.image &&
            (signature.imagePath == null ||
                !File(signature.imagePath!).existsSync())) {
          continue;
        }
        signatures.add(signature);
      } catch (_) {
        // Ignore damaged entries without hiding the remaining signatures.
      }
    }
    return signatures;
  }

  Future<void> save(List<StoredSignature> signatures) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      signatures.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  Future<StoredSignature?> importImage() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    final pickedFile = picked?.files.single;
    final sourcePath = pickedFile?.path;
    if (sourcePath == null) return null;
    final source = File(sourcePath);
    if (!await source.exists()) return null;
    if (await source.length() > 8 * 1024 * 1024) {
      throw const FileSystemException(
        'Signature images must be smaller than 8 MB.',
      );
    }
    final directory = Directory(
      '${(await getApplicationSupportDirectory()).path}'
      '${Platform.pathSeparator}signatures',
    );
    await directory.create(recursive: true);
    final extension = sourcePath.split('.').last.toLowerCase();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final destination = File(
      '${directory.path}${Platform.pathSeparator}$id.$extension',
    );
    await source.copy(destination.path);
    return StoredSignature(
      id: id,
      name: pickedFile!.name,
      kind: StoredSignatureKind.image,
      imagePath: destination.path,
    );
  }
}

class SignaturePreview extends StatelessWidget {
  const SignaturePreview({required this.signature, this.color, super.key});

  final StoredSignature signature;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (signature.kind == StoredSignatureKind.image) {
      return Image.file(
        File(signature.imagePath!),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
      );
    }
    return CustomPaint(
      painter: SignatureStrokePainter(
        strokes: signature.strokes,
        color: color ?? Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class SignatureStrokePainter extends CustomPainter {
  const SignatureStrokePainter({required this.strokes, required this.color});

  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final path = Path()
        ..moveTo(stroke.first.dx * size.width, stroke.first.dy * size.height);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx * size.width, point.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SignatureStrokePainter oldDelegate) =>
      oldDelegate.strokes != strokes || oldDelegate.color != color;
}

Future<StoredSignature?> showDrawSignatureDialog(BuildContext context) async {
  final strokes = <List<Offset>>[];
  var active = <Offset>[];
  final nameController = TextEditingController(text: 'My signature');
  final result = await showDialog<StoredSignature>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('Draw signature'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Signature name'),
              ),
              const SizedBox(height: 12),
              Container(
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black26),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.biggest;
                    Offset normalize(Offset point) => Offset(
                      (point.dx / size.width).clamp(0, 1),
                      (point.dy / size.height).clamp(0, 1),
                    );
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) => update(
                        () => active = [normalize(details.localPosition)],
                      ),
                      onPanUpdate: (details) => update(
                        () => active.add(normalize(details.localPosition)),
                      ),
                      onPanEnd: (_) => update(() {
                        if (active.isNotEmpty) strokes.add([...active]);
                        active = [];
                      }),
                      child: CustomPaint(
                        painter: SignatureStrokePainter(
                          strokes: [...strokes, if (active.isNotEmpty) active],
                          color: Colors.black,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => update(() {
              strokes.clear();
              active = [];
            }),
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: strokes.isEmpty
                ? null
                : () {
                    final id = DateTime.now().microsecondsSinceEpoch.toString();
                    Navigator.pop(
                      context,
                      StoredSignature(
                        id: id,
                        name: nameController.text.trim().isEmpty
                            ? 'Signature'
                            : nameController.text.trim(),
                        kind: StoredSignatureKind.drawn,
                        strokes: strokes.map((stroke) => [...stroke]).toList(),
                      ),
                    );
                  },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  nameController.dispose();
  return result;
}
