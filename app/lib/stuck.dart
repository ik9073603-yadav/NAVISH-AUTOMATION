import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'api.dart';
import 'contact_actions.dart';
import 'order_history.dart';
import 'theme/app_theme.dart';
import 'widgets/motion.dart';
import 'l10n/gen/app_localizations.dart';

class StuckScreen extends StatefulWidget {
  // Lets the Stuck tab jump to a sibling tab in the owner's bottom nav
  // (Tasks / Checklists / Inventory). FMS rows push OrderHistoryScreen
  // directly instead, since that's a precise per-order deep link.
  final void Function(String module) onNavigateToModule;

  const StuckScreen({super.key, required this.onNavigateToModule});

  @override
  State<StuckScreen> createState() => _StuckScreenState();
}

class _StuckScreenState extends State<StuckScreen> {
  List<dynamic> _items = [];
  Map<String, String?> _phoneById = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([Api.stuckList(), Api.users()]);
      final items = results[0];
      final users = results[1];
      final phoneById = <String, String?>{
        for (final u in users) u['id'] as String: u['phone'] as String?,
      };
      setState(() {
        _items = items;
        _phoneById = phoneById;
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

    if (_items.isEmpty) {
      final reduced = reducedMotion(context);
      final theme = Theme.of(context);
      final l10n = AppLocalizations.of(context);

      Widget title = Text(l10n.nothingStuckTitle, style: theme.textTheme.headlineMedium);
      Widget subtitle = Text(l10n.nothingStuckSubtitle,
          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant));
      if (!reduced) {
        title = title.animate().fadeIn(delay: 300.ms, duration: 400.ms);
        subtitle = subtitle.animate().fadeIn(delay: 420.ms, duration: 400.ms);
      }

      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BreathingCheck(size: 110),
                    const SizedBox(height: 24),
                    title,
                    const SizedBox(height: 6),
                    subtitle,
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final l10n = AppLocalizations.of(context);
    final groups = <String, List<dynamic>>{};
    for (final item in _items) {
      groups.putIfAbsent(item['module'] as String, () => []).add(item);
    }
    const moduleOrder = ['TASKS', 'CHECKLISTS', 'FMS', 'INVENTORY'];
    final orderedModules = moduleOrder.where(groups.containsKey).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: orderedModules.length,
        itemBuilder: (_, i) {
          final module = orderedModules[i];
          final items = groups[module]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                child: Row(
                  children: [
                    Icon(_moduleIcon(module), size: 18, color: Colors.grey.shade700),
                    const SizedBox(width: 6),
                    Text(_moduleLabel(l10n, module),
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                    const SizedBox(width: 6),
                    Text('(${items.length})', style: TextStyle(color: Colors.grey.shade500)),
                  ],
                ),
              ),
              ...items.indexed.map((entry) => StaggeredListItem(
                    index: entry.$1,
                    child: _StuckRow(
                      item: entry.$2,
                      phone: _phoneById[entry.$2['whoId']],
                      onTap: () => _openItem(entry.$2),
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }

  void _openItem(Map item) {
    final module = item['module'] as String;
    if (module == 'FMS') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrderHistoryScreen(
            orderId: item['deepLinkId'] as String,
            orderNumber: (item['title'] as String).split(' — ').first,
          ),
        ),
      );
      return;
    }
    widget.onNavigateToModule(module);
  }

  IconData _moduleIcon(String module) {
    switch (module) {
      case 'TASKS': return Icons.list_alt;
      case 'CHECKLISTS': return Icons.event_repeat;
      case 'FMS': return Icons.account_tree;
      case 'INVENTORY': return Icons.inventory_2;
      default: return Icons.warning;
    }
  }

  String _moduleLabel(AppLocalizations l10n, String module) {
    switch (module) {
      case 'TASKS': return l10n.moduleTasks;
      case 'CHECKLISTS': return l10n.moduleChecklists;
      case 'FMS': return l10n.moduleFlows;
      case 'INVENTORY': return l10n.moduleInventory;
      default: return module;
    }
  }
}

class _StuckRow extends StatelessWidget {
  final Map item;
  final String? phone;
  final VoidCallback onTap;

  const _StuckRow({required this.item, required this.phone, required this.onTap});

  Color _severityColor(BuildContext context) {
    final semantic = AppColors.of(context);
    switch (item['severity']) {
      case 'HIGH': return semantic.danger;
      case 'MEDIUM': return semantic.warning;
      default: return semantic.warning;
    }
  }

  String _duration(int mins) {
    if (mins < 60) return '$mins min';
    if (mins < 1440) return '${(mins / 60).toStringAsFixed(1)} hrs';
    return '${(mins / 1440).toStringAsFixed(1)} days';
  }

  @override
  Widget build(BuildContext context) {
    final who = item['who'] as String;
    final stuckForMins = item['stuckForMins'] as int;
    final color = _severityColor(context);

    return Card(
      color: color.withValues(alpha: 0.06),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color,
          child: Text(item['severity'].toString().substring(0, 1),
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        title: Text(item['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('$who · stuck for ${_duration(stuckForMins)}'),
        trailing: ContactButtons(
          phone: phone,
          message: 'Hi $who, checking on: ${item['title']} (pending since ${_duration(stuckForMins)}).',
        ),
      ),
    );
  }
}
