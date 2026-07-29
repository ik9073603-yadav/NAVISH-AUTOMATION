import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api.dart';
import 'filters.dart';
import 'order_history.dart';
import 'l10n/gen/app_localizations.dart';

// Drill-down behind a KPI card in the Analytics tab's Flow analysis screen
// (analytics_flow.dart). Same common columns for every category:
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
  int _loadRequestId = 0;

  static final _fmt = DateFormat('MMM d, yyyy');

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
    final requestId = ++_loadRequestId;
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
      if (mounted && requestId == _loadRequestId) setState(() => _orders = o);
    } catch (e) {
      if (mounted && requestId == _loadRequestId) setState(() => _error = '$e');
    } finally {
      if (mounted && requestId == _loadRequestId) setState(() => _loading = false);
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
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant),
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
