import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:animations/animations.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_theme.dart';

// Central place for "does motion play at all" — the OS reduced-motion
// setting wins over every effect below. Widgets in this file check this
// before animating instead of each screen remembering to.
bool reducedMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

// ---------------- List entrance stagger ----------------

// Wrap each item of a ListView.builder in this, passing its index — items
// fade+slide in with a delay proportional to position, capped so a long
// list doesn't make row 40 wait two seconds to appear.
class StaggeredListItem extends StatelessWidget {
  final int index;
  final Widget child;
  const StaggeredListItem({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    if (reducedMotion(context)) return child;
    final delay = Duration(milliseconds: 25 * index.clamp(0, 12));
    return child
        .animate(delay: delay)
        .fadeIn(duration: 260.ms, curve: Curves.easeOut)
        .slideY(begin: 0.06, end: 0, duration: 300.ms, curve: Curves.easeOutCubic);
  }
}

// ---------------- Fade-through tab body switch ----------------

// Swaps HomeScreen's tab body with a fade-through crossfade instead of an
// instant jump-cut. `tabKey` must change when the tab changes (e.g. the
// tab index or label) to trigger the transition.
class FadeThroughSwitcher extends StatelessWidget {
  final Object tabKey;
  final Widget child;
  const FadeThroughSwitcher({super.key, required this.tabKey, required this.child});

  @override
  Widget build(BuildContext context) {
    return PageTransitionSwitcher(
      duration: reducedMotion(context) ? Duration.zero : const Duration(milliseconds: 260),
      transitionBuilder: (child, primary, secondary) => FadeThroughTransition(
        animation: primary,
        secondaryAnimation: secondary,
        fillColor: Colors.transparent,
        child: child,
      ),
      child: KeyedSubtree(key: ValueKey(tabKey), child: child),
    );
  }
}

// ---------------- Shared-axis push route ----------------

// Drop-in replacement for MaterialPageRoute on Navigator.push — same call
// shape, just a considered transition instead of the platform default.
Route<T> sharedAxisRoute<T>(
  Widget page, {
  SharedAxisTransitionType type = SharedAxisTransitionType.horizontal,
}) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (reducedMotion(context)) return child;
      return SharedAxisTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        transitionType: type,
        child: child,
      );
    },
  );
}

// ---------------- Press feedback ----------------

// A gentle scale-down on press for cards/tiles that otherwise only show a
// ripple — makes tapping feel tactile without adding a new visual language.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  const PressableScale({super.key, required this.child, this.onTap, this.borderRadius});

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (widget.onTap == null) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final scale = !_pressed || reducedMotion(context) ? 1.0 : 0.97;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ---------------- Shimmer skeleton loaders ----------------

class SkeletonBox extends StatelessWidget {
  final double height;
  final double? width;
  final BorderRadius? borderRadius;
  const SkeletonBox({super.key, required this.height, this.width, this.borderRadius});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: isDark ? Colors.white : Colors.black,
        borderRadius: borderRadius ?? BorderRadius.circular(10),
      ),
    );
  }
}

// A handful of card-shaped placeholders shimmering while a list's first
// fetch is in flight — replaces the bare centered spinner.
class ShimmerSkeletonList extends StatelessWidget {
  final int count;
  final double itemHeight;
  const ShimmerSkeletonList({super.key, this.count = 6, this.itemHeight = 76});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final base = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06);
    final highlight = isDark ? Colors.white.withValues(alpha: 0.14) : Colors.black.withValues(alpha: 0.12);

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      period: const Duration(milliseconds: 1400),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        itemBuilder: (_, _) => Container(
          height: itemHeight,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? Colors.white : Colors.black,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const SkeletonBox(height: 40, width: 40, borderRadius: BorderRadius.all(Radius.circular(20))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    SkeletonBox(height: 12, width: 140),
                    SizedBox(height: 8),
                    SkeletonBox(height: 10, width: 90),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- Notification bell pulse ----------------

// Replays a quick scale pulse whenever `value` changes (pass the unread
// count) — a first build never pulses, only genuine increases do.
class PulseOnChange extends StatefulWidget {
  final Object value;
  final Widget child;
  const PulseOnChange({super.key, required this.value, required this.child});

  @override
  State<PulseOnChange> createState() => _PulseOnChangeState();
}

class _PulseOnChangeState extends State<PulseOnChange> {
  int _playKey = 0;

  @override
  void didUpdateWidget(covariant PulseOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) setState(() => _playKey++);
  }

  @override
  Widget build(BuildContext context) {
    if (reducedMotion(context)) return widget.child;
    return widget.child
        .animate(key: ValueKey(_playKey))
        .scale(
          begin: const Offset(1, 1),
          end: const Offset(1.35, 1.35),
          duration: 160.ms,
          curve: Curves.easeOut,
        )
        .then()
        .scale(
          begin: const Offset(1.35, 1.35),
          end: const Offset(1, 1),
          duration: 200.ms,
          curve: Curves.elasticOut,
        );
  }
}

// ---------------- "Nothing is stuck" reward moment ----------------

// A calm breathing glow behind a checkmark that draws itself in once. This
// is the emotional payoff of the Stuck screen — deliberately slower and
// softer than the rest of the app's motion.
class BreathingCheck extends StatelessWidget {
  final double size;
  const BreathingCheck({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF6FDB9C)
        : const Color(0xFF1E7D4D);
    final still = reducedMotion(context);

    final glow = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
        ),
      ),
    );

    final check = Icon(Icons.check_rounded, size: size * 0.46, color: color);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          still
              ? glow
              : glow
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(begin: 0.88, end: 1.08, duration: 1900.ms, curve: Curves.easeInOut)
                  .fadeIn(duration: 900.ms),
          Container(
            width: size * 0.62,
            height: size * 0.62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
            ),
          ),
          still
              ? check
              : check
                  .animate()
                  .scale(
                    begin: const Offset(0.4, 0.4),
                    end: const Offset(1, 1),
                    duration: 450.ms,
                    curve: Curves.elasticOut,
                    delay: 150.ms,
                  )
                  .fadeIn(duration: 250.ms, delay: 150.ms),
        ],
      ),
    );
  }
}

// ---------------- Task-done confirmation ----------------

// Shows a brief checkmark-burst overlay, then invokes onFinished (the real
// mark-done + list refresh) — the confirmation plays whether the network
// call is instant or takes a beat, so the celebration never feels delayed.
Future<void> playDoneConfirmation(BuildContext context, {required VoidCallback onFinished}) async {
  if (reducedMotion(context)) {
    onFinished();
    return;
  }
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => Center(
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
        )
            .animate()
            .scale(
              begin: const Offset(0.3, 0.3),
              end: const Offset(1, 1),
              duration: 260.ms,
              curve: Curves.elasticOut,
            )
            .fadeIn(duration: 120.ms)
            .then(delay: 320.ms)
            .fadeOut(duration: 220.ms)
            .scaleXY(end: 1.15, duration: 220.ms),
      ),
    ),
  );
  overlay.insert(entry);
  onFinished();
  await Future.delayed(const Duration(milliseconds: 780));
  entry.remove();
}

// ---------------- Order-finished celebration ----------------

// A slightly bigger moment than the plain done-confirmation: a ring of
// small dots bursts outward around a flag icon. Reserved for "this order
// just finished its entire flow," not every single stage completion.
Future<void> playCelebration(BuildContext context, {required VoidCallback onFinished}) async {
  if (reducedMotion(context)) {
    onFinished();
    return;
  }
  final overlay = Overlay.of(context);
  final scheme = Theme.of(context).colorScheme;
  final semantic = AppColors.of(context);
  final particleColors = [scheme.primary, scheme.tertiary, semantic.success, semantic.info];

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => Center(
      child: IgnorePointer(
        child: SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 10; i++)
                Builder(builder: (context) {
                  final angle = (2 * math.pi / 10) * i;
                  final dx = 70 * math.cos(angle);
                  final dy = 70 * math.sin(angle);
                  return Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: particleColors[i % particleColors.length],
                      shape: BoxShape.circle,
                    ),
                  )
                      .animate()
                      .move(begin: Offset.zero, end: Offset(dx, dy), duration: 520.ms, curve: Curves.easeOutCubic)
                      .fadeIn(duration: 120.ms)
                      .then(delay: 260.ms)
                      .fadeOut(duration: 260.ms);
                }),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                child: const Icon(Icons.flag_rounded, color: Colors.white, size: 42),
              )
                  .animate()
                  .scale(
                    begin: const Offset(0.3, 0.3),
                    end: const Offset(1, 1),
                    duration: 300.ms,
                    curve: Curves.elasticOut,
                  )
                  .fadeIn(duration: 140.ms)
                  .then(delay: 420.ms)
                  .fadeOut(duration: 260.ms)
                  .scaleXY(end: 1.15, duration: 260.ms),
            ],
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  onFinished();
  await Future.delayed(const Duration(milliseconds: 950));
  entry.remove();
}
