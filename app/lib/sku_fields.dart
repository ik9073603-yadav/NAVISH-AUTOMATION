import 'package:flutter/material.dart';
import 'api.dart';
import 'l10n/gen/app_localizations.dart';

// Owner/Manager only — lets each company decide what extra attributes its
// SKUs track (color, size, batch, expiry...) beyond the fixed core fields.
// Reached from the Inventory summary card (owner/manager only, same gate).
class SkuFieldsScreen extends StatefulWidget {
  const SkuFieldsScreen({super.key});
  @override
  State<SkuFieldsScreen> createState() => _SkuFieldsScreenState();
}

class _SkuFieldsScreenState extends State<SkuFieldsScreen> {
  List<dynamic> _fields = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final fields = await Api.skuFields();
      if (mounted) setState(() => _fields = fields);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addOrEdit({Map<String, dynamic>? existing}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _SkuFieldDialog(existing: existing),
    );
    if (result == null) return;
    try {
      if (existing == null) {
        await Api.createSkuField(
          label: result['label'] as String,
          type: result['type'] as String,
          required: result['required'] as bool,
          options: result['options'] as String?,
        );
      } else {
        await Api.updateSkuField(
          existing['id'] as String,
          label: result['label'] as String,
          type: result['type'] as String,
          required: result['required'] as bool,
          options: (result['options'] as String?) ?? '',
        );
      }
      await _load();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _delete(Map<String, dynamic> field) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.deleteFieldTitle),
        content: Text(l10n.deleteFieldConfirm(field['label'] as String)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await Api.deleteSkuField(field['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _fields.removeAt(oldIndex);
      _fields.insert(newIndex, item);
    });
    try {
      await Api.reorderSkuFields(_fields.map((f) => f['id'] as String).toList());
    } catch (e) {
      if (mounted) showApiError(context, e);
      await _load(); // resync with the server's actual order on failure
    }
  }

  String _typeLabel(AppLocalizations l10n, String type) => switch (type) {
        'TEXT' => l10n.fieldTypeText,
        'NUMBER' => l10n.fieldTypeNumber,
        'DROPDOWN' => l10n.fieldTypeDropdown,
        'DATE' => l10n.fieldTypeDate,
        'YESNO' => l10n.fieldTypeYesNo,
        _ => type,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.customizeSkuFields)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _fields.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l10n.noCustomFieldsYet, textAlign: TextAlign.center),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                  itemCount: _fields.length,
                  onReorder: _reorder,
                  itemBuilder: (context, i) {
                    final f = _fields[i] as Map<String, dynamic>;
                    return Card(
                      key: ValueKey(f['id']),
                      child: ListTile(
                        leading: const Icon(Icons.drag_indicator),
                        title: Text(f['label'] as String),
                        subtitle: Text(
                          f['required'] == true
                              ? '${_typeLabel(l10n, f['type'] as String)} · ${l10n.requiredField}'
                              : _typeLabel(l10n, f['type'] as String),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => _addOrEdit(existing: f),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 20),
                              onPressed: () => _delete(f),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add),
        label: Text(l10n.addField),
      ),
    );
  }
}

// ---------------- ADD/EDIT FIELD DIALOG ----------------
// PHOTO is a valid FieldType on the backend (reusing FMS's enum) but isn't
// offered here — a SKU already has its own dedicated photo (imageUrl).
class _SkuFieldDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _SkuFieldDialog({this.existing});
  @override
  State<_SkuFieldDialog> createState() => _SkuFieldDialogState();
}

class _SkuFieldDialogState extends State<_SkuFieldDialog> {
  final _label = TextEditingController();
  final _options = TextEditingController();
  String _type = 'TEXT';
  bool _required = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _label.text = existing['label'] as String? ?? '';
      _options.text = existing['options'] as String? ?? '';
      _type = existing['type'] as String? ?? 'TEXT';
      _required = existing['required'] as bool? ?? false;
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _options.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? l10n.editField : l10n.addField),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _label,
              decoration: InputDecoration(labelText: l10n.fieldLabel),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: InputDecoration(labelText: l10n.fieldTypeLabel),
              items: [
                DropdownMenuItem(value: 'TEXT', child: Text(l10n.fieldTypeText)),
                DropdownMenuItem(value: 'NUMBER', child: Text(l10n.fieldTypeNumber)),
                DropdownMenuItem(value: 'DROPDOWN', child: Text(l10n.fieldTypeDropdown)),
                DropdownMenuItem(value: 'DATE', child: Text(l10n.fieldTypeDate)),
                DropdownMenuItem(value: 'YESNO', child: Text(l10n.fieldTypeYesNo)),
              ],
              onChanged: (v) => setState(() => _type = v!),
            ),
            if (_type == 'DROPDOWN') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _options,
                decoration: InputDecoration(labelText: l10n.fieldOptionsHint),
              ),
            ],
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.requiredField),
              value: _required,
              onChanged: (v) => setState(() => _required = v ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: () {
            if (_label.text.trim().isEmpty) return;
            Navigator.pop(context, {
              'label': _label.text.trim(),
              'type': _type,
              'required': _required,
              'options': _type == 'DROPDOWN' ? _options.text.trim() : '',
            });
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
