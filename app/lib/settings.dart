import 'package:flutter/material.dart';
import 'api.dart';
import 'export_actions.dart';

const _commonTimezones = [
  'Asia/Kolkata',
  'Asia/Dubai',
  'Asia/Karachi',
  'Asia/Dhaka',
  'Asia/Singapore',
  'UTC',
  'Europe/London',
  'America/New_York',
];

const _weekdayLabels = {
  1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun',
};

// Owner-only: org working hours that gate the automation engine's chasing.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _backingUp = false;
  String _timezone = 'Asia/Kolkata';
  Set<int> _workingDays = {1, 2, 3, 4, 5, 6};
  TimeOfDay _shiftStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _shiftEnd = const TimeOfDay(hour: 18, minute: 0);
  List<String> _holidays = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay _parseTime(String s) {
    final parts = s.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await Api.getSettings();
      setState(() {
        _timezone = s['timezone'] as String? ?? 'Asia/Kolkata';
        _workingDays = ((s['workingDays'] as List?) ?? [1, 2, 3, 4, 5, 6])
            .map((e) => e as int)
            .toSet();
        _shiftStart = _parseTime(s['shiftStart'] as String? ?? '09:00');
        _shiftEnd = _parseTime(s['shiftEnd'] as String? ?? '18:00');
        _holidays = ((s['holidays'] as List?) ?? []).map((e) => e as String).toList()..sort();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Api.updateSettings(
        timezone: _timezone,
        workingDays: _workingDays.toList()..sort(),
        shiftStart: _fmtTime(_shiftStart),
        shiftEnd: _fmtTime(_shiftEnd),
        holidays: _holidays,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Settings saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _downloadBackup() async {
    setState(() => _backingUp = true);
    try {
      final (bytes, filename) = await Api.exportBackup();
      await shareExportedFile(bytes, filename);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  Future<void> _pickShiftStart() async {
    final picked = await showTimePicker(context: context, initialTime: _shiftStart);
    if (picked != null) setState(() => _shiftStart = picked);
  }

  Future<void> _pickShiftEnd() async {
    final picked = await showTimePicker(context: context, initialTime: _shiftEnd);
    if (picked != null) setState(() => _shiftEnd = picked);
  }

  Future<void> _addHoliday() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked == null) return;
    final iso =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    if (!_holidays.contains(iso)) {
      setState(() {
        _holidays.add(iso);
        _holidays.sort();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Company settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Timezone', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _commonTimezones.contains(_timezone) ? _timezone : null,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            hint: Text(_timezone),
            items: _commonTimezones
                .map((tz) => DropdownMenuItem(value: tz, child: Text(tz)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _timezone = v);
            },
          ),
          const SizedBox(height: 24),
          const Text('Working days', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _weekdayLabels.entries.map((e) {
              final selected = _workingDays.contains(e.key);
              return FilterChip(
                label: Text(e.value),
                selected: selected,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _workingDays.add(e.key);
                    } else {
                      _workingDays.remove(e.key);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          const Text('Shift hours', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _pickShiftStart,
                  child: Text('Start: ${_fmtTime(_shiftStart)}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _pickShiftEnd,
                  child: Text('End: ${_fmtTime(_shiftEnd)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Holidays', style: TextStyle(fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: _addHoliday,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
          if (_holidays.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No holidays added', style: TextStyle(color: Colors.grey)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _holidays.map((h) {
                return Chip(
                  label: Text(h),
                  onDeleted: () => setState(() => _holidays.remove(h)),
                );
              }).toList(),
            ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: _saving
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save settings'),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Data', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'A full export of your company\'s data — users, tasks, checklists, flow monitoring orders, inventory.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _backingUp ? null : _downloadBackup,
            icon: _backingUp
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.archive_outlined),
            label: Text(_backingUp ? 'Preparing backup...' : 'Download full company backup'),
          ),
        ],
      ),
    );
  }
}
