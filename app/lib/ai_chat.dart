import 'package:flutter/material.dart';
import 'api.dart';
import 'ai_settings.dart';
import 'ai_usage.dart';
import 'theme/app_theme.dart';
import 'widgets/motion.dart';
import 'l10n/gen/app_localizations.dart';

class _Message {
  final String role; // 'user' | 'assistant'
  final String text;
  const _Message(this.role, this.text);
}

// The AI Assistant chat — handles both business-overview questions and
// app-help questions through the same endpoint (the backend always has
// both the org data snapshot and the app knowledge base available; which
// one a reply leans on is left to the model, not a client-side router).
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});
  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  bool _loading = true;
  bool _configured = false;
  final _messages = <_Message>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _checkConfig();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _checkConfig() async {
    setState(() => _loading = true);
    try {
      final status = await Api.aiConfigStatus();
      if (mounted) setState(() => _configured = status['configured'] == true);
    } catch (_) {
      // Best-effort — treat as not configured, the connect prompt covers it.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(context, sharedAxisRoute(const AiSettingsScreen()));
    _checkConfig();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _send(String text, {String feature = 'ASSIST'}) async {
    if (text.trim().isEmpty || _sending) return;
    final history = [for (final m in _messages) {'role': m.role, 'content': m.text}];
    setState(() {
      _messages.add(_Message('user', text.trim()));
      _sending = true;
    });
    _input.clear();
    _scrollToEnd();
    try {
      final reply = await Api.aiChat(message: text.trim(), history: history, feature: feature);
      if (!mounted) return;
      setState(() => _messages.add(_Message('assistant', reply)));
    } catch (e) {
      if (mounted) setState(() => _messages.add(_Message('assistant', e.toString().replaceAll('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aiAssistantTitle),
        actions: [
          if (_configured)
            IconButton(
              icon: const Icon(Icons.bar_chart_outlined),
              tooltip: l10n.aiUsageTitle,
              onPressed: () => Navigator.push(context, sharedAxisRoute(const AiUsageScreen())),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_configured
              ? _connectPrompt(l10n)
              : _chatBody(l10n),
    );
  }

  Widget _connectPrompt(AppLocalizations l10n) {
    final accents = AppAccents.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: accents.hero,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 40, color: accents.onHero),
              const SizedBox(height: 16),
              Text(l10n.aiChatConnectPrompt,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: accents.onHero, fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 20),
              FilledButton(onPressed: _openSettings, child: Text(l10n.aiChatConnectAction)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chatBody(AppLocalizations l10n) {
    final accents = AppAccents.of(context);
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, size: 36, color: accents.teal),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          icon: const Icon(Icons.insights_outlined),
                          label: Text(l10n.aiBusinessOverviewAction),
                          onPressed: () => _send(l10n.aiBusinessOverviewAction, feature: 'OVERVIEW'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length + (_sending ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= _messages.length) return _typingBubble();
                    return _bubble(_messages[i]);
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (t) => _send(t),
                    decoration: InputDecoration(
                      hintText: l10n.aiChatInputHint,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : () => _send(_input.text),
                  icon: const Icon(Icons.arrow_upward),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bubble(_Message m) {
    final theme = Theme.of(context);
    final accents = AppAccents.of(context);
    final isUser = m.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: isUser ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          // A slim teal edge marks the assistant's own bubbles — a small,
          // consistent signature so the AI feature reads as its own thing
          // rather than borrowing the app's general primary color.
          border: isUser ? null : Border(left: BorderSide(color: accents.teal, width: 3)),
        ),
        child: Text(
          m.text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isUser ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _typingBubble() {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}
