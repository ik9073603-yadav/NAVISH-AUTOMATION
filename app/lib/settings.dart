import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'export_actions.dart';
import 'push.dart';
import 'reset_requests.dart';
import 'responsive.dart';
import 'theme_controller.dart';
import 'widgets/motion.dart';
import 'l10n/gen/app_localizations.dart';

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

Map<int, String> _weekdayLabels(AppLocalizations l10n) => {
      1: l10n.weekdayMon,
      2: l10n.weekdayTue,
      3: l10n.weekdayWed,
      4: l10n.weekdayThu,
      5: l10n.weekdayFri,
      6: l10n.weekdaySat,
      7: l10n.weekdaySun,
    };

// Owner-only: company profile + working hours that gate the automation
// engine's chasing, plus reset-request approvals, notification and
// appearance preferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _backingUp = false;
  bool _uploadingLogo = false;
  bool _pushEnabled = true;

  final _companyName = TextEditingController();
  final _industry = TextEditingController();
  String? _logoUrl;

  String _timezone = 'Asia/Kolkata';
  Set<int> _workingDays = {1, 2, 3, 4, 5, 6};
  TimeOfDay _shiftStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _shiftEnd = const TimeOfDay(hour: 18, minute: 0);
  List<String> _holidays = [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadPushPref();
  }

  @override
  void dispose() {
    _companyName.dispose();
    _industry.dispose();
    super.dispose();
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
        _companyName.text = s['name'] as String? ?? '';
        _industry.text = s['industry'] as String? ?? '';
        _logoUrl = s['logoUrl'] as String?;
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

  Future<void> _loadPushPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _pushEnabled = prefs.getBool('pushEnabled') ?? true);
  }

  Future<void> _togglePush(bool enabled) async {
    setState(() => _pushEnabled = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pushEnabled', enabled);
    if (enabled) {
      await PushService.registerToken();
    } else {
      await PushService.unregisterToken();
    }
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;

    setState(() => _uploadingLogo = true);
    try {
      final Uint8List bytes = await file.readAsBytes();
      final url = await Api.uploadImage(bytes, file.name);
      await Api.updateSettings(logoUrl: url);
      if (mounted) setState(() => _logoUrl = url);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Api.updateSettings(
        name: _companyName.text.trim(),
        industry: _industry.text.trim(),
        timezone: _timezone,
        workingDays: _workingDays.toList()..sort(),
        shiftStart: _fmtTime(_shiftStart),
        shiftEnd: _fmtTime(_shiftEnd),
        holidays: _holidays,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).settingsSaved)));
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
      return const Scaffold(body: ShimmerSkeletonList());
    }
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.companySettingsTitle)),
      body: MaxWidthCenter(
        maxWidth: 760,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionLabel(l10n.companyProfile),
            Center(child: _logoPicker()),
            const SizedBox(height: 16),
            TextField(
              controller: _companyName,
              decoration: InputDecoration(labelText: l10n.companyNameLabel, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _industry,
              decoration: InputDecoration(
                labelText: l10n.industryLabel, hintText: l10n.industryHint, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 28),
            _sectionLabel(l10n.timezone),
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
            const SizedBox(height: 28),
            _sectionLabel(l10n.workingDays),
            Wrap(
              spacing: 8,
              children: _weekdayLabels(l10n).entries.map((e) {
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
            const SizedBox(height: 28),
            _sectionLabel(l10n.shiftHours),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickShiftStart,
                    child: Text(l10n.startTime(_fmtTime(_shiftStart))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickShiftEnd,
                    child: Text(l10n.endTime(_fmtTime(_shiftEnd))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _sectionLabel(l10n.holidays),
                TextButton.icon(
                  onPressed: _addHoliday,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.add),
                ),
              ],
            ),
            if (_holidays.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l10n.noHolidaysAdded, style: const TextStyle(color: Colors.grey)),
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
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _saving
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(l10n.saveSettings),
            ),
            const SizedBox(height: 32),
            _sectionLabel(l10n.requests),
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock_reset),
                title: Text(l10n.navPasswordResetRequests),
                subtitle: Text(l10n.passwordResetRequestsSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context, sharedAxisRoute(const ResetRequestsScreen())),
              ),
            ),
            const SizedBox(height: 28),
            _sectionLabel(l10n.notifications),
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: Text(l10n.pushNotificationsTitle),
                subtitle: Text(l10n.pushNotificationsSubtitle),
                value: _pushEnabled,
                onChanged: _togglePush,
              ),
            ),
            const SizedBox(height: 28),
            _sectionLabel(l10n.appearance),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeController.mode,
              builder: (_, mode, __) => SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode), label: Text(l10n.light)),
                  ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode), label: Text(l10n.dark)),
                  ButtonSegment(value: ThemeMode.system, icon: const Icon(Icons.brightness_auto), label: Text(l10n.system)),
                ],
                selected: {mode},
                onSelectionChanged: (s) => ThemeController.set(s.first),
              ),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 8),
            _sectionLabel(l10n.dataSection),
            Text(
              l10n.dataExportDescription,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _backingUp ? null : _downloadBackup,
              icon: _backingUp
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.archive_outlined),
              label: Text(_backingUp ? l10n.preparingBackup : l10n.downloadFullBackup),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );

  Widget _logoPicker() {
    return Stack(
      children: [
        CircleAvatar(
          radius: 40,
          backgroundImage: _logoUrl != null ? NetworkImage(_logoUrl!) : null,
          child: _logoUrl == null ? const Icon(Icons.business, size: 32) : null,
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: InkWell(
            onTap: _uploadingLogo ? null : _pickLogo,
            borderRadius: BorderRadius.circular(20),
            child: CircleAvatar(
              radius: 15,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: _uploadingLogo
                  ? const SizedBox(
                      height: 12, width: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.camera_alt, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
