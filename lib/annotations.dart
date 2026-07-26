import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'notifications.dart';
import 'signatures.dart';
import 'horizontal_scroll_cue.dart';

enum AnnotationTool {
  highlight,
  underline,
  strikethrough,
  draw,
  note,
  signature,
  rectangle,
  oval,
  stamp,
}

List<Offset> translateAnnotationPoints(
  List<Offset> points,
  Offset normalizedDelta,
) => points
    .map(
      (point) => Offset(
        (point.dx + normalizedDelta.dx).clamp(0, 1).toDouble(),
        (point.dy + normalizedDelta.dy).clamp(0, 1).toDouble(),
      ),
    )
    .toList();

class AnnotationMark {
  const AnnotationMark({
    required this.tool,
    required this.page,
    required this.points,
    this.text,
  });

  final AnnotationTool tool;
  final int page;
  final List<Offset> points;
  final String? text;

  Map<String, dynamic> toJson() => {
    'tool': tool.name,
    'page': page,
    'points': points.map((point) => [point.dx, point.dy]).toList(),
    'text': text,
  };

  factory AnnotationMark.fromJson(Map<String, dynamic> json) => AnnotationMark(
    tool: AnnotationTool.values.byName(json['tool'] as String),
    page: (json['page'] as num).toInt(),
    points: (json['points'] as List)
        .map(
          (point) => Offset(
            (point[0] as num).toDouble(),
            (point[1] as num).toDouble(),
          ),
        )
        .toList(),
    text: json['text'] as String?,
  );
}

class AnnotationLayer extends StatefulWidget {
  const AnnotationLayer({
    required this.pdfPath,
    required this.page,
    required this.enabled,
    required this.onDirtyChanged,
    super.key,
  });

  final String pdfPath;
  final int page;
  final bool enabled;
  final ValueChanged<bool> onDirtyChanged;

  @override
  AnnotationLayerState createState() => AnnotationLayerState();
}

class AnnotationLayerState extends State<AnnotationLayer> {
  final _signatureStore = SignatureStore();
  final _pageChanges = ValueNotifier<int>(0);
  final List<AnnotationMark> _marks = [];
  final List<AnnotationMark> _redo = [];
  List<StoredSignature> _signatures = [];
  StoredSignature? _selectedSignature;
  List<Offset> _active = [];
  int? _activePage;
  int? _movingMarkIndex;
  Offset? _moveStart;
  List<Offset> _originalMovePoints = [];
  bool _didMoveMark = false;
  AnnotationTool? _tool;
  late final Future<void> _loadFuture;
  Future<void>? _saveInProgress;
  bool _loaded = false;
  int _revision = 0;

  String get _sidecarPath => '${widget.pdfPath}.papertrail-annotations.json';

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
    _loadSignatures();
  }

  @override
  void dispose() {
    _pageChanges.dispose();
    super.dispose();
  }

  Future<void> _loadSignatures() async {
    final signatures = await _signatureStore.load();
    if (mounted) setState(() => _signatures = signatures);
  }

  Future<void> _load() async {
    try {
      final file = File(_sidecarPath);
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString()) as List;
      if (!mounted) return;
      setState(() {
        _marks
          ..clear()
          ..addAll(
            decoded.map(
              (item) => AnnotationMark.fromJson(item as Map<String, dynamic>),
            ),
          );
        _loaded = true;
      });
      _notifyPages();
    } catch (_) {
      // A damaged sidecar must never prevent the PDF from opening.
    } finally {
      if (mounted && !_loaded) setState(() => _loaded = true);
    }
  }

  Future<void> _save() async {
    await _loadFuture;
    while (_saveInProgress != null) {
      await _saveInProgress;
    }
    final revision = _revision;
    final contents = jsonEncode(_marks.map((mark) => mark.toJson()).toList());
    final save = _writeAtomically(contents);
    _saveInProgress = save;
    try {
      await save;
      if (revision == _revision) widget.onDirtyChanged(false);
      if (mounted) {
        PapertrailNotice.show(
          context,
          'Annotations saved',
          icon: Icons.save_outlined,
        );
      }
    } finally {
      if (identical(_saveInProgress, save)) _saveInProgress = null;
    }
  }

  Future<void> save() => _save();

  Future<void> waitForPendingSave() async {
    while (_saveInProgress != null) {
      await _saveInProgress;
    }
  }

  Future<void> _writeAtomically(String contents) async {
    final target = File(_sidecarPath);
    final temporary = File(
      '$_sidecarPath.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsString(contents, flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  void _notifyPages() => _pageChanges.value++;

  void _changed() {
    _revision++;
    _notifyPages();
    widget.onDirtyChanged(true);
  }

  Widget buildPageOverlay(int page) =>
      _AnnotationPageSurface(owner: this, page: page);

  Offset _normalized(Offset point, Size size) =>
      Offset(point.dx / size.width, point.dy / size.height);

  Future<void> _finish(int page, Size size) async {
    if (_active.isEmpty) return;
    final tool = _tool;
    if (tool == null) {
      setState(() {
        _active = [];
        _activePage = null;
      });
      _notifyPages();
      return;
    }
    String? text;
    if (tool == AnnotationTool.note) {
      final controller = TextEditingController();
      text = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add note'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Write a comment'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Add'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (text == null || text.trim().isEmpty) {
        setState(() {
          _active = [];
          _activePage = null;
        });
        _notifyPages();
        return;
      }
    }
    if (tool == AnnotationTool.signature) {
      final signature = _selectedSignature;
      if (signature == null) {
        setState(() {
          _active = [];
          _activePage = null;
        });
        _notifyPages();
        return;
      }
      if (_active.length == 1) {
        final start = _active.first;
        _active.add(
          Offset(
            (start.dx + 180).clamp(0, size.width).toDouble(),
            (start.dy + 80).clamp(0, size.height).toDouble(),
          ),
        );
      }
      text = jsonEncode(signature.toJson());
    }
    setState(() {
      _marks.add(
        AnnotationMark(
          tool: tool,
          page: page,
          points: _active.map((point) => _normalized(point, size)).toList(),
          text: text,
        ),
      );
      _active = [];
      _activePage = null;
      _redo.clear();
    });
    _changed();
  }

  void _undo() {
    if (_marks.isEmpty) return;
    setState(() => _redo.add(_marks.removeLast()));
    _changed();
  }

  void _redoLast() {
    if (_redo.isEmpty) return;
    setState(() => _marks.add(_redo.removeLast()));
    _changed();
  }

  Rect _hitRect(AnnotationMark mark, Size size) {
    if (mark.tool == AnnotationTool.signature) {
      return _markRect(mark, size).inflate(18);
    }
    final points = mark.points
        .map((point) => Offset(point.dx * size.width, point.dy * size.height))
        .toList();
    if (points.isEmpty) return Rect.zero;
    if (mark.tool == AnnotationTool.note) {
      return Rect.fromLTWH(points.first.dx - 18, points.first.dy - 18, 220, 90);
    }
    if (mark.tool == AnnotationTool.stamp) {
      return Rect.fromLTWH(points.first.dx - 18, points.first.dy - 18, 150, 70);
    }
    var left = points.first.dx;
    var right = points.first.dx;
    var top = points.first.dy;
    var bottom = points.first.dy;
    for (final point in points.skip(1)) {
      left = math.min(left, point.dx);
      right = math.max(right, point.dx);
      top = math.min(top, point.dy);
      bottom = math.max(bottom, point.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom).inflate(20);
  }

  int? _markAt(int page, Offset position, Size size) {
    for (var index = _marks.length - 1; index >= 0; index--) {
      final mark = _marks[index];
      if (mark.page == page && _hitRect(mark, size).contains(position)) {
        return index;
      }
    }
    return null;
  }

  void _startAnnotationGesture(int page, Offset position, Size size) {
    final index = _markAt(page, position, size);
    setState(() {
      if (index == null) {
        _movingMarkIndex = null;
        _moveStart = null;
        _originalMovePoints = [];
        _didMoveMark = false;
        _active = [position];
        _activePage = page;
      } else {
        _movingMarkIndex = index;
        _moveStart = position;
        _originalMovePoints = [..._marks[index].points];
        _didMoveMark = false;
        _active = [];
        _activePage = page;
      }
    });
  }

  void _updateAnnotationGesture(Offset position, Size size) {
    final index = _movingMarkIndex;
    final start = _moveStart;
    if (index == null || start == null) {
      setState(() => _active.add(position));
      _notifyPages();
      return;
    }
    final delta = Offset(
      (position.dx - start.dx) / size.width,
      (position.dy - start.dy) / size.height,
    );
    final mark = _marks[index];
    setState(() {
      _didMoveMark = delta.distanceSquared > 0;
      _marks[index] = AnnotationMark(
        tool: mark.tool,
        page: mark.page,
        points: translateAnnotationPoints(_originalMovePoints, delta),
        text: mark.text,
      );
    });
    _notifyPages();
  }

  Future<void> _endAnnotationGesture(int page, Size size) async {
    if (_movingMarkIndex != null) {
      final changed = _didMoveMark;
      setState(() {
        _movingMarkIndex = null;
        _moveStart = null;
        _originalMovePoints = [];
        _didMoveMark = false;
        _activePage = null;
        _redo.clear();
      });
      if (changed) _changed();
      return;
    }
    await _finish(page, size);
  }

  Future<void> _chooseSignature() async {
    StoredSignature? selected;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateSheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .65,
            child: Column(
              children: [
                const ListTile(
                  title: Text(
                    'Choose a signature',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    'Signatures are stored privately on this device.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            final signature = await showDrawSignatureDialog(
                              context,
                            );
                            if (signature == null) return;
                            _signatures = [..._signatures, signature];
                            await _signatureStore.save(_signatures);
                            updateSheet(() {});
                          },
                          icon: const Icon(Icons.gesture_rounded),
                          label: const Text('Draw new'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              final signature = await _signatureStore
                                  .importImage();
                              if (signature == null) return;
                              _signatures = [..._signatures, signature];
                              await _signatureStore.save(_signatures);
                              updateSheet(() {});
                            } on FileSystemException catch (error) {
                              if (!context.mounted) return;
                              PapertrailNotice.show(
                                context,
                                error.message,
                                isError: true,
                              );
                            }
                          },
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('Import image'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _signatures.isEmpty
                      ? const Center(child: Text('No saved signatures yet.'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _signatures.length,
                          itemBuilder: (context, index) {
                            final signature = _signatures[index];
                            return Card(
                              child: ListTile(
                                leading: SizedBox(
                                  width: 72,
                                  height: 42,
                                  child: SignaturePreview(signature: signature),
                                ),
                                title: Text(signature.name),
                                subtitle: Text(
                                  signature.kind == StoredSignatureKind.drawn
                                      ? 'Drawn signature'
                                      : 'Image signature',
                                ),
                                onTap: () {
                                  selected = signature;
                                  Navigator.pop(sheetContext);
                                },
                                trailing: IconButton(
                                  tooltip: 'Delete saved signature',
                                  onPressed: () async {
                                    _signatures.removeAt(index);
                                    await _signatureStore.save(_signatures);
                                    updateSheet(() {});
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedSignature = selected;
      _tool = AnnotationTool.signature;
    });
    PapertrailNotice.show(
      context,
      'Drag on the page to place the signature',
      icon: Icons.border_color_outlined,
    );
  }

  StoredSignature? _signatureFromMark(AnnotationMark mark) {
    if (mark.tool != AnnotationTool.signature || mark.text == null) return null;
    try {
      return StoredSignature.fromJson(
        jsonDecode(mark.text!) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Rect _markRect(AnnotationMark mark, Size size) {
    final first = mark.points.first;
    final last = mark.points.length > 1 ? mark.points.last : first;
    final rect = Rect.fromPoints(
      Offset(first.dx * size.width, first.dy * size.height),
      Offset(last.dx * size.width, last.dy * size.height),
    );
    return Rect.fromLTWH(
      rect.left,
      rect.top,
      rect.width < 40 ? 180 : rect.width,
      rect.height < 24 ? 80 : rect.height,
    );
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      if (widget.enabled)
        Positioned(
          left: 8,
          right: 8,
          bottom: 92,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            child: HorizontalScrollCue(
              builder: (scrollController) => SingleChildScrollView(
                controller: scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    for (final tool in AnnotationTool.values)
                      IconButton(
                        tooltip: tool == AnnotationTool.signature
                            ? 'Add signature'
                            : tool.name,
                        isSelected: _tool == tool,
                        onPressed: !_loaded
                            ? null
                            : tool == AnnotationTool.signature
                            ? _chooseSignature
                            : () => setState(
                                () => _tool = _tool == tool ? null : tool,
                              ),
                        icon: tool == AnnotationTool.signature
                            ? const _SignatureToolIcon()
                            : Icon(_iconFor(tool)),
                      ),
                    const VerticalDivider(),
                    IconButton(
                      tooltip: 'Undo',
                      onPressed: _marks.isEmpty ? null : _undo,
                      icon: const Icon(Icons.undo),
                    ),
                    IconButton(
                      tooltip: 'Redo',
                      onPressed: _redo.isEmpty ? null : _redoLast,
                      icon: const Icon(Icons.redo),
                    ),
                    IconButton(
                      tooltip: 'Save annotations',
                      onPressed: _loaded && _saveInProgress == null
                          ? _save
                          : null,
                      icon: const Icon(Icons.save_outlined),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );

  IconData _iconFor(AnnotationTool tool) => switch (tool) {
    AnnotationTool.highlight => Icons.highlight,
    AnnotationTool.underline => Icons.format_underlined,
    AnnotationTool.strikethrough => Icons.format_strikethrough,
    AnnotationTool.draw => Icons.draw,
    AnnotationTool.note => Icons.note_add_outlined,
    AnnotationTool.signature => Icons.border_color_outlined,
    AnnotationTool.rectangle => Icons.rectangle_outlined,
    AnnotationTool.oval => Icons.circle_outlined,
    AnnotationTool.stamp => Icons.approval_outlined,
  };
}

class _AnnotationPageSurface extends StatelessWidget {
  const _AnnotationPageSurface({required this.owner, required this.page});

  final AnnotationLayerState owner;
  final int page;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: owner._pageChanges,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final pageMarks = owner._marks
            .where((mark) => mark.page == page)
            .toList();
        return Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              ignoring: !owner.widget.enabled || !owner._loaded,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (details) => owner._startAnnotationGesture(
                  page,
                  details.localPosition,
                  size,
                ),
                onPanUpdate: (details) =>
                    owner._updateAnnotationGesture(details.localPosition, size),
                onPanEnd: (_) => owner._endAnnotationGesture(page, size),
                onTapUp: (details) {
                  owner._startAnnotationGesture(
                    page,
                    details.localPosition,
                    size,
                  );
                  owner._endAnnotationGesture(page, size);
                },
                child: CustomPaint(
                  painter: _AnnotationPainter(
                    marks: pageMarks,
                    active: owner._activePage == page
                        ? owner._active
                        : const <Offset>[],
                    activeTool: owner._activePage == page ? owner._tool : null,
                  ),
                ),
              ),
            ),
            for (final mark in pageMarks.where(
              (mark) =>
                  mark.tool == AnnotationTool.signature &&
                  owner._signatureFromMark(mark) != null,
            ))
              Positioned.fromRect(
                rect: owner._markRect(mark, size),
                child: IgnorePointer(
                  child: SignaturePreview(
                    signature: owner._signatureFromMark(mark)!,
                    color: Colors.black,
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _SignatureToolIcon extends StatelessWidget {
  const _SignatureToolIcon();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 28,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(left: 0, bottom: 1, child: Icon(Icons.gesture, size: 25)),
        Positioned(
          right: -1,
          top: -1,
          child: Icon(Icons.edit_rounded, size: 14),
        ),
      ],
    ),
  );
}

class _AnnotationPainter extends CustomPainter {
  const _AnnotationPainter({
    required this.marks,
    required this.active,
    required this.activeTool,
  });

  final List<AnnotationMark> marks;
  final List<Offset> active;
  final AnnotationTool? activeTool;

  @override
  void paint(Canvas canvas, Size size) {
    for (final mark in marks) {
      _paintMark(
        canvas,
        size,
        mark.tool,
        mark.points
            .map(
              (point) => Offset(point.dx * size.width, point.dy * size.height),
            )
            .toList(),
        mark.text,
      );
    }
    final tool = activeTool;
    if (tool != null) {
      _paintMark(canvas, size, tool, active, null);
    }
  }

  void _paintMark(
    Canvas canvas,
    Size size,
    AnnotationTool tool,
    List<Offset> points,
    String? text,
  ) {
    if (points.isEmpty) return;
    if (tool == AnnotationTool.signature) {
      if (text == null && points.length > 1) {
        canvas.drawRect(
          Rect.fromPoints(points.first, points.last),
          Paint()
            ..color = Colors.blue
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      }
      return;
    }
    final color = switch (tool) {
      AnnotationTool.highlight => Colors.yellow.withValues(alpha: .42),
      AnnotationTool.underline => Colors.blue,
      AnnotationTool.strikethrough => Colors.red,
      AnnotationTool.signature => Colors.black,
      _ => Colors.deepPurple,
    };
    final paint = Paint()
      ..color = color
      ..strokeWidth = tool == AnnotationTool.highlight ? 18 : 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (tool == AnnotationTool.note) {
      canvas.drawCircle(points.first, 13, Paint()..color = Colors.amber);
      TextPainter(
          text: TextSpan(
            text: 'N',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )
        ..layout()
        ..paint(canvas, points.first - const Offset(5, 9));
      if (text != null) {
        final label = TextPainter(
          text: TextSpan(
            text: text,
            style: const TextStyle(color: Colors.black, fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 180);
        canvas.drawRect(
          Rect.fromLTWH(
            points.first.dx + 16,
            points.first.dy,
            label.width + 10,
            label.height + 8,
          ),
          Paint()..color = Colors.amber.shade100,
        );
        label.paint(canvas, points.first + const Offset(21, 4));
      }
      return;
    }
    if (tool == AnnotationTool.stamp) {
      final label = TextPainter(
        text: const TextSpan(
          text: 'APPROVED',
          style: TextStyle(
            color: Colors.green,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, points.first);
      return;
    }
    if ((tool == AnnotationTool.rectangle || tool == AnnotationTool.oval) &&
        points.length > 1) {
      final rect = Rect.fromPoints(points.first, points.last);
      tool == AnnotationTool.rectangle
          ? canvas.drawRect(rect, paint)
          : canvas.drawOval(rect, paint);
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) => true;
}

void paintAnnotationMarks(
  Canvas canvas,
  Size size,
  List<AnnotationMark> marks,
) {
  _AnnotationPainter(
    marks: marks
        .where((mark) => mark.tool != AnnotationTool.signature)
        .toList(),
    active: const [],
    activeTool: null,
  ).paint(canvas, size);
}
