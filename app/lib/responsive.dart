import 'package:flutter/material.dart';

// Breakpoints: compact < 600 (phone), medium 600-1024 (tablet), expanded > 1024
// (desktop/wide web). Anything reading window width for a layout decision
// should go through these instead of hardcoding a number.
class Breakpoints {
  static const compact = 600.0;
  static const expanded = 1024.0;
}

enum ScreenSize { compact, medium, expanded }

ScreenSize screenSizeOf(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < Breakpoints.compact) return ScreenSize.compact;
  if (w < Breakpoints.expanded) return ScreenSize.medium;
  return ScreenSize.expanded;
}

bool isCompact(BuildContext context) => screenSizeOf(context) == ScreenSize.compact;
bool isExpanded(BuildContext context) => screenSizeOf(context) == ScreenSize.expanded;

// Wide screens shouldn't stretch list/detail content edge-to-edge — center
// it in a capped column instead, like a reading-width column in a browser.
class MaxWidthCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const MaxWidthCenter({super.key, required this.child, this.maxWidth = 1000});

  @override
  Widget build(BuildContext context) {
    if (isCompact(context)) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

// Same builder, different presentation: a bottom sheet on phone, a centered
// dialog on tablet/desktop where a screen-height sheet would look stranded
// against a mostly-empty backdrop.
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  if (isCompact(context)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      builder: builder,
    );
  }
  // Sized relative to the real viewport, not a fixed constant — widgets like
  // DraggableScrollableSheet size their fixed (non-scrolling) content against
  // whatever height they're given, and a too-small fixed box makes that
  // content overflow on short windows.
  final screenHeight = MediaQuery.sizeOf(context).height;
  return showDialog<T>(
    context: context,
    builder: (ctx) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: screenHeight * 0.88),
        child: Material(
          type: MaterialType.transparency,
          child: builder(ctx),
        ),
      ),
    ),
  );
}
