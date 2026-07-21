import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api.dart';
import 'filters.dart';
import 'order_history.dart';
import 'widgets/cost_of_delay_info.dart';
import 'l10n/gen/app_localizations.dart';

// KPI cards + summary — the "Analytics" segment inside the Flow Monitoring
// System module. Tapping a card opens FlowOrdersListScreen filtered to that
// category. Owner/manager only (gated by the caller).
class FlowAnalyticsView extends StatefulWidget {
  const FlowAnalyticsView({super.key});

  @override
  State<FlowAnalyticsView> createState() => _FlowAnalyticsViewState();
}

class _FlowAnalyticsViewState extends State<FlowAnalyticsView> {
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _costOfDelay;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        Api.fmsAnalyticsSummary(),
        Api.fmsAnalyticsCostOfDelay(),
      ]);
      setState(() {
        _summary = results[0];
        _costOfDelay = results[1];
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openCategory(String category, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FlowOrdersListScreen(category: category, title: title)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));

    final s = _summary!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _kpiCard('Pending', s['pending'] as int, Colors.blue, Icons.hourglass_top,
                  () => _openCategory('PENDING', 'Pending orders')),
              _kpiCard('Completed', s['completed'] as int, Colors.green, Icons.check_circle,
                  () => _openCategory('COMPLETED', 'Completed orders')),
              _kpiCard('Delayed', s['delayed'] as int, Colors.red, Icons.warning,
                  () => _openCategory('DELAYED', 'Delayed orders')),
              _kpiCard('On-time', s['onTime'] as int, Colors.teal, Icons.thumb_up,
                  () => _openCategory('ONTIME', 'On-time orders')),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _summaryTile('${s['totalOrders']}', 'Total orders'),
                  _summaryTile('${s['noSla']}', 'No SLA'),
                  _summaryTile(_avgCycle(s['avgCycleTimeMins'] as int), 'Avg cycle time'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _costOfDelaySection(),
        ],
      ),
    );
  }

  Widget _costOfDelaySection() {
    final c = _costOfDelay;
    if (c == null) return const SizedBox.shrink();

    final total = c['totalRupeesLost'] as num?;
    final missing = c['ordersMissingCostInfo'] as int? ?? 0;
    final mostExpensive = (c['mostExpensiveOrders'] as List?) ?? [];
    final costliestStages = (c['costliestStages'] as List?) ?? [];
    final costliestPeople = (c['costliestPeople'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Cost of Delay', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const CostOfDelayInfoButton(),
          ],
        ),
        const SizedBox(height: 4),
        Card(
          color: Colors.red.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatRupeesOrPrompt(total),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: total == null ? Colors.grey.shade600 : Colors.red.shade700,
                  ),
                ),
                Text(
                  total == null ? 'Set a ₹/hr rate or capture order values to see ₹ lost to delay' : 'Total ₹ lost to delay',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (missing > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$missing delayed order(s) not counted — no rate or order value set',
                    style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (mostExpensive.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Most expensive delayed orders', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ...mostExpensive.take(5).map((o) => _costRow(o['orderNumber'] as String, o['cost'] as num)),
        ],
        if (costliestStages.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Costliest stage', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ...costliestStages.take(3).map((s) => _costRow('${s['stageName']} (${s['flowName']})', s['cost'] as num)),
        ],
        if (costliestPeople.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Costliest person', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ...costliestPeople.take(3).map((p) => _costRow(p['name'] as String, p['cost'] as num)),
        ],
      ],
    );
  }

  Widget _costRow(String label, num cost) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text('₹${cost.toStringAsFixed(0)}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red.shade700)),
        ],
      ),
    );
  }

  String _avgCycle(int mins) {
    if (mins <= 0) return '—';
    if (mins < 60) return '$mins min';
    if (mins < 1440) return '${(mins / 60).toStringAsFixed(1)} hrs';
    return '${(mins / 1440).toStringAsFixed(1)} days';
  }

  Widget _summaryTile(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center),
      ],
    );
  }

  Widget _kpiCard(String label, int count, Color color, IconData icon, VoidCallback onTap) {
    return Card(
      color: color.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color),
              Text('$count', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// Drill-down behind a KPI card. Same common columns for every category:
// order number, start date, current status, best-effort item/detail label.
class FlowOrdersListScreen extends StatefulWidget {
  final String category; // PENDING | COMPLETED | DELAYED | ONTIME
  final String title;

  const FlowOrdersListScreen({super.key, required this.category, required this.title});

  @override
  State<FlowOrdersListScreen> createState() => _FlowOrdersListScreenState();
}

class _FlowOrdersListScreenState extends State<FlowOrdersListScreen> {
  List<dynamic> _orders = [];
  bool _loading = true;
  String? _error;
  final _search = TextEditingController();
  DateRangePreset _datePreset = DateRangePreset.all;

  static final _fmt = DateFormat('MMM d, yyyy');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final o = await Api.fmsAnalyticsOrders(
        widget.category,
        search: _search.text.trim().isEmpty ? null : _search.text.trim(),
        from: _datePreset.from,
      );
      setState(() => _orders = o);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: 'Search by order number',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _search.clear();
                              _load();
                            },
                          ),
                  ),
                  onSubmitted: (_) => _load(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<DateRangePreset>(
                        initialValue: _datePreset,
                        isDense: true,
                        decoration: const InputDecoration(
                          labelText: 'Start date',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: DateRangePreset.values
                            .map((p) => DropdownMenuItem(value: p, child: Text(p.label(AppLocalizations.of(context)))))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _datePreset = v);
                          _load();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _orders.isEmpty
                        ? const Center(child: Text('No orders match this filter.'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _orders.length,
                              itemBuilder: (_, i) {
                                final o = _orders[i] as Map;
                                return Card(
                                  child: ListTile(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => OrderHistoryScreen(
                                          orderId: o['id'] as String,
                                          orderNumber: o['orderNumber'] as String,
                                        ),
                                      ),
                                    ),
                                    title: Text(o['orderNumber'] as String,
                                        style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(o['detailLabel'] as String),
                                        Text(
                                          '${_fmt.format(DateTime.parse(o['startedAt'] as String).toLocal())} · ${o['status']}',
                                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
