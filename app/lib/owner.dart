import 'package:flutter/material.dart';
import 'api.dart';
import 'filters.dart';

class OwnerScreen extends StatefulWidget {
  const OwnerScreen({super.key});
  @override
  State<OwnerScreen> createState() => _OwnerScreenState();
}

class _OwnerScreenState extends State<OwnerScreen> {
  List<dynamic> _tasks = [];
  List<dynamic> _stats = [];
  List<dynamic> _users = [];
  bool _loading = true;
  int _tab = 0;
  String _taskStatus = 'ACTIVE';
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
      final tasks = await Api.allTasks(
        status: _taskStatus,
        from: _datePreset.from,
        assigneeId: _assigneeId,
      );
      final stats = await Api.stats();
      final users = await Api.users();
      setState(() { _tasks = tasks; _stats = stats; _users = users; });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: _tab == 0 ? _tasksView() : _teamView(),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: _openAssign,
              icon: const Icon(Icons.add),
              label: const Text('Assign task'),
            )
          : FloatingActionButton.extended(
              onPressed: _openAddUser,
              icon: const Icon(Icons.person_add),
              label: const Text('Add person'),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'All tasks'),
          NavigationDestination(icon: Icon(Icons.groups), label: 'Team'),
        ],
      ),
    );
  }

  Widget _tasksView() {
    return Column(
      children: [
        FilterBar(
          status: _taskStatus,
          onStatusChanged: (s) {
            setState(() => _taskStatus = s);
            _load();
          },
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
          child: _tasks.isEmpty
              ? const Center(child: Text('No tasks yet. Assign one 👇'))
              : _tasksList(),
        ),
      ],
    );
  }

  Widget _tasksList() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _tasks.length,
        itemBuilder: (_, i) {
          final t = _tasks[i];
          final escalated = t['escalatedAt'] != null;
          final done = t['status'] == 'DONE';
          return Card(
            child: ListTile(
              leading: Icon(
                done ? Icons.check_circle : (escalated ? Icons.warning : Icons.schedule),
                color: done ? Colors.green : (escalated ? Colors.red : Colors.orange),
              ),
              title: Text(t['title']),
              subtitle: Text(
                '${t['assigneeName']} · ${t['status']}'
                '${t['chaseCount'] > 0 ? " · chased ${t['chaseCount']}x" : ""}'
                '${escalated ? " · ESCALATED" : ""}',
              ),
              trailing: Text(t['priority'], style: const TextStyle(fontSize: 11)),
            ),
          );
        },
      ),
    );
  }

  Widget _teamView() {
    if (_stats.isEmpty) {
      return const Center(child: Text('No data yet'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _stats.length,
        itemBuilder: (_, i) {
          final s = _stats[i];
          return Card(
            child: ListTile(
              title: Text(s['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Done ${s['done']}/${s['total']} · On-time ${s['onTimePct']}%'
                '${s['escalated'] > 0 ? " · ${s['escalated']} escalated" : ""}',
              ),
              trailing: CircleAvatar(
                backgroundColor: s['onTimePct'] >= 80
                    ? Colors.green
                    : (s['onTimePct'] >= 50 ? Colors.orange : Colors.red),
                child: Text('${s['onTimePct']}',
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openAssign() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AssignSheet(),
    );
    if (ok == true) _load();
  }

  Future<void> _openAddUser() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddUserSheet(),
    );
    if (ok == true) _load();
  }
}

// ---------- ASSIGN TASK ----------
class _AssignSheet extends StatefulWidget {
  const _AssignSheet();
  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  List<dynamic> _users = [];
  final Set<String> _selected = {};
  String _priority = 'NORMAL';
  int _dueMinutes = 60;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Api.users().then((u) => setState(() => _users = u));
  }

  Future<void> _save() async {
    if (_title.text.trim().length < 2 || _selected.isEmpty) return;
    setState(() => _saving = true);
    try {
      await Api.createTask(
        title: _title.text.trim(),
        description: _desc.text.trim(),
        assigneeIds: _selected.toList(),
        dueAt: DateTime.now().add(Duration(minutes: _dueMinutes)),
        priority: _priority,
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
            const Text('Assign a task',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                  labelText: 'What needs doing?', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(
                  labelText: 'Details (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            const Align(alignment: Alignment.centerLeft, child: Text('Assign to')),
            ..._users.map((u) => CheckboxListTile(
                  dense: true,
                  value: _selected.contains(u['id']),
                  title: Text('${u['name']} (${u['role']})'),
                  onChanged: (v) => setState(() {
                    v == true ? _selected.add(u['id']) : _selected.remove(u['id']);
                  }),
                )),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Priority: '),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _priority,
                  items: const [
                    DropdownMenuItem(value: 'HIGH', child: Text('High')),
                    DropdownMenuItem(value: 'NORMAL', child: Text('Normal')),
                    DropdownMenuItem(value: 'LOW', child: Text('Low')),
                  ],
                  onChanged: (v) => setState(() => _priority = v!),
                ),
              ],
            ),
            Row(
              children: [
                const Text('Due in: '),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _dueMinutes,
                  items: const [
                    DropdownMenuItem(value: 2, child: Text('2 min (test)')),
                    DropdownMenuItem(value: 60, child: Text('1 hour')),
                    DropdownMenuItem(value: 240, child: Text('4 hours')),
                    DropdownMenuItem(value: 1440, child: Text('Tomorrow')),
                  ],
                  onChanged: (v) => setState(() => _dueMinutes = v!),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text(_saving
                  ? 'Assigning...'
                  : 'Assign to ${_selected.length} person(s)'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- ADD USER ----------
class _AddUserSheet extends StatefulWidget {
  const _AddUserSheet();
  @override
  State<_AddUserSheet> createState() => _AddUserSheetState();
}

class _AddUserSheetState extends State<_AddUserSheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController(text: 'password123');
  String _role = 'EMPLOYEE';
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Api.addUser(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        role: _role,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Add a person',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'Name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            decoration: const InputDecoration(
                labelText: 'Email', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            decoration: const InputDecoration(
                labelText: 'Temporary password', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: const InputDecoration(
                labelText: 'Role', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'EMPLOYEE', child: Text('Employee')),
              DropdownMenuItem(value: 'MANAGER', child: Text('Manager')),
            ],
            onChanged: (v) => setState(() => _role = v!),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: Text(_saving ? 'Adding...' : 'Add person'),
          ),
        ],
      ),
    );
  }
}