import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'photo_viewer.dart';

// Shared network avatar for anywhere a profile photo / company logo shows:
// - cached (an already-seen image reappears instantly, no re-fetch)
// - shimmer placeholder while loading
// - one automatic retry on failure (covers a Render cold-start or a
//   transient Supabase hiccup) before falling back to initials/icon —
//   never a raw "failed to load" error surfaced to the user
// - tap opens a full-screen viewer with a Hero transition, when a photo is set
class AppAvatar extends StatefulWidget {
  final String? imageUrl;
  final double radius;
  final String heroTag;
  final String fallbackText;
  final IconData? fallbackIcon;
  final bool enableViewer;

  const AppAvatar({
    super.key,
    required this.imageUrl,
    required this.radius,
    required this.heroTag,
    this.fallbackText = '',
    this.fallbackIcon,
    this.enableViewer = true,
  });

  @override
  State<AppAvatar> createState() => _AppAvatarState();
}

class _AppAvatarState extends State<AppAvatar> {
  int _retryToken = 0;
  bool _retried = false;

  @override
  void didUpdateWidget(covariant AppAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _retried = false;
      _retryToken = 0;
    }
  }

  void _scheduleRetry(String url) {
    if (_retried) return;
    _retried = true;
    CachedNetworkImage.evictFromCache(url);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _retryToken++);
    });
  }

  Widget _fallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
      child: widget.fallbackIcon != null
          ? Icon(widget.fallbackIcon, size: widget.radius, color: scheme.onPrimaryContainer)
          : Text(
              widget.fallbackText.isNotEmpty ? widget.fallbackText[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: widget.radius * 0.7,
                fontWeight: FontWeight.w600,
                color: scheme.onPrimaryContainer,
              ),
            ),
    );
  }

  Widget _shimmerPlaceholder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06));
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl;
    final size = widget.radius * 2;

    Widget content;
    if (url == null || url.isEmpty) {
      content = _fallback(context);
    } else {
      content = ClipOval(
        child: CachedNetworkImage(
          key: ValueKey('$url#$_retryToken'),
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 200),
          placeholder: (context, _) => _shimmerPlaceholder(context),
          errorWidget: (context, failedUrl, error) {
            // Schedule the retry as a side effect, but render the fallback
            // immediately — never leave a broken-image error on screen.
            WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleRetry(failedUrl));
            return _fallback(context);
          },
        ),
      );
    }

    final sized = SizedBox(width: size, height: size, child: content);

    if (!widget.enableViewer || url == null || url.isEmpty) {
      return sized;
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black,
          pageBuilder: (_, _, _) => FullScreenPhotoViewer(imageUrl: url, heroTag: widget.heroTag),
        ),
      ),
      child: Hero(tag: widget.heroTag, child: sized),
    );
  }
}
