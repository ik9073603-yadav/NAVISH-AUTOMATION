import 'package:flutter/material.dart';
import 'api.dart';
import 'theme/app_theme.dart';
import 'widgets/motion.dart';

// The entire experience for an isSuperAdmin account (main.dart routes
// straight here, bypassing the normal company Home/modules UI — a platform
// operator doesn't belong to any company). onLogout is provided when this
// is the root view, so there's a way out; null when (historically) pushed
// on top of something else that already has its own logout path.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, this.onLogout});
  final Future<void> Function()? onLogout;
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _overview = {};
  List<dynamic> _orgs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final overview = await Api.adminOverview();
      final orgs = await Api.adminOrgs();
      if (!mounted) return;
      setState(() { _overview = overview; _orgs = orgs; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> org) async {
    final enabling = !(org['enabled'] as bool);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(enabling ? 'Reactivate company?' : 'Suspend company?'),
        content: Text(
          enabling
              ? '${org['name']} will be able to log in again.'
              : '${org['name']} will be blocked from logging in until reactivated.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: enabling
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: AppColors.of(context).danger,
                    foregroundColor: AppColors.of(context).onDanger,
                  ),
            child: Text(enabling ? 'Reactivate' : 'Suspend'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await Api.adminToggleOrg(org['id'] as String);
      _load();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navish Admin'),
        actions: [
          if (widget.onLogout != null)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Log out',
              onPressed: widget.onLogout,
            ),
        ],
      ),
      body: _loading
          ? const ShimmerSkeletonList()
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: AppColors.of(context).danger)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _heroCard(),
                      const SizedBox(height: 12),
                      _statRow(),
                      const SizedBox(height: 20),
                      Text('COMPANIES', style: AppTheme.eyebrow(context)),
                      const SizedBox(height: 8),
                      ..._orgs.map(_orgCard),
                    ],
                  ),
                ),
    );
  }

  // The one dark "hero" card — total companies is the single number a
  // platform operator cares about first, same anchor treatment as the
  // Home dashboard's Health Score.
  Widget _heroCard() {
    final theme = Theme.of(context);
    final accents = AppAccents.of(context);
    return Container(
      decoration: BoxDecoration(color: accents.hero, borderRadius: BorderRadius.circular(AppRadius.lg)),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PLATFORM', style: AppTheme.eyebrow(context).copyWith(color: accents.onHero.withValues(alpha: 0.6))),
                const SizedBox(height: 6),
                Text('${_overview['totalCompanies'] ?? 0}',
                    style: AppTheme.tabularFigures(theme.textTheme.displayLarge).copyWith(color: accents.onHero, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('companies', style: theme.textTheme.bodySmall?.copyWith(color: accents.onHero.withValues(alpha: 0.75))),
              ],
            ),
          ),
          Icon(Icons.apartment, color: accents.onHero.withValues(alpha: 0.35), size: 40),
        ],
      ),
    );
  }

  Widget _statRow() {
    final byRole = (_overview['activeAccountsByRole'] as Map<String, dynamic>? ?? {});
    final semantic = AppColors.of(context);
    final accents = AppAccents.of(context);
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.3,
      children: [
        _stat('${_overview['orgsActiveLast7Days'] ?? 0}', 'Active 7d', semantic.successContainer, semantic.onSuccessContainer),
        _stat('${_overview['totalTasks'] ?? 0}', 'Total tasks', semantic.infoContainer, semantic.onInfoContainer),
        _stat('${byRole['OWNER'] ?? 0}', 'Owners', accents.tealContainer, accents.onTealContainer),
        _stat('${byRole['MANAGER'] ?? 0}', 'Managers', accents.magentaContainer, accents.onMagentaContainer),
        _stat('${byRole['EMPLOYEE'] ?? 0}', 'Employees', semantic.warningContainer, semantic.onWarningContainer),
      ],
    );
  }

  Widget _stat(String value, String label, Color background, Color foreground) {
    return Container(
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppRadius.md)),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value,
              style: AppTheme.tabularFigures(Theme.of(context).textTheme.headlineSmall)
                  .copyWith(color: foreground, fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(color: foreground.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _orgCard(dynamic org) {
    final enabled = org['enabled'] as bool;
    final activeRecently = org['activeRecently'] as bool;
    final semantic = AppColors.of(context);
    return Card(
      child: ListTile(
        title: Text(org['name'], style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text('${org['accountCount']} accounts · ${org['taskCount']} tasks · '
            '${activeRecently ? "active recently" : "quiet 7d+"}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!enabled)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: semantic.dangerContainer, borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Text('SUSPENDED',
                    style: TextStyle(color: semantic.onDangerContainer, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              ),
            Switch(value: enabled, onChanged: (_) => _toggle(org)),
          ],
        ),
      ),
    );
  }
}
