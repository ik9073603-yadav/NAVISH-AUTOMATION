import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// Writes exported bytes to a temp file and opens the platform share sheet —
// the user picks where it lands (Drive, WhatsApp, Files, email...).
Future<void> shareExportedFile(Uint8List bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], fileNameOverrides: [filename]));
}
