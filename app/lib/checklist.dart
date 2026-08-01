import 'package:flutter/material.dart';
import 'api.dart';
import 'filters.dart';
import 'template_setup.dart';
import 'responsive.dart';
import 'theme/app_theme.dart';
import 'widgets/motion.dart';
import 'l10n/gen/app_localizations.dart';

// Short weekday chip labels — same l10n keys and Wrap/FilterChip pattern as
// the org working-days picker in settings.dart.
Map<int, String> _weekdayLabels(AppLocalizations l10n) => {
      1: l10n.weekdayMon,
      2: l10n.weekdayTue,
      3: l10n.weekdayWed,
      4: l10n.weekdayThu,
      5: l10n.weekdayFri,
      6: l10n.weekdaySat,
      7: l10n.weekdaySun,
    };

class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key});
  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  List<dynamic> _rules = [];
  List<dynamic> _users = [];
  bool _loading = true;
  String _status = 'ACTIVE';
  DateRangePreset _datePreset = DateRangePreset.all;
  String? _assigneeId;
  int _loadRequestId = 0;
  bool _aiConfigured = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Best-effort — if this fails, the AI setup option just doesn't show;
    // no need to block the screen or error-toast over it.
    Api.aiConfigStatus().then((s) {
      if (mounted) setState(() => _aiConfigured = s['configured'] == true);
    }).catchError((_) {});
  }

  Future<void> _load() async {
    final requestId = ++_loadRequestId;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        Api.checklists(status: _status, from: _datePreset.from, assigneeId: _assigneeId),
        Api.users(),
      ]);
      if (!mounted || requestId != _loadRequestId) return;
      setState(() { _rules = results[0]; _users = results[1]; });
    } catch (e) {
      if (mounted && requestId == _loadRequestId) {
        showApiError(context, e);
      }
    } finally {
      if (mounted && requestId == _loadRequestId) setState(() => _loading = false);
    }
  }

  Future<void> _newChecklist() async {
    final l10n = AppLocalizations.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('New checklist'),
        children: [
          if (_aiConfigured)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'ai'),
              child: Row(children: [
                const Icon(Icons.auto_awesome, size: 18),
                const SizedBox(width: 8),
                Text(l10n.aiSetupOption),
              ]),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'template'),
            child: const Text('Start from template'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'blank'),
            child: const Text('Start from scratch'),
          ),
        ],
      ),
    );
    if (choice == null) return;

    if (choice == 'blank') {
      final ok = await showAdaptiveSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const _NewChecklistSheet(),
      );
      if (ok == true) _load();
      return;
    }

    if (choice == 'ai') {
      final created = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => const _AiDescribeChecklistScreen()));
      if (created == true) _load();
      return;
    }

    final applied = await pickAndApplyTemplate(context, 'CHECKLIST');
    if (applied == null || !mounted) return;
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => TemplateAssignChecklistScreen(ruleId: applied['ruleId'] as String)),
    );
    if (done == true) _load();
  }

  String _schedule(Map r) {
    const days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    switch (r['recurrence']) {
      case 'DAILY':
        return 'Every day at ${r['timeOfDay']}';
      case 'WEEKLY':
        final weekdays = ((r['weekdays'] as List?) ?? const [1]).cast<int>();
        final sorted = [...weekdays]..sort();
        String label;
        if (sorted.length == 7) {
          label = 'day';
        } else if (const [1, 2, 3, 4, 5].every(sorted.contains) && sorted.length == 5) {
          label = 'weekday';
        } else {
          label = sorted.map((d) => days[d]).join(', ');
        }
        return 'Every $label at ${r['timeOfDay']}';
      case 'MONTHLY':
        return 'Day ${r['dayOfMonth'] ?? 1} of month at ${r['timeOfDay']}';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: ShimmerSkeletonList());

    return Scaffold(
      body: Column(
        children: [
          FilterBar(
            status: _status,
            onStatusChanged: (s) {
              setState(() => _status = s);
              _load();
            },
            doneLabel: 'Inactive',
            datePreset: _datePreset,
            onDatePresetChanged: (p) {
              setState(() => _datePreset = p);
              _load();
            },
            users: _users,
            assigneeId: _assigneeId,
            onAssigneeChanged: (a) {
              setState(() => _assigneeId = a);
              _load();
            },
          ),
          Expanded(
            child: _rules.isEmpty
                ? Center(
                    child: Text(
                      _status == 'ACTIVE'
                          ? 'No checklists yet.\nCreate one 👇'
                          : 'No inactive checklists',
                      textAlign: TextAlign.center,
                    ),
                  )
                : _rulesList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newChecklist,
        icon: const Icon(Icons.add),
        label: const Text('New checklist'),
      ),
    );
  }

  Widget _rulesList() {
    return RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _rules.length,
                itemBuilder: (_, i) {
                  final r = _rules[i];
                  final active = r['active'] == true;
                  final semantic = AppColors.of(context);
                  return StaggeredListItem(
                    index: i,
                    child: Card(
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: active ? semantic.successContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.event_repeat, size: 20,
                              color: active ? semantic.onSuccessContainer : Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        title: Text(r['title'],
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: active ? null : Theme.of(context).colorScheme.onSurfaceVariant)),
                        subtitle: Text('${r['assigneeName']} · ${_schedule(r)}'),
                        trailing: Switch(
                          value: active,
                          onChanged: (_) async {
                            await Api.toggleChecklist(r['id']);
                            _load();
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
  }
}

class _NewChecklistSheet extends StatefulWidget {
  const _NewChecklistSheet();
  @override
  State<_NewChecklistSheet> createState() => _NewChecklistSheetState();
}

class _NewChecklistSheetState extends State<_NewChecklistSheet> {
  final _title = TextEditingController();
  List<dynamic> _users = [];
  String? _assignee;
  String _recurrence = 'DAILY';
  final Set<int> _weekdays = {1};
  int _dayOfMonth = 1;
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Api.users().then((u) {
      if (!mounted) return;
      setState(() {
        _users = u;
        if (u.isNotEmpty) _assignee = u.first['id'];
      });
    }).catchError((e) {
      if (mounted) showApiError(context, e);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String get _timeStr =>
      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (_title.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter what must be done (2+ characters)')),
      );
      return;
    }
    if (_assignee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select who does it')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await Api.createChecklist(
        title: _title.text.trim(),
        assigneeId: _assignee!,
        recurrence: _recurrence,
        timeOfDay: _timeStr,
        weekdays: _recurrence == 'WEEKLY' ? (_weekdays.toList()..sort()) : null,
        dayOfMonth: _recurrence == 'MONTHLY' ? _dayOfMonth : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showApiError(context, e);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('New recurring checklist', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text('Fires automatically. Nobody has to remember.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                  labelText: 'What must be done?', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _assignee,
              decoration: const InputDecoration(
                  labelText: 'Who does it?', border: OutlineInputBorder()),
              items: _users
                  .map((u) => DropdownMenuItem<String>(
                      value: u['id'] as String, child: Text('${u['name']}')))
                  .toList(),
              onChanged: (v) => setState(() => _assignee = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _recurrence,
              decoration: const InputDecoration(
                  labelText: 'How often?', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'DAILY', child: Text('Every day')),
                DropdownMenuItem(value: 'WEEKLY', child: Text('Every week')),
                DropdownMenuItem(value: 'MONTHLY', child: Text('Every month')),
              ],
              onChanged: (v) => setState(() => _recurrence = v!),
            ),
            if (_recurrence == 'WEEKLY') ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(l10n.checklistWeekdaysLabel, style: Theme.of(context).textTheme.labelLarge),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _weekdayLabels(l10n).entries.map((e) {
                  final selected = _weekdays.contains(e.key);
                  return FilterChip(
                    label: Text(e.value),
                    selected: selected,
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _weekdays.add(e.key);
                        } else if (_weekdays.length > 1) {
                          _weekdays.remove(e.key);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ],
            if (_recurrence == 'MONTHLY') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _dayOfMonth,
                decoration: const InputDecoration(
                    labelText: 'Day of month', border: OutlineInputBorder()),
                items: List.generate(28, (i) => i + 1)
                    .map((d) => DropdownMenuItem(value: d, child: Text('Day $d')))
                    .toList(),
                onChanged: (v) => setState(() => _dayOfMonth = v!),
              ),
            ],
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Time of day'),
              trailing: Text(_timeStr, style: Theme.of(context).textTheme.titleMedium),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _time);
                if (t != null) setState(() => _time = t);
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text(_saving ? 'Creating...' : 'Create checklist'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- AI SETUP: DESCRIBE BUSINESS/ROUTINE ----------------
// Step 1 of 2. Only reachable when the user already has an AI key
// configured (see ChecklistScreen). Uses THEIR key server-side — see
// suggestChecklistItems() in ai.service.ts; nothing here ever sees the key.
class _AiDescribeChecklistScreen extends StatefulWidget {
  const _AiDescribeChecklistScreen();
  @override
  State<_AiDescribeChecklistScreen> createState() => _AiDescribeChecklistScreenState();
}

class _AiDescribeChecklistScreenState extends State<_AiDescribeChecklistScreen> {
  final _description = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _suggest() async {
    final l10n = AppLocalizations.of(context);
    final text = _description.text.trim();
    if (text.isEmpty) {
      setState(() => _error = l10n.aiDescribeRoutineEmpty);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final items = await Api.suggestChecklistItems(text);
      if (!mounted) return;
      final created = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => _AiPreviewChecklistScreen(suggested: items)),
      );
      if (!mounted) return;
      if (created == true) {
        Navigator.pop(context, true);
        return;
      }
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiDescribeRoutineTitle)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.aiDescribeRoutineHelp,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.aiDescribeRoutineHint,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: AppColors.of(context).danger)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loading ? null : _suggest,
              icon: _loading
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(_loading ? l10n.suggestingFields : l10n.suggestChecklistAction),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- AI SETUP: EDITABLE PREVIEW ----------------
// Step 2 of 2. Nothing is created until "Create N items" is pressed — each
// edit/remove here only touches this screen's local list. One assignee is
// picked for the whole batch (matches the create-sheet flow, which also
// creates rules one at a time via the existing checklist CRUD).
class _AiPreviewChecklistScreen extends StatefulWidget {
  final List<dynamic> suggested;
  const _AiPreviewChecklistScreen({required this.suggested});
  @override
  State<_AiPreviewChecklistScreen> createState() => _AiPreviewChecklistScreenState();
}

class _AiPreviewChecklistScreenState extends State<_AiPreviewChecklistScreen> {
  late List<Map<String, dynamic>> _items;
  List<dynamic> _users = [];
  String? _assignee;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _items = widget.suggested.map((f) => Map<String, dynamic>.from(f as Map)).toList();
    Api.users().then((u) {
      if (!mounted) return;
      setState(() {
        _users = u;
        if (u.isNotEmpty) _assignee = u.first['id'] as String;
      });
    }).catchError((e) {
      if (mounted) showApiError(context, e);
    });
  }

  Future<void> _edit(int index) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ChecklistItemDialog(existing: _items[index]),
    );
    if (result != null) setState(() => _items[index] = result);
  }

  Future<void> _add() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _ChecklistItemDialog(),
    );
    if (result != null) setState(() => _items.add(result));
  }

  void _remove(int index) => setState(() => _items.removeAt(index));

  Future<void> _confirm() async {
    if (_assignee == null) return;
    setState(() => _saving = true);
    try {
      // Sequential, not parallel — matches the SKU-field AI setup, and keeps
      // failures easy to attribute to a single item.
      for (final item in _items) {
        final weekdays = (item['weekdays'] as List?)?.map((e) => (e as num).toInt()).toList();
        await Api.createChecklist(
          title: item['title'] as String,
          assigneeId: _assignee!,
          recurrence: item['recurrence'] as String,
          timeOfDay: (item['timeOfDay'] as String?) ?? '09:00',
          weekdays: item['recurrence'] == 'WEEKLY' ? weekdays : null,
          dayOfMonth: item['recurrence'] == 'MONTHLY' ? (item['dayOfMonth'] as num?)?.toInt() : null,
        );
      }
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.checklistItemsCreatedMessage(_items.length))),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showApiError(context, e);
        setState(() => _saving = false);
      }
    }
  }

  String _scheduleLabel(Map item) {
    const days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final timeOfDay = (item['timeOfDay'] as String?) ?? '09:00';
    switch (item['recurrence']) {
      case 'DAILY':
        return 'Every day at $timeOfDay';
      case 'WEEKLY':
        final weekdays = ((item['weekdays'] as List?) ?? const [1]).map((e) => (e as num).toInt()).toList()..sort();
        return 'Every ${weekdays.map((d) => days[d]).join(', ')} at $timeOfDay';
      case 'MONTHLY':
        return 'Day ${item['dayOfMonth'] ?? 1} of month at $timeOfDay';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiPreviewChecklistTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.aiPreviewHelp,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: DropdownButtonFormField<String>(
              initialValue: _assignee,
              decoration: const InputDecoration(labelText: 'Who does it?', border: OutlineInputBorder()),
              items: _users
                  .map((u) => DropdownMenuItem<String>(value: u['id'] as String, child: Text('${u['name']}')))
                  .toList(),
              onChanged: (v) => setState(() => _assignee = v),
            ),
          ),
          Expanded(
            child: _items.isEmpty
                ? Center(child: Text(l10n.aiPreviewChecklistEmpty))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      final item = _items[i];
                      return Card(
                        child: ListTile(
                          onTap: () => _edit(i),
                          title: Text(item['title'] as String),
                          subtitle: Text(_scheduleLabel(item)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _edit(i)),
                              IconButton(icon: const Icon(Icons.delete, size: 20), onPressed: () => _remove(i)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.addChecklistItem),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: (_saving || _items.isEmpty || _assignee == null) ? null : _confirm,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: Text(l10n.createNChecklistItems(_items.length)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- AI SETUP: ADD/EDIT ITEM DIALOG ----------------
class _ChecklistItemDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _ChecklistItemDialog({this.existing});
  @override
  State<_ChecklistItemDialog> createState() => _ChecklistItemDialogState();
}

class _ChecklistItemDialogState extends State<_ChecklistItemDialog> {
  final _title = TextEditingController();
  String _recurrence = 'DAILY';
  Set<int> _weekdays = {1};
  int _dayOfMonth = 1;
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _title.text = existing['title'] as String? ?? '';
      _recurrence = existing['recurrence'] as String? ?? 'DAILY';
      final wd = existing['weekdays'];
      if (wd is List && wd.isNotEmpty) _weekdays = wd.map((e) => (e as num).toInt()).toSet();
      _dayOfMonth = (existing['dayOfMonth'] as num?)?.toInt() ?? 1;
      final parts = ((existing['timeOfDay'] as String?) ?? '09:00').split(':');
      _time = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 9,
        minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
      );
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String get _timeStr =>
      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? l10n.editChecklistItem : l10n.addChecklistItem),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'What must be done?', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _recurrence,
              decoration: const InputDecoration(labelText: 'How often?', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'DAILY', child: Text('Every day')),
                DropdownMenuItem(value: 'WEEKLY', child: Text('Every week')),
                DropdownMenuItem(value: 'MONTHLY', child: Text('Every month')),
              ],
              onChanged: (v) => setState(() => _recurrence = v!),
            ),
            if (_recurrence == 'WEEKLY') ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(l10n.checklistWeekdaysLabel, style: Theme.of(context).textTheme.labelLarge),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _weekdayLabels(l10n).entries.map((e) {
                  final selected = _weekdays.contains(e.key);
                  return FilterChip(
                    label: Text(e.value),
                    selected: selected,
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _weekdays.add(e.key);
                        } else if (_weekdays.length > 1) {
                          _weekdays.remove(e.key);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ],
            if (_recurrence == 'MONTHLY') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _dayOfMonth,
                decoration: const InputDecoration(labelText: 'Day of month', border: OutlineInputBorder()),
                items: List.generate(28, (i) => i + 1)
                    .map((d) => DropdownMenuItem(value: d, child: Text('Day $d')))
                    .toList(),
                onChanged: (v) => setState(() => _dayOfMonth = v!),
              ),
            ],
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Time of day'),
              trailing: Text(_timeStr, style: Theme.of(context).textTheme.titleMedium),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _time);
                if (t != null) setState(() => _time = t);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) return;
            Navigator.pop(context, {
              'title': _title.text.trim(),
              'recurrence': _recurrence,
              if (_recurrence == 'WEEKLY') 'weekdays': (_weekdays.toList()..sort()),
              if (_recurrence == 'MONTHLY') 'dayOfMonth': _dayOfMonth,
              'timeOfDay': _timeStr,
            });
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}