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

  Future<void> _scrollToward(double direction) async {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final distance = position.viewportDimension * .8;
    final target = (position.pixels + (distance * direction)).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 1) return;
    await _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateCues();
    });
    final surface = Theme.of(context).colorScheme.surface;
    final rightToLeft = Directionality.of(context) == TextDirection.rtl;
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
              tooltip: rightToLeft ? 'Show more items' : 'Show previous items',
              onPressed: () => _scrollToward(-1),
            ),
          if (_showRight)
            _ScrollEdgeCue(
              alignment: Alignment.centerRight,
              icon: Icons.chevron_right_rounded,
              surface: surface,
              tooltip: rightToLeft ? 'Show previous items' : 'Show more items',
              onPressed: () => _scrollToward(1),
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
    required this.tooltip,
    required this.onPressed,
  });

  final Alignment alignment;
  final IconData icon;
  final Color surface;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isLeft = alignment == Alignment.centerLeft;
    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: 0,
      bottom: 0,
      child: Container(
        width: 52,
        alignment: alignment,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
            end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
            colors: [surface, surface.withValues(alpha: 0)],
          ),
        ),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            minimumSize: const Size.square(48),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          icon: Icon(icon, size: 24),
        ),
      ),
    );
  }
}
