import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum StoredSignatureKind { drawn, image }

final _signatureCipher = AesGcm.with256bits();

Future<Uint8List> encryptSignaturePayload(
  List<int> bytes,
  SecretKey key,
) async {
  final box = await _signatureCipher.encrypt(bytes, secretKey: key);
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'v': 1,
        'nonce': base64Encode(box.nonce),
        'cipherText': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      }),
    ),
  );
}

Future<Uint8List> decryptSignaturePayload(
  List<int> payload,
  SecretKey key,
) async {
  final decoded = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
  if (decoded['v'] != 1) throw const FormatException('Unknown signature');
  final box = SecretBox(
    base64Decode(decoded['cipherText'] as String),
    nonce: base64Decode(decoded['nonce'] as String),
    mac: Mac(base64Decode(decoded['mac'] as String)),
  );
  return Uint8List.fromList(
    await _signatureCipher.decrypt(box, secretKey: key),
  );
}

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
  static const _legacyKey = 'papertrail_saved_signatures_v1';
  static const _secureKey = 'papertrail_saved_signatures_v2';
  static const _encryptionKey = 'papertrail_signature_encryption_key_v1';
  static const _storage = FlutterSecureStorage();

  Future<List<StoredSignature>> load() async {
    final prefs = await SharedPreferences.getInstance();
    var values = <String>[];
    try {
      final secure = await _storage.read(key: _secureKey);
      if (secure != null) values = (jsonDecode(secure) as List).cast<String>();
    } catch (_) {
      // The secure store can be temporarily unavailable before device unlock.
    }
    final legacy = prefs.getStringList(_legacyKey);
    if (values.isEmpty && legacy != null) values = legacy;
    final signatures = <StoredSignature>[];
    var migrated = legacy != null;
    for (final value in values) {
      try {
        var signature = StoredSignature.fromJson(
          jsonDecode(value) as Map<String, dynamic>,
        );
        if (signature.kind == StoredSignatureKind.image) {
          final path = signature.imagePath;
          if (path == null || !File(path).existsSync()) continue;
          if (!await _isEncryptedFile(File(path))) {
            signature = await _migrateImage(signature);
            migrated = true;
          }
        }
        signatures.add(signature);
      } catch (_) {
        // Ignore damaged entries without hiding the remaining signatures.
      }
    }
    if (migrated) await save(signatures);
    return signatures;
  }

  Future<void> save(List<StoredSignature> signatures) async {
    final prefs = await SharedPreferences.getInstance();
    final values = signatures.map((item) => jsonEncode(item.toJson())).toList();
    await _storage.write(key: _secureKey, value: jsonEncode(values));
    await prefs.remove(_legacyKey);
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
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final destination = File(
      '${directory.path}${Platform.pathSeparator}$id.ptsig',
    );
    await _encryptToFile(await source.readAsBytes(), destination);
    return StoredSignature(
      id: id,
      name: pickedFile!.name,
      kind: StoredSignatureKind.image,
      imagePath: destination.path,
    );
  }

  Future<StoredSignature> _migrateImage(StoredSignature signature) async {
    final source = File(signature.imagePath!);
    await _replaceWithEncrypted(source, await source.readAsBytes());
    return StoredSignature(
      id: signature.id,
      name: signature.name,
      kind: signature.kind,
      strokes: signature.strokes,
      imagePath: source.path,
    );
  }

  static Future<SecretKey> _secretKey() async {
    String? encoded;
    try {
      encoded = await _storage.read(key: _encryptionKey);
    } catch (_) {
      // Do not fall back to an unencrypted key.
    }
    if (encoded != null) return SecretKey(base64Decode(encoded));
    final key = await _signatureCipher.newSecretKey();
    final bytes = await key.extractBytes();
    await _storage.write(key: _encryptionKey, value: base64Encode(bytes));
    return key;
  }

  static Future<void> _encryptToFile(List<int> bytes, File destination) async {
    await destination.writeAsBytes(
      await encryptSignaturePayload(bytes, await _secretKey()),
      flush: true,
    );
  }

  static Future<Uint8List> readImageBytes(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    if (!await _isEncryptedFile(file, bytes: bytes)) {
      await _replaceWithEncrypted(file, bytes);
      return bytes;
    }
    return decryptSignaturePayload(bytes, await _secretKey());
  }

  static Future<bool> _isEncryptedFile(File file, {List<int>? bytes}) async {
    try {
      final payload = bytes ?? await file.readAsBytes();
      final decoded = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      return decoded['v'] == 1 &&
          decoded.containsKey('nonce') &&
          decoded.containsKey('cipherText') &&
          decoded.containsKey('mac');
    } catch (_) {
      return false;
    }
  }

  static Future<void> _replaceWithEncrypted(
    File source,
    List<int> bytes,
  ) async {
    final temporary = File(
      '${source.path}.${DateTime.now().microsecondsSinceEpoch}.ptsig.tmp',
    );
    final backup = File('${temporary.path}.backup');
    await _encryptToFile(bytes, temporary);
    try {
      await source.rename(backup.path);
      await temporary.rename(source.path);
      await backup.delete();
    } catch (_) {
      if (!await source.exists() && await backup.exists()) {
        await backup.rename(source.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
      if (await backup.exists() && await source.exists()) await backup.delete();
    }
  }
}

class SignaturePreview extends StatelessWidget {
  const SignaturePreview({required this.signature, this.color, super.key});

  final StoredSignature signature;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (signature.kind == StoredSignatureKind.image) {
      return FutureBuilder<Uint8List>(
        future: SignatureStore.readImageBytes(signature.imagePath!),
        builder: (context, snapshot) => snapshot.hasData
            ? Image.memory(snapshot.data!, fit: BoxFit.contain)
            : snapshot.hasError
            ? const Icon(Icons.broken_image_outlined)
            : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
