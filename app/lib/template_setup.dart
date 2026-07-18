import 'package:flutter/material.dart';
import 'api.dart';
import 'responsive.dart';

// Shows the template library (filtered by type), lets the user pick one,
// and applies it. Returns the apply result ({type, flowId} or {type, ruleId})
// or null if the user backed out at any point.
Future<Map<String, dynamic>?> pickAndApplyTemplate(BuildContext context, String type) async {
  List<dynamic> all;
  try {
    all = await Api.templates();
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    return null;
  }
  final templates = all.where((t) => t['type'] == type).toList();

  if (!context.mounted) return null;
  final chosen = await showAdaptiveSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TemplateListSheet(templates: templates),
  );
  if (chosen == null) return null;

  if (!context.mounted) return null;
  try {
    return await Api.applyTemplate(chosen['id'] as String);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    return null;
  }
}

class _TemplateListSheet extends StatelessWidget {
  final List<dynamic> templates;
  const _TemplateListSheet({required this.templates});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Start from template', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (templates.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('No templates available.')),
            ...templates.map((t) => Card(
                  child: ListTile(
                    title: Text(t['name'] as String),
                    subtitle: Text(t['description'] as String),
                    onTap: () => Navigator.pop(context, t as Map<String, dynamic>),
                  ),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// After applying an FMS template: assign a responsible person per stage
// (all start unassigned — never guessed). Pops true if the user saved.
class TemplateAssignStagesScreen extends StatefulWidget {
  final String flowId;
  const TemplateAssignStagesScreen({super.key, required this.flowId});
  @override
  State<TemplateAssignStagesScreen> createState() => _TemplateAssignStagesScreenState();
}

class _TemplateAssignStagesScreenState extends State<TemplateAssignStagesScreen> {
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic>? _flow;
  List<dynamic> _users = [];
  final Map<String, String?> _responsibleByStage = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final flows = await Api.flows();
      final users = await Api.users();
      final flow = flows.firstWhere((f) => f['id'] == widget.flowId);
      setState(() {
        _flow = flow as Map<String, dynamic>;
        _users = users;
        for (final s in (_flow!['stages'] as List)) {
          _responsibleByStage[s['id'] as String] = s['responsibleId'] as String?;
        }
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      for (final entry in _responsibleByStage.entries) {
        await Api.assignStage(entry.key, responsibleId: entry.value);
      }
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
    return Scaffold(
      appBar: AppBar(title: Text(_flow != null ? '${_flow!['name']} — assign people' : 'Assign people')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  "Pick who's responsible for each stage. Leave blank if anyone can pick it up.",
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ...(_flow!['stages'] as List).map((s) {
                  final stageId = s['id'] as String;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            s['plannedMins'] != null ? 'Planned: ${s['plannedMins']} min' : 'Unplanned — no deadline',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String?>(
                            initialValue: _responsibleByStage[stageId],
                            decoration: const InputDecoration(
                              labelText: 'Responsible person', border: OutlineInputBorder(), isDense: true),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('Unassigned')),
                              ..._users.map((u) => DropdownMenuItem<String?>(
                                    value: u['id'] as String,
                                    child: Text(u['name'] as String),
                                  )),
                            ],
                            onChanged: (v) => setState(() => _responsibleByStage[stageId] = v),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: Text(_saving ? 'Saving...' : 'Save & done'),
                ),
              ],
            ),
    );
  }
}

// After applying a checklist template: it was created inactive and assigned
// to whoever applied it (a safe placeholder, never a guessed employee).
// This screen lets them pick the real person and activate it.
class TemplateAssignChecklistScreen extends StatefulWidget {
  final String ruleId;
  const TemplateAssignChecklistScreen({super.key, required this.ruleId});
  @override
  State<TemplateAssignChecklistScreen> createState() => _TemplateAssignChecklistScreenState();
}

class _TemplateAssignChecklistScreenState extends State<TemplateAssignChecklistScreen> {
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic>? _rule;
  List<dynamic> _users = [];
  String? _assigneeId;
  bool _activate = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rules = await Api.checklists(status: 'ALL');
      final users = await Api.users();
      final rule = rules.firstWhere((r) => r['id'] == widget.ruleId);
      setState(() {
        _rule = rule as Map<String, dynamic>;
        _users = users;
        _assigneeId = _rule!['assigneeId'] as String?;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Api.updateChecklistRule(widget.ruleId, assigneeId: _assigneeId, active: _activate);
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
    return Scaffold(
      appBar: AppBar(title: Text(_rule != null ? '${_rule!['title']} — assign' : 'Assign checklist')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(_rule!['description'] as String? ?? '', style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  initialValue: _assigneeId,
                  decoration: const InputDecoration(labelText: 'Assign to', border: OutlineInputBorder()),
                  items: _users
                      .map((u) => DropdownMenuItem<String?>(value: u['id'] as String, child: Text(u['name'] as String)))
                      .toList(),
                  onChanged: (v) => setState(() => _assigneeId = v),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activate now'),
                  subtitle: const Text('Otherwise it stays inactive until you turn it on later'),
                  value: _activate,
                  onChanged: (v) => setState(() => _activate = v),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: Text(_saving ? 'Saving...' : 'Save & done'),
                ),
              ],
            ),
    );
  }
}
