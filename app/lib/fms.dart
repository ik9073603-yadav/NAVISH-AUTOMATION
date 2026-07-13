import 'package:flutter/material.dart';
import 'api.dart';

class FmsScreen extends StatefulWidget {
  const FmsScreen({super.key});
  @override
  State<FmsScreen> createState() => _FmsScreenState();
}

class _FmsScreenState extends State<FmsScreen> {
  List<dynamic> _orders = [];
  List<dynamic> _flows = [];
  List<dynamic> _bottlenecks = [];
  bool _loading = true;
  int _view = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final o = await Api.orders();
      final f = await Api.flows();
      final b = await Api.bottlenecks();
      setState(() {
        _orders = o;
        _flows = f;
        _bottlenecks = b;
      });
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
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Live board')),
                ButtonSegment(value: 1, label: Text('Bottlenecks')),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          ),
          Expanded(child: _view == 0 ? _board() : _bottleneckView()),
        ],
      ),
      floatingActionButton: _flows.isEmpty
          ? FloatingActionButton.extended(
              heroTag: 'flow',
              onPressed: _newFlow,
              icon: const Icon(Icons.account_tree),
              label: const Text('Create your first flow'),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'flow',
                  onPressed: _newFlow,
                  icon: const Icon(Icons.account_tree),
                  label: const Text('New flow'),
                ),
                const SizedBox(width: 8),
                FloatingActionButton.extended(
                  heroTag: 'order',
                  onPressed: _newItem,
                  icon: const Icon(Icons.add_box),
                  label: const Text('Start new'),
                ),
              ],
            ),
    );
  }

  Widget _board() {
    if (_orders.isEmpty) {
      return Center(
        child: Text(
          _flows.isEmpty
              ? 'No flows yet.\nBuild your process first.'
              : 'Nothing in progress.\nStart one below.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _orders.length,
        itemBuilder: (_, i) {
          final o = _orders[i];
          final done = o['status'] == 'COMPLETED';
          final delayed = o['delayed'] == true;
          return Card(
            child: ListTile(
              leading: Icon(
                done
                    ? Icons.check_circle
                    : (delayed ? Icons.warning : Icons.local_shipping),
                color: done
                    ? Colors.green
                    : (delayed ? Colors.red : Colors.blue),
              ),
              title: Text(o['orderNumber'],
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(done
                      ? 'Completed'
                      : 'At: ${o['currentStage']}  (${o['doneStages']}/${o['totalStages']})'),
                  if (!done)
                    Text(
                      _sitting(o['sittingMins'] as int),
                      style: TextStyle(
                        fontSize: 12,
                        color: delayed ? Colors.red : Colors.grey,
                      ),
                    ),
                ],
              ),
              trailing: done || o['orderStageId'] == null
                  ? null
                  : FilledButton(
                      onPressed: () => _completeStage(o),
                      child: const Text('Complete'),
                    ),
            ),
          );
        },
      ),
    );
  }

  String _sitting(int mins) {
    if (mins < 60) return 'Sitting $mins min';
    if (mins < 1440) return 'Sitting ${(mins / 60).toStringAsFixed(1)} hrs';
    return 'Sitting ${(mins / 1440).toStringAsFixed(1)} days';
  }

  Widget _bottleneckView() {
    if (_bottlenecks.isEmpty) return const Center(child: Text('No data yet'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _bottlenecks.length,
        itemBuilder: (_, i) {
          final b = _bottlenecks[i];
          final stuck = b['ordersStuck'] as int;
          final planned = b['plannedMins'];
          return Card(
            color: stuck > 0 ? Colors.red.shade50 : null,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: stuck > 2
                    ? Colors.red
                    : (stuck > 0 ? Colors.orange : Colors.green),
                child: Text('$stuck',
                    style: const TextStyle(color: Colors.white)),
              ),
              title: Text(b['stageName'],
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${b['flowName']} · $stuck order(s) here'
                '${planned == null ? " · unplanned" : ""}'
                '${b['avgDelayMins'] != 0 ? " · avg delay ${b['avgDelayMins']} min" : ""}',
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _newItem() async {
    final flowId = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Start an order in which flow?'),
        children: _flows
            .map((f) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, f['id'] as String),
                  child: Text('${f['name']} — new ${f['itemLabel']}'),
                ))
            .toList(),
      ),
    );
    if (flowId == null) return;
    await Api.createOrder(flowId);
    _load();
  }

  Future<void> _completeStage(Map o) async {
    final flow = _flows.firstWhere(
      (f) => f['name'] == o['flowName'],
      orElse: () => null,
    );
    final stage = flow == null
        ? null
        : (flow['stages'] as List).firstWhere(
            (s) => s['id'] == o['currentStageId'],
            orElse: () => null,
          );
    final fields = stage == null ? [] : (stage['fields'] as List);

    final data = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _StageFormSheet(
        stageName: o['currentStage'],
        orderNumber: o['orderNumber'],
        fields: fields,
      ),
    );
    if (data == null) return;

    try {
      await Api.completeStage(o['orderStageId'], data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stage done. Order moved forward.')),
      );
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _newFlow() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FlowBuilderSheet(),
    );
    if (ok == true) _load();
  }
}

// ---------------- STAGE FORM ----------------
class _StageFormSheet extends StatefulWidget {
  final String stageName;
  final String orderNumber;
  final List fields;

  const _StageFormSheet({
    required this.stageName,
    required this.orderNumber,
    required this.fields,
  });

  @override
  State<_StageFormSheet> createState() => _StageFormSheetState();
}

class _StageFormSheetState extends State<_StageFormSheet> {
  final Map<String, dynamic> _data = {};

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${widget.orderNumber} — ${widget.stageName}',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (widget.fields.isEmpty)
              const Text('No fields to fill. Just confirm.',
                  style: TextStyle(color: Colors.grey)),
            ...widget.fields.map((f) {
              final label = f['label'] as String;
              final type = f['type'] as String;
              final req = f['required'] == true;

              if (type == 'YESNO') {
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('$label${req ? " *" : ""}'),
                  value: _data[label] == true,
                  onChanged: (v) => setState(() => _data[label] = v),
                );
              }

              if (type == 'DROPDOWN') {
                final opts = ((f['options'] as String?) ?? '')
                    .split(',')
                    .where((s) => s.trim().isNotEmpty)
                    .toList();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: '$label${req ? " *" : ""}',
                      border: const OutlineInputBorder(),
                    ),
                    items: opts
                        .map((o) => DropdownMenuItem(
                            value: o.trim(), child: Text(o.trim())))
                        .toList(),
                    onChanged: (v) => _data[label] = v,
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  keyboardType:
                      type == 'NUMBER' ? TextInputType.number : null,
                  decoration: InputDecoration(
                    labelText: '$label${req ? " *" : ""}',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) =>
                      _data[label] = type == 'NUMBER' ? (num.tryParse(v) ?? v) : v,
                ),
              );
            }),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, _data),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              child: const Text('Complete stage'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- FLOW BUILDER ----------------
class _FlowBuilderSheet extends StatefulWidget {
  const _FlowBuilderSheet();
  @override
  State<_FlowBuilderSheet> createState() => _FlowBuilderSheetState();
}

class _FlowBuilderSheetState extends State<_FlowBuilderSheet> {
  final _name = TextEditingController();
  final _prefix = TextEditingController(text: 'ORD');
  final _itemLabel = TextEditingController(text: 'Order');
  List<dynamic> _users = [];
  final List<_StageDraft> _stages = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Api.users().then((u) {
      if (mounted) setState(() => _users = u);
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2 || _stages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Flow needs a name and at least one stage')),
      );
      return;
    }
    if (_stages.any((s) => s.name.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Every stage needs a name')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await Api.createFlow(
        name: _name.text.trim(),
        prefix: _prefix.text.trim().toUpperCase(),
        itemLabel: _itemLabel.text.trim(),
        stages: _stages.map((s) => s.toJson()).toList(),
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
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Build a flow',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Text('Your own process. Any number of stages.',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Flow name (e.g. Order to Delivery)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _itemLabel,
              decoration: const InputDecoration(
                labelText: 'What do you call each one?',
                hintText: 'Order / Batch / Job / Ticket / Lot',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _prefix,
              decoration: const InputDecoration(
                labelText: 'Order prefix (e.g. ORD)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Stages',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            ..._stages.asMap().entries.map((entry) {
              return _StageCard(
                index: entry.key,
                draft: entry.value,
                users: _users,
                onRemove: () => setState(() => _stages.removeAt(entry.key)),
                onChanged: () => setState(() {}),
              );
            }),
            OutlinedButton.icon(
              onPressed: () => setState(() => _stages.add(_StageDraft())),
              icon: const Icon(Icons.add),
              label: const Text('Add stage'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text(_saving ? 'Creating...' : 'Create flow'),
            ),
          ],
        ),
      ),
    );
  }
}

// Stage ka draft — plannedMins null = unplanned
class _StageDraft {
  String name = '';
  String? responsibleId;
  bool hasPlannedTime = false;
  int? planValue;
  String planUnit = 'minutes';
  List<Map<String, dynamic>> fields = [];

  int? get plannedMins {
    if (!hasPlannedTime || planValue == null) return null;
    switch (planUnit) {
      case 'hours':
        return planValue! * 60;
      case 'days':
        return planValue! * 60 * 24;
      default:
        return planValue;
    }
  }

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        if (responsibleId != null) 'responsibleId': responsibleId,
        if (plannedMins != null) 'plannedMins': plannedMins,
        'fields': fields,
      };
}

class _StageCard extends StatelessWidget {
  final int index;
  final _StageDraft draft;
  final List users;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _StageCard({
    required this.index,
    required this.draft,
    required this.users,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  child: Text('${index + 1}',
                      style: const TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 8),
                const Expanded(child: Text('Stage')),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  onPressed: onRemove,
                ),
              ],
            ),
            TextField(
              decoration: const InputDecoration(labelText: 'Stage name'),
              onChanged: (v) {
                draft.name = v;
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: draft.responsibleId,
              decoration:
                  const InputDecoration(labelText: 'Who is responsible?'),
              items: users
                  .map((u) => DropdownMenuItem<String>(
                        value: u['id'] as String,
                        child: Text('${u['name']}'),
                      ))
                  .toList(),
              onChanged: (v) {
                draft.responsibleId = v;
                onChanged();
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Has a planned time?',
                  style: TextStyle(fontSize: 14)),
              subtitle: Text(
                draft.hasPlannedTime
                    ? 'Late = chase + escalate'
                    : 'Unplanned — no deadline, no chasing',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              value: draft.hasPlannedTime,
              onChanged: (v) {
                draft.hasPlannedTime = v;
                if (!v) draft.planValue = null;
                onChanged();
              },
            ),
            if (draft.hasPlannedTime)
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'How long?',
                        hintText: 'e.g. 30',
                      ),
                      onChanged: (v) {
                        draft.planValue = int.tryParse(v);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      initialValue: draft.planUnit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: const [
                        DropdownMenuItem(
                            value: 'minutes', child: Text('minutes')),
                        DropdownMenuItem(value: 'hours', child: Text('hours')),
                        DropdownMenuItem(value: 'days', child: Text('days')),
                      ],
                      onChanged: (v) {
                        draft.planUnit = v ?? 'minutes';
                        onChanged();
                      },
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text('${draft.fields.length} custom field(s)',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey)),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add field'),
                  onPressed: () async {
                    final f = await showDialog<Map<String, dynamic>>(
                      context: context,
                      builder: (_) => const _FieldDialog(),
                    );
                    if (f != null) {
                      draft.fields.add(f);
                      onChanged();
                    }
                  },
                ),
              ],
            ),
            ...draft.fields.map(
              (f) => Text('  • ${f['label']} (${f['type']})',
                  style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- FIELD DIALOG ----------------
class _FieldDialog extends StatefulWidget {
  const _FieldDialog();
  @override
  State<_FieldDialog> createState() => _FieldDialogState();
}

class _FieldDialogState extends State<_FieldDialog> {
  final _label = TextEditingController();
  final _options = TextEditingController();
  String _type = 'TEXT';
  bool _required = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a field'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                  labelText: 'Field label (e.g. Quantity)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: 'TEXT', child: Text('Text')),
                DropdownMenuItem(value: 'NUMBER', child: Text('Number')),
                DropdownMenuItem(value: 'DROPDOWN', child: Text('Dropdown')),
                DropdownMenuItem(value: 'DATE', child: Text('Date')),
                DropdownMenuItem(value: 'YESNO', child: Text('Yes / No')),
              ],
              onChanged: (v) => setState(() => _type = v!),
            ),
            if (_type == 'DROPDOWN')
              TextField(
                controller: _options,
                decoration: const InputDecoration(
                    labelText: 'Options, comma separated (A,B,C)'),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Required'),
              value: _required,
              onChanged: (v) => setState(() => _required = v ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_label.text.trim().isEmpty) return;
            Navigator.pop(context, {
              'label': _label.text.trim(),
              'type': _type,
              'required': _required,
              if (_type == 'DROPDOWN') 'options': _options.text.trim(),
            });
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}