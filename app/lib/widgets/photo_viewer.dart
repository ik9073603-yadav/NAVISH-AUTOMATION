import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';

// WhatsApp/Instagram-style full-screen image viewer: pinch-to-zoom, tap to
// dismiss, with a Hero transition from whatever avatar opened it. Tap
// dismissal is wired through PhotoView's own onTapUp (not a wrapping
// GestureDetector) so it never fights with PhotoView's internal pan/zoom
// gesture recognizers.
class FullScreenPhotoViewer extends StatelessWidget {
  final String imageUrl;
  final String heroTag;
  const FullScreenPhotoViewer({super.key, required this.imageUrl, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: PhotoView(
        imageProvider: CachedNetworkImageProvider(imageUrl),
        heroAttributes: PhotoViewHeroAttributes(tag: heroTag),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 3,
        onTapUp: (context, details, controllerValue) => Navigator.of(context).pop(),
        loadingBuilder: (context, event) => const Center(
          child: CircularProgressIndicator(color: Colors.white54),
        ),
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 64),
        ),
      ),
    );
  }
}
