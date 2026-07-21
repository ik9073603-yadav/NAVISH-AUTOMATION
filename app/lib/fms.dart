import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'order_history.dart';
import 'filters.dart';
import 'contact_actions.dart';
import 'export_actions.dart';
import 'template_setup.dart';
import 'responsive.dart';
import 'widgets/motion.dart';
import 'widgets/cost_of_delay_info.dart';
import 'offline/write_queue.dart';
import 'flow_analytics.dart';

class FmsScreen extends StatefulWidget {
  final String? currentUserId;
  final String? role;

  const FmsScreen({super.key, this.currentUserId, this.role});
  @override
  State<FmsScreen> createState() => _FmsScreenState();
}

class _FmsScreenState extends State<FmsScreen> {
  List<dynamic> _orders = [];
  List<dynamic> _flows = [];
  List<dynamic> _bottlenecks = [];
  List<dynamic> _users = [];
  bool _loading = true;
  int _view = 0;
  String _orderStatus = 'ACTIVE';
  DateRangePreset _datePreset = DateRangePreset.all;
  String? _assigneeId;

  // Owner never executes; only the stage's responsible person (or anyone,
  // if the stage has no assigned responsible) may complete it.
  bool _canComplete(Map o) {
    if (widget.role == 'OWNER' || widget.currentUserId == null) return false;
    final responsibleId = o['responsibleId'];
    return responsibleId == null || responsibleId == widget.currentUserId;
  }

  bool get _canSeeAnalytics => widget.role == 'OWNER' || widget.role == 'MANAGER';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final o = await Api.orders(
        status: _orderStatus,
        from: _datePreset.from,
        assigneeId: _assigneeId,
      );
      final f = await Api.flows();
      final b = await Api.bottlenecks();
      final u = await Api.users();
      setState(() {
        _orders = o;
        _flows = f;
        _bottlenecks = b;
        _users = u;
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
    if (_loading) return const Scaffold(body: ShimmerSkeletonList());

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<int>(
                    segments: [
                      const ButtonSegment(value: 0, label: Text('Live board')),
                      const ButtonSegment(value: 1, label: Text('Bottlenecks')),
                      if (_canSeeAnalytics) const ButtonSegment(value: 2, label: Text('Analytics')),
                    ],
                    selected: {_view},
                    onSelectionChanged: (s) => setState(() => _view = s.first),
                  ),
                ),
                if (_flows.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.ios_share),
                    tooltip: 'Export orders',
                    onPressed: _exportOrders,
                  ),
              ],
            ),
          ),
          Expanded(
            child: switch (_view) {
              1 => _bottleneckView(),
              2 when _canSeeAnalytics => const FlowAnalyticsView(),
              _ => _board(),
            },
          ),
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
    return Column(
      children: [
        FilterBar(
          status: _orderStatus,
          onStatusChanged: (s) {
            setState(() => _orderStatus = s);
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
          child: _orders.isEmpty
              ? Center(
                  child: Text(
                    _flows.isEmpty
                        ? 'No flows yet.\nBuild your process first.'
                        : (_orderStatus == 'ACTIVE'
                            ? 'Nothing in progress.\nStart one below.'
                            : 'Nothing here yet.'),
                    textAlign: TextAlign.center,
                  ),
                )
              : _ordersList(),
        ),
      ],
    );
  }

  Widget _ordersList() {
    final phoneByUserId = <String, String?>{
      for (final u in _users) u['id'] as String: u['phone'] as String?,
    };
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _orders.length,
        itemBuilder: (_, i) {
          final o = _orders[i];
          final done = o['status'] == 'COMPLETED';
          final delayed = o['delayed'] == true;
          final canComplete = !done && o['orderStageId'] != null && _canComplete(o);
          return StaggeredListItem(
            index: i,
            child: Card(
              child: ListTile(
                onTap: () => Navigator.push(
                  context,
                  sharedAxisRoute(OrderHistoryScreen(
                    orderId: o['id'] as String,
                    orderNumber: o['orderNumber'] as String,
                  )),
                ),
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
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!done)
                      ContactButtons(
                        phone: phoneByUserId[o['responsibleId']],
                        message: 'Hi, checking on: ${o['orderNumber']} — ${o['currentStage']}.',
                        iconSize: 20,
                      ),
                    if (canComplete)
                      FilledButton(
                        onPressed: () => _completeStage(o),
                        child: const Text('Complete'),
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
          return StaggeredListItem(
            index: i,
            child: Card(
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
    if (flowId == null || !mounted) return;

    // Optional — dismissing this (tap outside, or "Skip") just starts the
    // order with no captured value; Cost of Delay falls back to the ₹/hr
    // rate (or shows the "set a delay cost" prompt) for that order.
    final orderValue = await showAdaptiveSheet<double?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _OrderValueSheet(),
    );

    await Api.createOrder(flowId, orderValue: orderValue);
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

    final result = await showAdaptiveSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _StageFormSheet(
        stageName: o['currentStage'],
        orderNumber: o['orderNumber'],
        fields: fields,
      ),
    );
    if (result == null || !mounted) return;

    // Only the final stage of an order gets the bigger celebration — every
    // other stage gets the same quick confirmation as marking a task done.
    final isLastStage = (o['doneStages'] as int) + 1 >= (o['totalStages'] as int);

    // Self-contained, same as the original: the confirmation animation
    // fires this immediately and plays concurrently, so the real network
    // call is never delayed by the animation. Errors are handled here, not
    // by the animation helper, exactly as before this pass.
    Future<void> submit() async {
      try {
        await Api.completeStage(
          o['orderStageId'],
          result['data'] as Map<String, dynamic>,
          remarks: result['remarks'] as String?,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isLastStage ? 'Order complete! 🎉' : 'Stage done. Order moved forward.')),
        );
        _load();
      } on OfflineQueuedException {
        // Queued — the order's real position won't change until sync, so we
        // deliberately don't guess where it'll land. The pending-count banner
        // is the signal here.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved offline — will sync when back online')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }

    if (isLastStage) {
      await playCelebration(context, onFinished: submit);
    } else {
      await playDoneConfirmation(context, onFinished: submit);
    }
  }

  Future<void> _exportOrders() async {
    final flowId = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Export which flow?'),
        children: _flows
            .map((f) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, f['id'] as String),
                  child: Text(f['name'] as String),
                ))
            .toList(),
      ),
    );
    if (flowId == null || !mounted) return;

    final format = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Format'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'csv'), child: const Text('CSV')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'xlsx'), child: const Text('Excel (.xlsx)')),
        ],
      ),
    );
    if (format == null || !mounted) return;

    try {
      final (bytes, filename) = await Api.exportFms(flowId, format);
      await shareExportedFile(bytes, filename);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _newFlow() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('New flow'),
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
        builder: (_) => const _FlowBuilderSheet(),
      );
      if (ok == true) _load();
      return;
    }

    final applied = await pickAndApplyTemplate(context, 'FMS');
    if (applied == null || !mounted) return;
    final done = await Navigator.push<bool>(
      context,
      sharedAxisRoute(TemplateAssignStagesScreen(flowId: applied['flowId'] as String)),
    );
    if (done == true) _load();
  }
}

// ---------------- ORDER VALUE (Cost of Delay) ----------------
class _OrderValueSheet extends StatefulWidget {
  const _OrderValueSheet();
  @override
  State<_OrderValueSheet> createState() => _OrderValueSheetState();
}

class _OrderValueSheetState extends State<_OrderValueSheet> {
  final _value = TextEditingController();

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Order value (optional)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const CostOfDelayInfoButton(),
            ],
          ),
          const Text(
            'Used to estimate the ₹ cost of a delay if no per-hour rate is set in Settings.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _value,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Order value (₹)',
              prefixText: '₹ ',
              hintText: 'e.g. 50000',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Skip'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, double.tryParse(_value.text.trim())),
                  child: const Text('Start order'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
  final _remarks = TextEditingController();
  String? _uploadingField;

  List<String> _photoList(String label) =>
      _data.putIfAbsent(label, () => <String>[]) as List<String>;

  Future<void> _addPhotos(String label) async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage();
    if (files.isEmpty) return;

    setState(() => _uploadingField = label);
    try {
      final urls = _photoList(label);
      for (final f in files) {
        final Uint8List bytes = await f.readAsBytes();
        final url = await Api.uploadImage(bytes, f.name);
        urls.add(url);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingField = null);
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

              if (type == 'PHOTO') {
                final urls = _photoList(label);
                final uploading = _uploadingField == label;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$label${req ? " *" : ""}'),
                      const SizedBox(height: 8),
                      if (urls.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: urls.map((url) {
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    url,
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: -8,
                                  right: -8,
                                  child: GestureDetector(
                                    onTap: () => setState(() => urls.remove(url)),
                                    child: const CircleAvatar(
                                      radius: 10,
                                      backgroundColor: Colors.red,
                                      child: Icon(Icons.close, size: 14, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: uploading ? null : () => _addPhotos(label),
                        icon: uploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add_a_photo, size: 18),
                        label: Text(uploading ? 'Uploading...' : 'Add photo'),
                      ),
                    ],
                  ),
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
            TextField(
              controller: _remarks,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Remarks (optional)',
                hintText: 'Any notes about this stage...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'data': _data,
                'remarks': _remarks.text.trim(),
              }),
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
                DropdownMenuItem(value: 'PHOTO', child: Text('Photo')),
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