import 'package:flutter/material.dart';

// Pull, not push: default view is ACTIVE only; historical data is one filter away.
enum DateRangePreset { today, thisWeek, thisMonth, all }

extension DateRangePresetX on DateRangePreset {
  String get label {
    switch (this) {
      case DateRangePreset.today:
        return 'Today';
      case DateRangePreset.thisWeek:
        return 'This week';
      case DateRangePreset.thisMonth:
        return 'This month';
      case DateRangePreset.all:
        return 'All time';
    }
  }

  DateTime? get from {
    final now = DateTime.now();
    switch (this) {
      case DateRangePreset.today:
        return DateTime(now.year, now.month, now.day);
      case DateRangePreset.thisWeek:
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        return DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
      case DateRangePreset.thisMonth:
        return DateTime(now.year, now.month, 1);
      case DateRangePreset.all:
        return null;
    }
  }
}

// Active/Done segmented control + date range + optional assignee filter.
// Reused across the task list, checklists, and the FMS board.
class FilterBar extends StatelessWidget {
  final String status; // 'ACTIVE' | 'DONE'
  final ValueChanged<String> onStatusChanged;
  final String activeLabel;
  final String doneLabel;
  final DateRangePreset datePreset;
  final ValueChanged<DateRangePreset> onDatePresetChanged;
  final List<dynamic>? users;
  final String? assigneeId;
  final ValueChanged<String?>? onAssigneeChanged;

  const FilterBar({
    super.key,
    required this.status,
    required this.onStatusChanged,
    this.activeLabel = 'Active',
    this.doneLabel = 'Done',
    required this.datePreset,
    required this.onDatePresetChanged,
    this.users,
    this.assigneeId,
    this.onAssigneeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'ACTIVE', label: Text(activeLabel)),
              ButtonSegment(value: 'DONE', label: Text(doneLabel)),
            ],
            selected: {status},
            onSelectionChanged: (s) => onStatusChanged(s.first),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<DateRangePreset>(
                  initialValue: datePreset,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Date range',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: DateRangePreset.values
                      .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onDatePresetChanged(v);
                  },
                ),
              ),
              if (users != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: assigneeId,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Assignee',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Everyone')),
                      ...users!.map((u) => DropdownMenuItem<String?>(
                            value: u['id'] as String,
                            child: Text('${u['name']}'),
                          )),
                    ],
                    onChanged: onAssigneeChanged,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
