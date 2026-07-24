import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'api.dart';
import 'export_actions.dart';
import 'responsive.dart';
import 'theme/app_theme.dart';
import 'widgets/motion.dart';
import 'offline/write_queue.dart';

class InventoryScreen extends StatefulWidget {
  final String? role;
  final bool canStockIn;
  final bool canStockOut;
  const InventoryScreen({super.key, this.role, this.canStockIn = false, this.canStockOut = false});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<dynamic> _skus = [];
  Map<String, dynamic>? _summary;
  bool _loading = true;
  String _statusFilter = 'ALL';
  final _search = TextEditingController();

  bool get _canManage => widget.role == 'OWNER' || widget.role == 'MANAGER';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final skusFuture = Api.skus(search: _search.text.trim(), status: _statusFilter);
      final summaryFuture = _canManage ? Api.inventorySummary() : Future.value(null);
      final results = await Future.wait([skusFuture, summaryFuture]);
      setState(() { _skus = results[0] as List<dynamic>; _summary = results[1] as Map<String, dynamic>?; });
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
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_summary != null) _summaryCard(),
            if (_summary != null) const SizedBox(height: 12),
            _searchBar(),
            const SizedBox(height: 8),
            _filterChips(),
            const SizedBox(height: 8),
            if (_skus.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: Text('No SKUs found')),
              )
            else
              for (final (i, sku) in _skus.indexed)
                StaggeredListItem(index: i, child: _skuTile(sku)),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: _openAddSku,
              icon: const Icon(Icons.add),
              label: const Text('Add SKU'),
            )
          : null,
    );
  }

  Widget _summaryCard() {
    final s = _summary!;
    final lowCount = s['lowStockCount'] as int;
    final deadCount = s['deadStockCount'] as int;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Inventory summary',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                IconButton(
                  icon: const Icon(Icons.ios_share, size: 20),
                  tooltip: 'Export movements',
                  onPressed: _exportMovements,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statTile('₹${(s['totalStockValue'] as num).toStringAsFixed(0)}', 'Stock value'),
                _statTile('$lowCount', 'Low stock', color: lowCount > 0 ? AppColors.of(context).danger : null),
                _statTile(
                  '$deadCount',
                  'Dead (₹${(s['deadStockValue'] as num).toStringAsFixed(0)})',
                  color: deadCount > 0 ? Colors.grey.shade700 : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(String value, String label, {Color? color}) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center),
      ],
    );
  }

  Widget _searchBar() {
    return TextField(
      controller: _search,
      decoration: const InputDecoration(
        hintText: 'Search by name or code',
        prefixIcon: Icon(Icons.search),
        border: OutlineInputBorder(),
        isDense: true,
      ),
      onSubmitted: (_) => _load(),
    );
  }

  Widget _filterChips() {
    const options = {'ALL': 'All', 'LOW': 'Low stock', 'DEAD': 'Dead stock'};
    return Wrap(
      spacing: 8,
      children: options.entries.map((e) {
        return ChoiceChip(
          label: Text(e.value),
          selected: _statusFilter == e.key,
          onSelected: (_) {
            setState(() => _statusFilter = e.key);
            _load();
          },
        );
      }).toList(),
    );
  }

  Widget _skuTile(dynamic sku) {
    final liquidClass = sku['liquidClass'] as String;
    final isLow = sku['isLow'] == true;
    final semantic = AppColors.of(context);
    final badgeColor = switch (liquidClass) {
      'LIQUID' => semantic.success,
      'SLOW' => semantic.warning,
      _ => Colors.grey,
    };

    return Card(
      child: ListTile(
        onTap: () => _openSkuDetail(sku),
        title: Text(sku['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${sku['code']} · ${sku['currentStock']} ${sku['unit']}',
          style: TextStyle(
            color: isLow ? semantic.danger : null,
            fontWeight: isLow ? FontWeight.w600 : null,
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(liquidClass,
              style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 11)),
        ),
      ),
    );
  }

  Future<void> _exportMovements() async {
    final format = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Export format'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'csv'), child: const Text('CSV')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'xlsx'), child: const Text('Excel (.xlsx)')),
        ],
      ),
    );
    if (format == null || !mounted) return;

    try {
      final (bytes, filename) = await Api.exportInventoryMovements(format);
      await shareExportedFile(bytes, filename);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _openAddSku() async {
    final ok = await showAdaptiveSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddSkuSheet(),
    );
    if (ok == true) _load();
  }

  Future<void> _openSkuDetail(dynamic sku) async {
    final changed = await showAdaptiveSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SkuDetailSheet(
        sku: sku,
        allowIn: _canManage || widget.canStockIn,
        allowOut: _canManage || widget.canStockOut,
      ),
    );
    if (changed == true) _load();
  }
}

// ---------------- ADD SKU ----------------
class _AddSkuSheet extends StatefulWidget {
  const _AddSkuSheet();
  @override
  State<_AddSkuSheet> createState() => _AddSkuSheetState();
}

class _AddSkuSheetState extends State<_AddSkuSheet> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _category = TextEditingController();
  final _unit = TextEditingController(text: 'pcs');
  final _openingStock = TextEditingController();
  final _minStock = TextEditingController();
  final _maxStock = TextEditingController();
  final _unitCost = TextEditingController();
  bool _saving = false;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await Api.createSku(
        name: _name.text.trim(),
        code: _code.text.trim().isEmpty ? null : _code.text.trim(),
        category: _category.text.trim().isEmpty ? null : _category.text.trim(),
        unit: _unit.text.trim().isEmpty ? 'pcs' : _unit.text.trim(),
        currentStock: double.tryParse(_openingStock.text.trim()),
        minStock: double.tryParse(_minStock.text.trim()),
        maxStock: double.tryParse(_maxStock.text.trim()),
        unitCost: double.tryParse(_unitCost.text.trim()),
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
            const Text('Add SKU', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              decoration: const InputDecoration(
                  labelText: 'Code (optional — auto-generated if blank)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _category,
              decoration: const InputDecoration(
                  labelText: 'Category (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unit,
              decoration: const InputDecoration(
                  labelText: 'Unit (e.g. pcs, kg, box, litre)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _openingStock,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Opening stock (optional, default 0)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minStock,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Min stock (optional)', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _maxStock,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Max stock (optional)', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Leave min/max blank for no alert on that SKU.',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: _unitCost,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Unit cost ₹ (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text(_saving ? 'Saving...' : 'Add SKU'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- SKU DETAIL ----------------
class _SkuDetailSheet extends StatefulWidget {
  final dynamic sku;
  final bool allowIn;
  final bool allowOut;
  const _SkuDetailSheet({required this.sku, required this.allowIn, required this.allowOut});
  @override
  State<_SkuDetailSheet> createState() => _SkuDetailSheetState();
}

class _SkuDetailSheetState extends State<_SkuDetailSheet> {
  Map<String, dynamic>? _history;
  bool _loading = true;
  bool _changed = false;
  bool _showQr = false;
  final _barcodeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    try {
      final h = await Api.skuHistory(widget.sku['id'] as String);
      setState(() => _history = h);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _move(String type) async {
    final result = await showAdaptiveSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MovementSheet(type: type, unit: widget.sku['unit'] as String),
    );
    if (result == null) return;

    try {
      await Api.recordMovement(
        skuId: widget.sku['id'] as String,
        type: type,
        quantity: result['quantity'] as double,
        reason: result['reason'] as String?,
      );
      _changed = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stock ${type == 'IN' ? 'in' : 'out'} recorded.')),
        );
      }
      await _loadHistory();
    } on OfflineQueuedException {
      // Queued — the history list won't reflect it until sync, so skip reloading.
      _changed = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved offline — will sync when back online')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _shareBarcode() async {
    try {
      final boundary = _barcodeKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final code = widget.sku['code'] as String;
      await shareExportedFile(bytes, '$code.png');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _barcodeSection() {
    final code = widget.sku['code'] as String;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Barcode', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ToggleButtons(
              isSelected: [!_showQr, _showQr],
              onPressed: (i) => setState(() => _showQr = i == 1),
              constraints: const BoxConstraints(minHeight: 28, minWidth: 44),
              children: const [Text('Bars'), Text('QR')],
            ),
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Print / Share',
              onPressed: _shareBarcode,
            ),
          ],
        ),
        Container(
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: RepaintBoundary(
            key: _barcodeKey,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: _showQr
                  ? BarcodeWidget(
                      barcode: Barcode.qrCode(),
                      data: code,
                      width: 160,
                      height: 160,
                      drawText: true,
                    )
                  : BarcodeWidget(
                      barcode: Barcode.code128(),
                      data: code,
                      width: 260,
                      height: 100,
                      drawText: true,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentStock = _history?['sku']?['currentStock'] ?? widget.sku['currentStock'];
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(widget.sku['name'],
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, _changed),
                  ),
                ],
              ),
              Text('${widget.sku['code']} · $currentStock ${widget.sku['unit']}',
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              if (widget.allowIn || widget.allowOut)
                Row(
                  children: [
                    if (widget.allowIn)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _move('IN'),
                          icon: const Icon(Icons.arrow_downward),
                          label: const Text('Stock IN'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    if (widget.allowIn && widget.allowOut) const SizedBox(width: 12),
                    if (widget.allowOut)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _move('OUT'),
                          icon: const Icon(Icons.arrow_upward),
                          label: const Text('Stock OUT'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                  ],
                ),
              if (widget.allowIn || widget.allowOut) const SizedBox(height: 20),
              _barcodeSection(),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('History', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _historyList(scrollController),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _historyList(ScrollController scrollController) {
    final movements = (_history?['movements'] as List?) ?? [];
    if (movements.isEmpty) return const Center(child: Text('No movements yet'));
    return ListView.builder(
      controller: scrollController,
      itemCount: movements.length,
      itemBuilder: (_, i) {
        final m = movements[i] as Map;
        final type = m['type'] as String;
        final color = type == 'IN' ? Colors.green : (type == 'OUT' ? Colors.red : Colors.blueGrey);
        final sign = type == 'OUT' ? '-' : '+';
        return ListTile(
          dense: true,
          leading: Icon(
            type == 'IN' ? Icons.arrow_downward : (type == 'OUT' ? Icons.arrow_upward : Icons.tune),
            color: color,
          ),
          title: Text('$sign${m['quantity']} ${widget.sku['unit']} · ${m['doneByName']}'),
          subtitle: Text(
              '${m['reason'] ?? '—'} · ${DateTime.parse(m['createdAt'] as String).toLocal()}'),
          trailing: Text('Bal: ${m['balance']}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        );
      },
    );
  }
}

// ---------------- MOVEMENT ENTRY ----------------
class _MovementSheet extends StatefulWidget {
  final String type;
  final String unit;
  const _MovementSheet({required this.type, required this.unit});
  @override
  State<_MovementSheet> createState() => _MovementSheetState();
}

class _MovementSheetState extends State<_MovementSheet> {
  final _quantity = TextEditingController();
  final _reason = TextEditingController();

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
          Text(widget.type == 'IN' ? 'Stock IN' : 'Stock OUT',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _quantity,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: 'Quantity (${widget.unit})', border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            decoration: InputDecoration(
              labelText: widget.type == 'IN' ? 'Source (optional)' : 'Reason (optional)',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final q = double.tryParse(_quantity.text.trim());
              if (q == null || q <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a valid quantity')),
                );
                return;
              }
              Navigator.pop(context, {'quantity': q, 'reason': _reason.text.trim()});
            },
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}
