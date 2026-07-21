import 'package:flutter/material.dart';
import '../l10n/gen/app_localizations.dart';

// Small "How is this calculated?" info button — shared by the order-start
// form, Settings, Flow Analytics and the per-order journey so the Cost of
// Delay explanation stays identical (and bilingual) everywhere it appears.
class CostOfDelayInfoButton extends StatelessWidget {
  final double iconSize;

  const CostOfDelayInfoButton({super.key, this.iconSize = 18});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      icon: Icon(Icons.info_outline, size: iconSize),
      tooltip: l10n.costOfDelayTooltipTitle,
      visualDensity: VisualDensity.compact,
      onPressed: () => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(l10n.costOfDelayTooltipTitle),
          content: Text(l10n.costOfDelayTooltipBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.done),
            ),
          ],
        ),
      ),
    );
  }
}

// "set a delay cost to see ₹" — never a fake number. Shared formatter for
// a nullable ₹ amount produced by the backend's Cost of Delay logic.
String formatRupeesOrPrompt(num? value, {String prompt = 'Set a delay cost to see ₹'}) {
  if (value == null) return prompt;
  return '₹${value.toStringAsFixed(0)}';
}
