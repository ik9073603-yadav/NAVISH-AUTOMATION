import 'package:flutter/material.dart';
import 'api.dart';
import 'analytics_flow.dart';
import 'analytics_employee.dart';
import 'analytics_department.dart';
import 'analytics_task.dart';
import 'analytics_inventory.dart';
import 'responsive.dart';
import 'theme/app_theme.dart';
import 'l10n/gen/app_localizations.dart';

// Owner/Manager only. First screen is a hub of five analysis areas — each
// card shows a cheap one-line summary (reusing the same cached, grouped-
// aggregate endpoints the detail screens use, just with a fixed "this week"
// window). Tapping a card opens that area's full, date-filterable analysis.
// This hub is the ONLY place Flow analytics lives — the FMS module tab
// keeps only its operational views (see fms.dart).
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _loading = true;
  String? _error;

  String _flowSummary = '';
  String _employeeSummary = '';
  String _departmentSummary = '';
  String _taskSummary = '';
  String _inventorySummary = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    try {
      final results = await Future.wait([
        Api.fmsAnalyticsSummary(),
        Api.analyticsEmployees(weekAgo, now),
        Api.analyticsDepartments(weekAgo, now),
        Api.analyticsDelegation(weekAgo, now),
        Api.analyticsChecklists(weekAgo, now),
        Api.analyticsInventory(weekAgo, now),
      ]);

      final flow = results[0] as Map<String, dynamic>;
      final employees = results[1] as List<dynamic>;
      final departments = results[2] as List<dynamic>;
      final delegation = results[3] as Map<String, dynamic>;
      final checklists = results[4] as Map<String, dynamic>;
      final inventory = results[5] as Map<String, dynamic>;

      final delegationTotals = delegation['totals'] as Map<String, dynamic>? ?? {};
      final checklistTotals = checklists['totals'] as Map<String, dynamic>? ?? {};
      final lowStockCount = inventory['lowStockCount'] as int? ?? 0;

      setState(() {
        _flowSummary = '${flow['totalOrders'] ?? 0} orders · ${flow['delayed'] ?? 0} delayed';
        _employeeSummary = employees.isEmpty
            ? 'No active employees'
            : '${employees.length} active · ${_avgOnTime(employees)}% avg on-time';
        _departmentSummary = departments.isEmpty
            ? 'No departments yet'
            : '${departments.length} group(s) · ${_avgDeptOnTime(departments)}% avg on-time';
        _taskSummary = '${delegationTotals['completionPct'] ?? 0}% delegation · ${checklistTotals['compliancePct'] ?? 0}% checklist';
        _inventorySummary = lowStockCount > 0
            ? '$lowStockCount low-stock alert${lowStockCount == 1 ? '' : 's'}'
            : 'Stock levels healthy';
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _avgOnTime(List<dynamic> employees) {
    final withCompleted = employees.where((e) => (e['completed'] as int? ?? 0) > 0).toList();
    if (withCompleted.isEmpty) return 0;
    final sum = withCompleted.fold<int>(0, (a, e) => a + (e['onTimePct'] as int? ?? 0));
    return (sum / withCompleted.length).round();
  }

  int _avgDeptOnTime(List<dynamic> departments) {
    final withCompleted = departments.where((d) => (d['completed'] as int? ?? 0) > 0).toList();
    if (withCompleted.isEmpty) return 0;
    final sum = withCompleted.fold<int>(0, (a, d) => a + (d['onTimePct'] as int? ?? 0));
    return (sum / withCompleted.length).round();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navAnalytics)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, style: TextStyle(color: AppColors.of(context).danger)),
                    ),
                  )
                : MaxWidthCenter(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        GridView.count(
                          crossAxisCount: switch (screenSizeOf(context)) {
                            ScreenSize.compact => 1,
                            ScreenSize.medium => 2,
                            ScreenSize.expanded => 2,
                          },
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 2.6,
                          children: [
                            _AnalyticsCard(
                              icon: Icons.account_tree_outlined,
                              title: l10n.flowAnalysisTitle,
                              summary: _flowSummary,
                              color: AppColors.of(context).info,
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FlowAnalysisScreen())),
                            ),
                            _AnalyticsCard(
                              icon: Icons.people_outline,
                              title: l10n.employeeAnalysisTitle,
                              summary: _employeeSummary,
                              color: AppColors.of(context).success,
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployeeAnalysisScreen())),
                            ),
                            _AnalyticsCard(
                              icon: Icons.apartment_outlined,
                              title: l10n.departmentAnalysisTitle,
                              summary: _departmentSummary,
                              color: Theme.of(context).colorScheme.tertiary,
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DepartmentAnalysisScreen())),
                            ),
                            _AnalyticsCard(
                              icon: Icons.fact_check_outlined,
                              title: l10n.taskAnalysisTitle,
                              summary: _taskSummary,
                              color: AppColors.of(context).warning,
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskAnalysisScreen())),
                            ),
                            _AnalyticsCard(
                              icon: Icons.inventory_2_outlined,
                              title: l10n.inventoryAnalysisTitle,
                              summary: _inventorySummary,
                              color: Theme.of(context).colorScheme.primary,
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryAnalysisScreen())),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String summary;
  final Color color;
  final VoidCallback onTap;

  const _AnalyticsCard({
    required this.icon,
    required this.title,
    required this.summary,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A real color block, not a faint tint — each of the 5 cards carries its
    // own accent identity (matches the Home hub's per-module tile language).
    final background = Color.alphaBlend(color.withValues(alpha: 0.16), theme.colorScheme.surface);
    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      summary,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
