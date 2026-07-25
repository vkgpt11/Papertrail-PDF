import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_reader/annotations.dart';

void main() {
  test('annotation points translate and stay inside the page', () {
    final moved = translateAnnotationPoints(const [
      Offset(.1, .2),
      Offset(.9, .8),
    ], const Offset(.3, -.4));
    expect(moved, const [Offset(.4, 0), Offset(1, .4)]);
  });

  for (final tool in AnnotationTool.values) {
    test('${tool.name} annotation survives JSON round trip', () {
      final mark = AnnotationMark(
        tool: tool,
        page: 7,
        points: const [Offset(.1, .2), Offset(.8, .9)],
        text: tool == AnnotationTool.note ? 'Review this' : null,
      );
      final restored = AnnotationMark.fromJson(mark.toJson());
      expect(restored.tool, tool);
      expect(restored.page, 7);
      expect(restored.points, mark.points);
      expect(restored.text, mark.text);
    });
  }
}
