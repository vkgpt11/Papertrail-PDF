import 'package:flutter/material.dart';

class HorizontalScrollCue extends StatefulWidget {
  const HorizontalScrollCue({required this.builder, super.key});

  final Widget Function(ScrollController controller) builder;

  @override
  State<HorizontalScrollCue> createState() => _HorizontalScrollCueState();
}

class _HorizontalScrollCueState extends State<HorizontalScrollCue> {
  final _controller = ScrollController();
  bool _showLeft = false;
  bool _showRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateCues);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_updateCues)
      ..dispose();
    super.dispose();
  }

  void _updateCues() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final left = position.pixels > position.minScrollExtent + 2;
    final right = position.pixels < position.maxScrollExtent - 2;
    if (left != _showLeft || right != _showRight) {
      setState(() {
        _showLeft = left;
        _showRight = right;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateCues();
    });
    final surface = Theme.of(context).colorScheme.surface;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _updateCues();
        });
        return false;
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.builder(_controller),
          if (_showLeft)
            _ScrollEdgeCue(
              alignment: Alignment.centerLeft,
              icon: Icons.chevron_left_rounded,
              surface: surface,
            ),
          if (_showRight)
            _ScrollEdgeCue(
              alignment: Alignment.centerRight,
              icon: Icons.chevron_right_rounded,
              surface: surface,
            ),
        ],
      ),
    );
  }
}

class _ScrollEdgeCue extends StatelessWidget {
  const _ScrollEdgeCue({
    required this.alignment,
    required this.icon,
    required this.surface,
  });

  final Alignment alignment;
  final IconData icon;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final isLeft = alignment == Alignment.centerLeft;
    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Semantics(
          label: isLeft ? 'More items to the left' : 'More items to the right',
          child: Container(
            width: 42,
            alignment: alignment,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
                end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
                colors: [surface, surface.withValues(alpha: 0)],
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 22,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
