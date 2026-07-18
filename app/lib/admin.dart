import 'package:flutter/material.dart';
import 'api.dart';

// Cross-org platform view. Only ever pushed onto the nav for accounts where
// isSuperAdmin is true (checked in main.dart) — regular users never see this.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
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
      setState(() { _overview = overview; _orgs = orgs; });
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
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
            style: enabling ? null : FilledButton.styleFrom(backgroundColor: Colors.red),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Navish Admin')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _overviewCard(),
                      const SizedBox(height: 16),
                      const Text('Companies', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      ..._orgs.map(_orgCard),
                    ],
                  ),
                ),
    );
  }

  Widget _overviewCard() {
    final byRole = (_overview['activeAccountsByRole'] as Map<String, dynamic>? ?? {});
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _stat('Companies', '${_overview['totalCompanies'] ?? 0}'),
            _stat('Active last 7d', '${_overview['orgsActiveLast7Days'] ?? 0}'),
            _stat('Total tasks', '${_overview['totalTasks'] ?? 0}'),
            _stat('Owners', '${byRole['OWNER'] ?? 0}'),
            _stat('Managers', '${byRole['MANAGER'] ?? 0}'),
            _stat('Employees', '${byRole['EMPLOYEE'] ?? 0}'),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _orgCard(dynamic org) {
    final enabled = org['enabled'] as bool;
    final activeRecently = org['activeRecently'] as bool;
    return Card(
      child: ListTile(
        title: Text(org['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${org['accountCount']} accounts · ${org['taskCount']} tasks · '
          '${activeRecently ? "active recently" : "quiet 7d+"}'
          '${enabled ? "" : " · SUSPENDED"}',
          style: TextStyle(color: enabled ? null : Colors.red),
        ),
        trailing: Switch(
          value: enabled,
          onChanged: (_) => _toggle(org),
          activeTrackColor: Colors.green.shade200,
        ),
      ),
    );
  }
}
