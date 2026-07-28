import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'api.dart';
import 'contact_actions.dart';
import 'order_history.dart';
import 'theme/app_theme.dart';
import 'time_format.dart';
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

// One person's worth of stuck items — items sharing the same whoId (or
// grouped together as "Unassigned" when whoId is null, e.g. a stage with no
// responsible person set).
class _PersonGroup {
  final String? whoId;
  final String who;
  final List<dynamic> items;
  _PersonGroup(this.whoId, this.who, this.items);

  int get count => items.length;

  String get worstSeverity {
    if (items.any((i) => i['severity'] == 'HIGH')) return 'HIGH';
    return 'MEDIUM';
  }
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
      if (!mounted) return;
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

    // LEVEL 1 — people, not items. Sorted most-stuck first.
    final byPerson = <String, _PersonGroup>{};
    for (final item in _items) {
      final whoId = item['whoId'] as String?;
      final key = whoId ?? '__unassigned__';
      byPerson.putIfAbsent(key, () => _PersonGroup(whoId, item['who'] as String, [])).items.add(item);
    }
    final people = byPerson.values.toList()..sort((a, b) => b.count.compareTo(a.count));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: people.length,
        itemBuilder: (_, i) {
          final group = people[i];
          return StaggeredListItem(
            index: i,
            child: _PersonSummaryRow(group: group, onTap: () => _openPerson(group)),
          );
        },
      ),
    );
  }

  Future<void> _openPerson(_PersonGroup group) async {
    final moduleToNavigate = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _PersonStuckScreen(group: group, phone: _phoneById[group.whoId]),
      ),
    );
    if (moduleToNavigate != null) widget.onNavigateToModule(moduleToNavigate);
  }
}

class _PersonSummaryRow extends StatelessWidget {
  final _PersonGroup group;
  final VoidCallback onTap;

  const _PersonSummaryRow({required this.group, required this.onTap});

  Color _severityColor(BuildContext context) {
    final semantic = AppColors.of(context);
    return group.worstSeverity == 'HIGH' ? semantic.danger : semantic.warning;
  }

  Color _onSeverityColor(BuildContext context) {
    final semantic = AppColors.of(context);
    return group.worstSeverity == 'HIGH' ? semantic.onDanger : semantic.onWarning;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = _severityColor(context);
    final initial = group.who.isNotEmpty ? group.who[0].toUpperCase() : '?';

    return Card(
      color: color.withValues(alpha: 0.06),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color,
          child: Text(initial, style: TextStyle(color: _onSeverityColor(context), fontWeight: FontWeight.bold)),
        ),
        title: Text(group.who, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(l10n.stuckCountForPerson(group.count)),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

// LEVEL 2 — one person's stuck items, grouped by module same as the old
// flat view was. Non-FMS rows pop back to the person list with the target
// module, which StuckScreen relays to onNavigateToModule (a sibling tab);
// FMS rows push the order's history directly, same as before.
class _PersonStuckScreen extends StatelessWidget {
  final _PersonGroup group;
  final String? phone;

  const _PersonStuckScreen({required this.group, required this.phone});

  static const _moduleOrder = ['TASKS', 'CHECKLISTS', 'FMS', 'INVENTORY'];

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

  void _openItem(BuildContext context, Map item) {
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
    Navigator.pop(context, module);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = <String, List<dynamic>>{};
    for (final item in group.items) {
      groups.putIfAbsent(item['module'] as String, () => []).add(item);
    }
    final orderedModules = _moduleOrder.where(groups.containsKey).toList();

    return Scaffold(
      appBar: AppBar(title: Text(group.who)),
      body: ListView.builder(
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
                    Icon(_moduleIcon(module), size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(_moduleLabel(l10n, module),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(width: 6),
                    Text('(${items.length})',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
                  ],
                ),
              ),
              ...items.indexed.map((entry) => StaggeredListItem(
                    index: entry.$1,
                    child: _StuckRow(
                      item: entry.$2,
                      phone: phone,
                      onTap: () => _openItem(context, entry.$2),
                    ),
                  )),
            ],
          );
        },
      ),
    );
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

  Color _onSeverityColor(BuildContext context) {
    final semantic = AppColors.of(context);
    switch (item['severity']) {
      case 'HIGH': return semantic.onDanger;
      case 'MEDIUM': return semantic.onWarning;
      default: return semantic.onWarning;
    }
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
              style: TextStyle(color: _onSeverityColor(context), fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        title: Text(item['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('$who · stuck for ${formatDurationMins(stuckForMins)}'),
        trailing: ContactButtons(
          phone: phone,
          message: 'Hi $who, checking on: ${item['title']} (pending since ${formatDurationMins(stuckForMins)}).',
        ),
      ),
    );
  }
}
