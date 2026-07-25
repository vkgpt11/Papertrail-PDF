import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader/signatures.dart';

void main() {
  test('drawn signature survives JSON round trip', () {
    const signature = StoredSignature(
      id: 'signature-1',
      name: 'Primary',
      kind: StoredSignatureKind.drawn,
      strokes: [
        [Offset(.1, .2), Offset(.8, .7)],
      ],
    );

    final restored = StoredSignature.fromJson(signature.toJson());

    expect(restored.id, signature.id);
    expect(restored.name, signature.name);
    expect(restored.kind, StoredSignatureKind.drawn);
    expect(restored.strokes, signature.strokes);
  });

  test('image signature path survives JSON round trip', () {
    const signature = StoredSignature(
      id: 'signature-2',
      name: 'Imported',
      kind: StoredSignatureKind.image,
      imagePath: r'C:\private\signature.png',
    );

    final restored = StoredSignature.fromJson(signature.toJson());

    expect(restored.kind, StoredSignatureKind.image);
    expect(restored.imagePath, signature.imagePath);
  });
}
