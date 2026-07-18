import 'package:flutter/material.dart';
import 'api.dart';
import 'filters.dart';
import 'template_setup.dart';
import 'responsive.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rules = await Api.checklists(
        status: _status,
        from: _datePreset.from,
        assigneeId: _assigneeId,
      );
      final users = await Api.users();
      setState(() { _rules = rules; _users = users; });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newChecklist() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('New checklist'),
        children: [
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
        return 'Every ${days[r['weekday'] ?? 1]} at ${r['timeOfDay']}';
      case 'MONTHLY':
        return 'Day ${r['dayOfMonth'] ?? 1} of month at ${r['timeOfDay']}';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

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
                  return Card(
                    child: ListTile(
                      leading: Icon(Icons.event_repeat,
                          color: active ? Colors.green : Colors.grey),
                      title: Text(r['title'],
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: active ? null : Colors.grey)),
                      subtitle: Text('${r['assigneeName']} · ${_schedule(r)}'),
                      trailing: Switch(
                        value: active,
                        onChanged: (_) async {
                          await Api.toggleChecklist(r['id']);
                          _load();
                        },
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
  int _weekday = 1;
  int _dayOfMonth = 1;
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Api.users().then((u) => setState(() {
          _users = u;
          if (u.isNotEmpty) _assignee = u.first['id'];
        }));
  }

  String get _timeStr =>
      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (_title.text.trim().length < 2 || _assignee == null) return;
    setState(() => _saving = true);
    try {
      await Api.createChecklist(
        title: _title.text.trim(),
        assigneeId: _assignee!,
        recurrence: _recurrence,
        timeOfDay: _timeStr,
        weekday: _recurrence == 'WEEKLY' ? _weekday : null,
        dayOfMonth: _recurrence == 'MONTHLY' ? _dayOfMonth : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            const Text('New recurring checklist',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Fires automatically. Nobody has to remember.',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
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
              DropdownButtonFormField<int>(
                initialValue: _weekday,
                decoration: const InputDecoration(
                    labelText: 'Which day?', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Monday')),
                  DropdownMenuItem(value: 2, child: Text('Tuesday')),
                  DropdownMenuItem(value: 3, child: Text('Wednesday')),
                  DropdownMenuItem(value: 4, child: Text('Thursday')),
                  DropdownMenuItem(value: 5, child: Text('Friday')),
                  DropdownMenuItem(value: 6, child: Text('Saturday')),
                  DropdownMenuItem(value: 7, child: Text('Sunday')),
                ],
                onChanged: (v) => setState(() => _weekday = v!),
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
              trailing: Text(_timeStr,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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