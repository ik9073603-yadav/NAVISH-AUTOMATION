import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'l10n/gen/app_localizations.dart';

// Full-screen camera scan — pops with the scanned code's raw text, or null
// if the user backs out. Used by the inventory SKU lookup flow.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});
  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (value == null || value.isEmpty) return;
    _handled = true;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanBarcodeTitle)),
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
        errorBuilder: (context, error, child) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography_outlined, size: 48),
                const SizedBox(height: 12),
                Text(l10n.cameraUnavailable, textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(
                  error.errorDetails?.message ?? error.errorCode.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
