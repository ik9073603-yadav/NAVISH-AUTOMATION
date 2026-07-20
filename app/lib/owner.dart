import 'package:flutter/material.dart';
import 'api.dart';
import 'filters.dart';
import 'contact_actions.dart';
import 'responsive.dart';
import 'widgets/motion.dart';
import 'l10n/gen/app_localizations.dart';

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
      return const ShimmerSkeletonList();
    }
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: _tab == 0 ? _tasksView() : _teamView(),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: _openAssign,
              icon: const Icon(Icons.add),
              label: Text(l10n.assignTaskAction),
            )
          : FloatingActionButton.extended(
              onPressed: _openAddUser,
              icon: const Icon(Icons.person_add),
              label: Text(l10n.addPerson),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.list_alt), label: l10n.allTasks),
          NavigationDestination(icon: const Icon(Icons.groups), label: l10n.team),
        ],
      ),
    );
  }

  Widget _tasksView() {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        FilterBar(
          status: _taskStatus,
          onStatusChanged: (s) {
            setState(() => _taskStatus = s);
            _load();
          },
          activeLabel: l10n.activeFilter,
          doneLabel: l10n.doneFilter,
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
              ? Center(child: Text(l10n.noTasksAssignOne))
              : _tasksList(),
        ),
      ],
    );
  }

  Widget _tasksList() {
    final phoneByAssignee = <String, String?>{
      for (final u in _users) u['id'] as String: u['phone'] as String?,
    };
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _tasks.length,
        itemBuilder: (_, i) {
          final t = _tasks[i];
          final escalated = t['escalatedAt'] != null;
          final done = t['status'] == 'DONE';
          return StaggeredListItem(
            index: i,
            child: Card(
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
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t['priority'], style: const TextStyle(fontSize: 11)),
                    ContactButtons(
                      phone: phoneByAssignee[t['assigneeId']],
                      message: 'Hi ${t['assigneeName']}, checking on: ${t['title']}.',
                      iconSize: 20,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _teamView() {
    final l10n = AppLocalizations.of(context);
    if (_users.isEmpty) {
      return Center(child: Text(l10n.noDataYet));
    }
    // /stats only returns users with at least one task ever — a freshly
    // added person with none yet must still show up here to be manageable.
    final statsByUserId = <String, dynamic>{
      for (final s in _stats) s['userId'] as String: s,
    };
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _users.length,
        itemBuilder: (_, i) {
          final u = _users[i];
          final s = statsByUserId[u['id']];
          final role = u['role'] as String;
          final hasInventoryAccess = u['canStockIn'] == true || u['canStockOut'] == true;
          return StaggeredListItem(
            index: i,
            child: Card(
              child: ListTile(
                title: Text(u['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  s == null
                      ? l10n.noTasksYetRole(role)
                      : 'Done ${s['done']}/${s['total']} · On-time ${s['onTimePct']}%'
                        '${s['escalated'] > 0 ? " · ${s['escalated']} escalated" : ""}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (role == 'EMPLOYEE')
                      IconButton(
                        icon: Icon(
                          hasInventoryAccess ? Icons.inventory : Icons.inventory_2_outlined,
                          color: hasInventoryAccess ? Colors.green : null,
                        ),
                        tooltip: l10n.inventoryPermissionsTooltip,
                        onPressed: () => _editInventoryPermissions(u),
                      ),
                    ContactButtons(
                      phone: u['phone'] as String?,
                      message: 'Hi ${u['name']}, ',
                      iconSize: 20,
                    ),
                    if (s != null)
                      CircleAvatar(
                        backgroundColor: s['onTimePct'] >= 80
                            ? Colors.green
                            : (s['onTimePct'] >= 50 ? Colors.orange : Colors.red),
                        child: Text('${s['onTimePct']}',
                            style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _editInventoryPermissions(Map user) async {
    final l10n = AppLocalizations.of(context);
    bool canIn = user['canStockIn'] == true;
    bool canOut = user['canStockOut'] == true;
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.inventoryPermissionsTitle(user['name'])),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.canAddStock),
                value: canIn,
                onChanged: (v) => setDialogState(() => canIn = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.canRemoveStock),
                value: canOut,
                onChanged: (v) => setDialogState(() => canOut = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.save)),
          ],
        ),
      ),
    );
    if (save != true) return;

    try {
      await Api.updateInventoryPermissions(user['id'] as String, canStockIn: canIn, canStockOut: canOut);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated permissions for ${user['name']}')),
        );
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _openAssign() async {
    final ok = await showAdaptiveSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AssignSheet(),
    );
    if (ok == true) _load();
  }

  Future<void> _openAddUser() async {
    final ok = await showAdaptiveSheet<bool>(
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
            Text(l10n.assignATask,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              decoration: InputDecoration(
                  labelText: l10n.whatNeedsDoing, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              decoration: InputDecoration(
                  labelText: l10n.detailsOptional, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Align(alignment: Alignment.centerLeft, child: Text(l10n.assignTo)),
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
                Text(l10n.priorityLabel),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _priority,
                  items: [
                    DropdownMenuItem(value: 'HIGH', child: Text(l10n.priorityHigh)),
                    DropdownMenuItem(value: 'NORMAL', child: Text(l10n.priorityNormal)),
                    DropdownMenuItem(value: 'LOW', child: Text(l10n.priorityLow)),
                  ],
                  onChanged: (v) => setState(() => _priority = v!),
                ),
              ],
            ),
            Row(
              children: [
                Text(l10n.dueIn),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _dueMinutes,
                  items: [
                    DropdownMenuItem(value: 2, child: Text(l10n.dueIn2Min)),
                    DropdownMenuItem(value: 60, child: Text(l10n.dueIn1Hour)),
                    DropdownMenuItem(value: 240, child: Text(l10n.dueIn4Hours)),
                    DropdownMenuItem(value: 1440, child: Text(l10n.dueInTomorrow)),
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
                  ? l10n.assigning
                  : l10n.assignToNPeople(_selected.length)),
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
  final _phone = TextEditingController();
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
        phone: _phone.text.trim(),
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
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.addAPerson,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: InputDecoration(
                labelText: l10n.nameLabel, border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            decoration: InputDecoration(
                labelText: l10n.emailLabel, border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
                labelText: l10n.phoneOptionalLabel,
                hintText: '9876543210',
                border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            decoration: InputDecoration(
                labelText: l10n.temporaryPassword, border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: InputDecoration(
                labelText: l10n.roleFieldLabel, border: const OutlineInputBorder()),
            items: [
              DropdownMenuItem(value: 'EMPLOYEE', child: Text(l10n.roleEmployee)),
              DropdownMenuItem(value: 'MANAGER', child: Text(l10n.roleManager)),
            ],
            onChanged: (v) => setState(() => _role = v!),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: Text(_saving ? l10n.adding : l10n.addPerson),
          ),
        ],
      ),
    );
  }
}