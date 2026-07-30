import 'package:flutter/material.dart';
import 'api.dart';
import 'theme/app_theme.dart';
import 'l10n/gen/app_localizations.dart';

const _kAiProviders = ['OPENAI', 'ANTHROPIC', 'GEMINI'];
const _kAiProviderLabels = {'OPENAI': 'OpenAI', 'ANTHROPIC': 'Anthropic', 'GEMINI': 'Gemini'};
// Mirrors backend/src/lib/ai/providers.ts DEFAULT_MODEL — just a pre-fill
// convenience here, the backend is the source of truth if left blank.
const _kAiDefaultModels = {
  'OPENAI': 'gpt-4.1-mini',
  'ANTHROPIC': 'claude-haiku-4-5-20251001',
  'GEMINI': 'gemini-2.5-flash',
};

// Per-user AI provider setup — any role (owner/manager/employee) brings
// their own key. Reached from Profile. The key itself is never round-
// tripped back from the server after saving; only provider+model+"is a key
// set" comes back, so this screen shows a masked status once configured.
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});
  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  bool _loading = true;
  bool _configured = false;
  String? _savedProvider;
  String? _savedModel;
  bool _editing = false;

  String _provider = 'OPENAI';
  final _apiKey = TextEditingController();
  final _model = TextEditingController();
  bool _obscureKey = true;
  bool _testing = false;
  bool _saving = false;
  String? _testResult;
  bool? _testOk;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final status = await Api.aiConfigStatus();
      if (!mounted) return;
      setState(() {
        _configured = status['configured'] == true;
        _savedProvider = status['provider'] as String?;
        _savedModel = status['model'] as String?;
        _editing = !_configured;
        if (_savedProvider != null) _provider = _savedProvider!;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _test() async {
    setState(() { _testing = true; _testResult = null; _testOk = null; });
    try {
      await Api.aiTestConnection(provider: _provider, apiKey: _apiKey.text.trim(), model: _model.text.trim());
      if (!mounted) return;
      setState(() { _testOk = true; _testResult = AppLocalizations.of(context).aiConnectionSuccessful; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _testOk = false; _testResult = e.toString().replaceAll('Exception: ', ''); });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Api.aiSaveConfig(provider: _provider, apiKey: _apiKey.text.trim(), model: _model.text.trim());
      _apiKey.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    try {
      await Api.aiDeleteConfig();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).aiRemovedStatus)),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiAssistantTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(l10n.aiNotConfiguredHint, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 20),
                if (_configured && !_editing) _statusCard(l10n) else _form(l10n),
              ],
            ),
    );
  }

  Widget _statusCard(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.smart_toy_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(_kAiProviderLabels[_savedProvider] ?? _savedProvider ?? '', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            if (_savedModel != null && _savedModel!.isNotEmpty)
              Text(_savedModel!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(l10n.aiKeySetStatus, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton(onPressed: () => setState(() => _editing = true), child: Text(l10n.aiChangeAction)),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _remove,
                  style: TextButton.styleFrom(foregroundColor: AppColors.of(context).danger),
                  child: Text(l10n.aiRemoveAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _form(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _provider,
          decoration: InputDecoration(labelText: l10n.aiProviderLabel, border: const OutlineInputBorder()),
          items: [for (final p in _kAiProviders) DropdownMenuItem(value: p, child: Text(_kAiProviderLabels[p]!))],
          onChanged: (v) {
            if (v == null) return;
            setState(() { _provider = v; _testResult = null; });
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _apiKey,
          obscureText: _obscureKey,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l10n.aiApiKeyLabel,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscureKey = !_obscureKey),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _model,
          decoration: InputDecoration(
            labelText: l10n.aiModelLabel,
            hintText: _kAiDefaultModels[_provider],
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        if (_testResult != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _testResult!,
              style: TextStyle(color: _testOk == true ? AppColors.of(context).success : AppColors.of(context).danger),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: (_testing || _apiKey.text.trim().isEmpty) ? null : _test,
                child: _testing
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l10n.aiTestConnectionAction),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: (_saving || _apiKey.text.trim().isEmpty) ? null : _save,
                child: _saving
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l10n.aiSaveAction),
              ),
            ),
          ],
        ),
        if (_configured) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: () => setState(() => _editing = false), child: const Text('Cancel')),
        ],
      ],
    );
  }
}
