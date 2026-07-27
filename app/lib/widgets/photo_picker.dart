import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

// Shared pick -> crop -> compress pipeline for both the profile photo and
// the company logo pickers. Crops to a square (like WhatsApp/Instagram),
// then compresses/downscales via image_cropper's own export settings
// (max 1024px, JPEG q85) so neither the upload nor later loads are ever
// slowed down by a full-resolution original.
//
// The picker call is deliberately inside the try/catch by the caller's
// convention elsewhere in this app — this function lets pick/crop
// exceptions propagate rather than swallowing them, so callers keep that
// same pattern (a denied gallery permission must surface an error, not
// fail silently).
//
// Returns null if the user cancels at either the picker or the crop step.
Future<Uint8List?> pickAndCropSquareImage(BuildContext context, {required String toolbarTitle}) async {
  final picker = ImagePicker();
  final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
  if (file == null) return null;

  if (!context.mounted) return null;
  final scheme = Theme.of(context).colorScheme;
  // image_cropper's web dialog defaults to a 500x500 cropper area, which
  // overflows its own dialog chrome (header/actions/footer) on any viewport
  // under ~750px tall — including most phone-sized browser windows. Size it
  // off the actual viewport so the dialog always fits.
  final webCropSize = (MediaQuery.sizeOf(context).shortestSide - 120)
      .clamp(200.0, 300.0)
      .toInt();

  final cropped = await ImageCropper().cropImage(
    sourcePath: file.path,
    aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: 85,
    maxWidth: 1024,
    maxHeight: 1024,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: toolbarTitle,
        toolbarColor: scheme.surface,
        toolbarWidgetColor: scheme.onSurface,
        activeControlsWidgetColor: scheme.primary,
        backgroundColor: scheme.surface,
        initAspectRatio: CropAspectRatioPreset.square,
        lockAspectRatio: true,
      ),
      IOSUiSettings(
        title: toolbarTitle,
        aspectRatioLockEnabled: true,
        resetAspectRatioEnabled: false,
      ),
      WebUiSettings(
        context: context,
        size: CropperSize(width: webCropSize, height: webCropSize),
      ),
    ],
  );
  if (cropped == null) return null;

  return cropped.readAsBytes();
}
