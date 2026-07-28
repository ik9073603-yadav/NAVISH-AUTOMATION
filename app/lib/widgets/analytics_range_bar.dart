import 'package:flutter/material.dart';
import '../l10n/gen/app_localizations.dart';

enum AnalyticsRangePreset { today, week, month, custom }

extension AnalyticsRangePresetX on AnalyticsRangePreset {
  String label(AppLocalizations l10n) {
    switch (this) {
      case AnalyticsRangePreset.today:
        return l10n.todayPreset;
      case AnalyticsRangePreset.week:
        return l10n.thisWeekPreset;
      case AnalyticsRangePreset.month:
        return l10n.thisMonthPreset;
      case AnalyticsRangePreset.custom:
        return l10n.customRangePreset;
    }
  }
}

// Shared Today/Week/Month/Custom date-range selector for every Analytics
// screen (hub summary + all four detail screens) — one implementation so
// they all behave identically instead of five near-duplicate widgets.
class AnalyticsRangeBar extends StatelessWidget {
  final AnalyticsRangePreset preset;
  final DateTime customFrom;
  final DateTime customTo;
  final ValueChanged<AnalyticsRangePreset> onPresetChanged;
  final ValueChanged<DateTimeRange> onCustomRangePicked;

  const AnalyticsRangeBar({
    super.key,
    required this.preset,
    required this.customFrom,
    required this.customTo,
    required this.onPresetChanged,
    required this.onCustomRangePicked,
  });

  // Resolves a preset (or the caller's stored custom bounds) to concrete
  // from/to instants. Shared so every screen computes the same range for
  // the same preset.
  static (DateTime, DateTime) rangeFor(
    AnalyticsRangePreset preset,
    DateTime customFrom,
    DateTime customTo,
  ) {
    final now = DateTime.now();
    switch (preset) {
      case AnalyticsRangePreset.today:
        return (DateTime(now.year, now.month, now.day), now);
      case AnalyticsRangePreset.week:
        return (now.subtract(const Duration(days: 7)), now);
      case AnalyticsRangePreset.month:
        return (DateTime(now.year, now.month, 1), now);
      case AnalyticsRangePreset.custom:
        return (customFrom, customTo);
    }
  }

  Future<void> _pickCustom(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: customFrom, end: customTo),
    );
    if (picked == null) return;
    onCustomRangePicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<AnalyticsRangePreset>(
          segments: [
            for (final p in AnalyticsRangePreset.values) ButtonSegment(value: p, label: Text(p.label(l10n))),
          ],
          selected: {preset},
          onSelectionChanged: (s) {
            if (s.first == AnalyticsRangePreset.custom) {
              _pickCustom(context);
            } else {
              onPresetChanged(s.first);
            }
          },
        ),
        if (preset == AnalyticsRangePreset.custom)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${customFrom.toLocal().toString().split(' ')[0]} → ${customTo.toLocal().toString().split(' ')[0]}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
