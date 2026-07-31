import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A "+" assign button the owner/manager can drag anywhere within the body
// area; position is remembered (as a fraction of the available space, so it
// survives screen-size/orientation changes) across app restarts.
class DraggableFab extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget label;
  const DraggableFab({super.key, required this.onPressed, required this.label});

  @override
  State<DraggableFab> createState() => _DraggableFabState();
}

class _DraggableFabState extends State<DraggableFab> {
  static const _kX = 'assign_fab_x_frac';
  static const _kY = 'assign_fab_y_frac';

  Offset _fraction = const Offset(1, 1); // default: bottom-right, like a normal FAB
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble(_kX);
    final y = prefs.getDouble(_kY);
    if (!mounted) return;
    setState(() {
      if (x != null && y != null) _fraction = Offset(x, y);
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kX, _fraction.dx);
    await prefs.setDouble(_kY, _fraction.dy);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    // Positioned must be a DIRECT child of a Stack to take effect — nesting
    // an inner Stack here (rather than returning Positioned straight out of
    // LayoutBuilder) is what makes that true regardless of how this widget
    // itself is placed in the outer Stack.
    return Positioned.fill(
      child: LayoutBuilder(builder: (context, constraints) {
        const fabHeight = 56.0;
        const fabWidth = 160.0; // rough width of an extended FAB — clamped, not measured
        final maxX = (constraints.maxWidth - fabWidth).clamp(0.0, double.infinity);
        final maxY = (constraints.maxHeight - fabHeight).clamp(0.0, double.infinity);
        final left = _fraction.dx * maxX;
        final top = _fraction.dy * maxY;

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    final newLeft = (left + details.delta.dx).clamp(0.0, maxX);
                    final newTop = (top + details.delta.dy).clamp(0.0, maxY);
                    _fraction = Offset(
                      maxX > 0 ? newLeft / maxX : 0,
                      maxY > 0 ? newTop / maxY : 0,
                    );
                  });
                },
                onPanEnd: (_) => _save(),
                child: FloatingActionButton.extended(
                  onPressed: widget.onPressed,
                  icon: const Icon(Icons.add),
                  label: widget.label,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
