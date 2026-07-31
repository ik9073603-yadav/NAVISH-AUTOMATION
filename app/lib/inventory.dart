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
import 'sku_fields.dart';
import 'barcode_scanner.dart';
import 'l10n/gen/app_localizations.dart';

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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final skusFuture = Api.skus(search: _search.text.trim(), status: _statusFilter);
      final summaryFuture = _canManage ? Api.inventorySummary() : Future.value(null);
      final results = await Future.wait([skusFuture, summaryFuture]);
      if (!mounted) return;
      setState(() { _skus = results[0] as List<dynamic>; _summary = results[1] as Map<String, dynamic>?; });
    } catch (e) {
      if (mounted) {
        showApiError(context, e);
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
    final theme = Theme.of(context);
    final semantic = AppColors.of(context);
    final lowCount = s['lowStockCount'] as int;
    final deadCount = s['deadStockCount'] as int;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('INVENTORY SUMMARY', style: AppTheme.eyebrow(context)),
            ),
            IconButton(
              icon: const Icon(Icons.tune, size: 20),
              tooltip: AppLocalizations.of(context).customizeFieldsTooltip,
              onPressed: _openSkuFields,
            ),
            IconButton(
              icon: const Icon(Icons.ios_share, size: 20),
              tooltip: 'Export movements',
              onPressed: _exportMovements,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _statBlock(
                '₹${(s['totalStockValue'] as num).toStringAsFixed(0)}',
                'Stock value',
                background: theme.colorScheme.primaryContainer,
                foreground: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statBlock(
                '$lowCount',
                'Low stock',
                background: lowCount > 0 ? semantic.warningContainer : semantic.successContainer,
                foreground: lowCount > 0 ? semantic.onWarningContainer : semantic.onSuccessContainer,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statBlock(
                '$deadCount',
                '₹${(s['deadStockValue'] as num).toStringAsFixed(0)} dead',
                background: deadCount > 0 ? semantic.dangerContainer : semantic.successContainer,
                foreground: deadCount > 0 ? semantic.onDangerContainer : semantic.onSuccessContainer,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Color-blocked stat card — a full saturated-pastel fill (not a light
  // tint), matching the design system's featured-metric treatment.
  Widget _statBlock(String value, String label, {required Color background, required Color foreground}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: AppTheme.tabularFigures(Theme.of(context).textTheme.headlineSmall)
                  .copyWith(color: foreground, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 11, color: foreground.withValues(alpha: 0.85), fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return TextField(
      controller: _search,
      decoration: InputDecoration(
        hintText: 'Search by name or code',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: IconButton(
          icon: const Icon(Icons.qr_code_scanner),
          tooltip: AppLocalizations.of(context).scanBarcodeTooltip,
          onPressed: _scanBarcode,
        ),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onSubmitted: (_) => _load(),
    );
  }

  Future<void> _openSkuFields() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SkuFieldsScreen()));
    _load(); // field defs may have changed what the Add/Edit form and detail view show
  }

  // Reusable by both the list and (via _SkuDetailSheet) the movement flow —
  // exact-code lookup, open the matching SKU's detail, or offer to create a
  // new one with this code (owner/manager only, since creating a SKU is).
  Future<void> _scanBarcode() async {
    final code = await Navigator.push<String>(
      context, MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));
    if (code == null || code.isEmpty || !mounted) return;

    final l10n = AppLocalizations.of(context);
    try {
      final match = await Api.skuByCode(code);
      if (!mounted) return;
      if (match != null) {
        await _openSkuDetail(match);
        return;
      }
      if (!_canManage) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.skuNotFoundForCode(code))));
        return;
      }
      final create = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(l10n.noSkuFoundTitle),
          content: Text(l10n.createSkuWithCodeQuestion(code)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.create)),
          ],
        ),
      );
      if (create == true && mounted) {
        final ok = await showAdaptiveSheet<bool>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _AddSkuSheet(initialCode: code),
        );
        if (ok == true) _load();
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
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
    final (badgeBg, badgeFg) = switch (liquidClass) {
      'LIQUID' => (semantic.successContainer, semantic.onSuccessContainer),
      'SLOW' => (semantic.warningContainer, semantic.onWarningContainer),
      _ => (semantic.dangerContainer, semantic.onDangerContainer), // DEAD
    };

    return Card(
      child: ListTile(
        onTap: () => _openSkuDetail(sku),
        title: Text(sku['name'], style: Theme.of(context).textTheme.titleSmall),
        subtitle: Text(
          '${sku['code']} · ${sku['currentStock']} ${sku['unit']}',
          style: TextStyle(
            color: isLow ? semantic.danger : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: isLow ? FontWeight.w600 : null,
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(AppRadius.pill)),
          child: Text(liquidClass,
              style: TextStyle(color: badgeFg, fontWeight: FontWeight.bold, fontSize: 11)),
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
        showApiError(context, e);
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
        canManage: _canManage,
      ),
    );
    if (changed == true) _load();
  }
}

// ---------------- ADD/EDIT SKU ----------------
// One form for both: existingSku non-null means edit. Renders the org's
// custom SKU fields (see sku_fields.dart) after the core fields — defaults
// (no custom fields defined) just show nothing extra.
class _AddSkuSheet extends StatefulWidget {
  final Map<String, dynamic>? existingSku;
  final String? initialCode; // prefill for the scan-to-create flow
  const _AddSkuSheet({this.existingSku, this.initialCode});
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
  List<dynamic> _fieldDefs = [];
  final Map<String, dynamic> _customValues = {};
  bool _loadingFields = true;
  bool _saving = false;

  bool get _isEdit => widget.existingSku != null;

  @override
  void initState() {
    super.initState();
    final sku = widget.existingSku;
    if (sku != null) {
      _name.text = sku['name'] as String? ?? '';
      _code.text = sku['code'] as String? ?? '';
      _category.text = sku['category'] as String? ?? '';
      _unit.text = sku['unit'] as String? ?? 'pcs';
      _minStock.text = sku['minStock'] != null ? '${sku['minStock']}' : '';
      _maxStock.text = sku['maxStock'] != null ? '${sku['maxStock']}' : '';
      _unitCost.text = sku['unitCost'] != null ? '${sku['unitCost']}' : '';
      final existingCustom = sku['customData'];
      if (existingCustom is Map) _customValues.addAll(Map<String, dynamic>.from(existingCustom));
    } else if (widget.initialCode != null) {
      _code.text = widget.initialCode!;
    }
    _loadFields();
  }

  Future<void> _loadFields() async {
    try {
      final fields = await Api.skuFields();
      if (mounted) setState(() { _fieldDefs = fields; _loadingFields = false; });
    } catch (e) {
      if (mounted) {
        showApiError(context, e);
        setState(() => _loadingFields = false);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _category.dispose();
    _unit.dispose();
    _openingStock.dispose();
    _minStock.dispose();
    _maxStock.dispose();
    _unitCost.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }
    for (final f in _fieldDefs) {
      final label = f['label'] as String;
      if (f['required'] != true) continue;
      final v = _customValues[label];
      if (v == null || (v is String && v.trim().isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.requiredField}: $label')),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await Api.updateSku(widget.existingSku!['id'] as String, {
          'name': _name.text.trim(),
          'code': _code.text.trim(),
          'category': _category.text.trim().isEmpty ? null : _category.text.trim(),
          'unit': _unit.text.trim().isEmpty ? 'pcs' : _unit.text.trim(),
          'minStock': double.tryParse(_minStock.text.trim()),
          'maxStock': double.tryParse(_maxStock.text.trim()),
          'unitCost': double.tryParse(_unitCost.text.trim()),
          'customData': _customValues,
        });
      } else {
        await Api.createSku(
          name: _name.text.trim(),
          code: _code.text.trim().isEmpty ? null : _code.text.trim(),
          category: _category.text.trim().isEmpty ? null : _category.text.trim(),
          unit: _unit.text.trim().isEmpty ? 'pcs' : _unit.text.trim(),
          currentStock: double.tryParse(_openingStock.text.trim()),
          minStock: double.tryParse(_minStock.text.trim()),
          maxStock: double.tryParse(_maxStock.text.trim()),
          unitCost: double.tryParse(_unitCost.text.trim()),
          customData: _customValues,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showApiError(context, e);
        setState(() => _saving = false);
      }
    }
  }

  Widget _customFieldInput(Map<String, dynamic> f) {
    final label = f['label'] as String;
    final type = f['type'] as String;
    final required = f['required'] == true;
    final displayLabel = required ? '$label *' : label;

    switch (type) {
      case 'YESNO':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(displayLabel),
          value: _customValues[label] == true,
          onChanged: (v) => setState(() => _customValues[label] = v),
        );
      case 'DATE':
        final current = _customValues[label] as String?;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: Theme.of(context).colorScheme.outline),
          ),
          title: Text(displayLabel),
          subtitle: Text(current ?? '—'),
          trailing: const Icon(Icons.calendar_today, size: 18),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: current != null ? (DateTime.tryParse(current) ?? DateTime.now()) : DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              setState(() => _customValues[label] = picked.toIso8601String().split('T').first);
            }
          },
        );
      case 'DROPDOWN':
        final opts = ((f['options'] as String?) ?? '')
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        final current = _customValues[label] as String?;
        return DropdownButtonFormField<String>(
          initialValue: opts.contains(current) ? current : null,
          decoration: InputDecoration(labelText: displayLabel, border: const OutlineInputBorder()),
          items: opts.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) => setState(() => _customValues[label] = v),
        );
      case 'NUMBER':
        return TextFormField(
          initialValue: _customValues[label]?.toString() ?? '',
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: displayLabel, border: const OutlineInputBorder()),
          onChanged: (v) => _customValues[label] = num.tryParse(v),
        );
      default: // TEXT (PHOTO isn't offered as a custom-field type — falls back to text)
        return TextFormField(
          initialValue: _customValues[label]?.toString() ?? '',
          decoration: InputDecoration(labelText: displayLabel, border: const OutlineInputBorder()),
          onChanged: (v) => _customValues[label] = v,
        );
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
            Text(_isEdit ? l10n.editSku : 'Add SKU', style: Theme.of(context).textTheme.headlineSmall),
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
            if (!_isEdit) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _openingStock,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Opening stock (optional, default 0)', border: OutlineInputBorder()),
              ),
            ],
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
            Text('Leave min/max blank for no alert on that SKU.',
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            TextField(
              controller: _unitCost,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Unit cost ₹ (optional)', border: OutlineInputBorder()),
            ),
            if (_fieldDefs.isNotEmpty) ...[
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(l10n.detailsSection, style: AppTheme.eyebrow(context)),
              ),
              const SizedBox(height: 8),
              for (final f in _fieldDefs) ...[
                _customFieldInput(f as Map<String, dynamic>),
                const SizedBox(height: 12),
              ],
            ],
            const SizedBox(height: 4),
            FilledButton(
              onPressed: (_saving || _loadingFields) ? null : _save,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text(_saving ? 'Saving...' : (_isEdit ? l10n.save : 'Add SKU')),
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
  final bool canManage;
  const _SkuDetailSheet({required this.sku, required this.allowIn, required this.allowOut, required this.canManage});
  @override
  State<_SkuDetailSheet> createState() => _SkuDetailSheetState();
}

class _SkuDetailSheetState extends State<_SkuDetailSheet> {
  Map<String, dynamic>? _history;
  List<dynamic> _fieldDefs = [];
  bool _loading = true;
  bool _changed = false;
  bool _showQr = false;
  final _barcodeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadHistory();
    // Best-effort — if this fails the detail view just shows no custom
    // fields section, no need to block or error-toast over it.
    Api.skuFields().then((f) {
      if (mounted) setState(() => _fieldDefs = f);
    }).catchError((_) {});
  }

  Future<void> _edit() async {
    final ok = await showAdaptiveSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddSkuSheet(existingSku: widget.sku as Map<String, dynamic>),
    );
    // The edit form doesn't return the updated SKU, so rather than showing
    // stale data in this still-open sheet, close it — the list reload the
    // caller already does on a truthy pop picks up the fresh values.
    if (ok == true && mounted) Navigator.pop(context, true);
  }

  String _formatCustomValue(Map<String, dynamic> f, dynamic v) {
    if (f['type'] == 'YESNO') return v == true ? 'Yes' : 'No';
    return '$v';
  }

  Widget _customValuesSection() {
    final l10n = AppLocalizations.of(context);
    final customData = widget.sku['customData'];
    final values = customData is Map ? Map<String, dynamic>.from(customData) : <String, dynamic>{};
    final withValues = _fieldDefs.cast<Map<String, dynamic>>().where((f) {
      final v = values[f['label']];
      return v != null && v != '';
    }).toList();
    if (withValues.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(l10n.detailsSection, style: AppTheme.eyebrow(context)),
        ),
        const SizedBox(height: 6),
        for (final f in withValues)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(f['label'] as String,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
                Text(_formatCustomValue(f, values[f['label']]),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    try {
      final h = await Api.skuHistory(widget.sku['id'] as String);
      if (mounted) setState(() => _history = h);
    } catch (e) {
      if (mounted) showApiError(context, e);
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
      if (mounted) showApiError(context, e);
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
      if (mounted) showApiError(context, e);
    }
  }

  Widget _barcodeSection() {
    final code = widget.sku['code'] as String;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('BARCODE', style: AppTheme.eyebrow(context)),
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
                    child: Text(widget.sku['name'], style: Theme.of(context).textTheme.headlineSmall),
                  ),
                  if (widget.canManage)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: _edit,
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, _changed),
                  ),
                ],
              ),
              Text('${widget.sku['code']} · $currentStock ${widget.sku['unit']}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              _customValuesSection(),
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
                            backgroundColor: AppColors.of(context).success,
                            foregroundColor: AppColors.of(context).onSuccess,
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
                            backgroundColor: AppColors.of(context).danger,
                            foregroundColor: AppColors.of(context).onDanger,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                  ],
                ),
              if (widget.allowIn || widget.allowOut) const SizedBox(height: 20),
              _barcodeSection(),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('HISTORY', style: AppTheme.eyebrow(context)),
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
        final semantic = AppColors.of(context);
        final color = type == 'IN'
            ? semantic.success
            : (type == 'OUT' ? semantic.danger : Theme.of(context).colorScheme.onSurfaceVariant);
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
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
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
          Text(widget.type == 'IN' ? 'Stock IN' : 'Stock OUT',
              style: Theme.of(context).textTheme.headlineSmall),
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
