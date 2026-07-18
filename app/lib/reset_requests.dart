import 'package:flutter/material.dart';
import 'api.dart';
import 'contact_actions.dart';

// Owner/Manager: approve or deny employees' forgot-password requests.
class ResetRequestsScreen extends StatefulWidget {
  const ResetRequestsScreen({super.key});
  @override
  State<ResetRequestsScreen> createState() => _ResetRequestsScreenState();
}

class _ResetRequestsScreenState extends State<ResetRequestsScreen> {
  List<dynamic> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final requests = await Api.resetRequests();
      setState(() => _requests = requests);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _timeAgo(String iso) {
    final mins = DateTime.now().difference(DateTime.parse(iso).toLocal()).inMinutes;
    if (mins < 1) return 'just now';
    if (mins < 60) return '$mins min ago';
    final hrs = mins ~/ 60;
    if (hrs < 24) return '$hrs hr ago';
    return '${hrs ~/ 24} day(s) ago';
  }

  Future<void> _approve(Map<String, dynamic> req) async {
    try {
      final result = await Api.approveReset(req['id'] as String);
      if (!mounted) return;
      final user = result['user'] as Map<String, dynamic>;
      final tempPassword = result['tempPassword'] as String;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('New password for ${user['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Relay this to them — it will not be shown again:'),
              const SizedBox(height: 12),
              SelectableText(
                tempPassword,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 16),
              ContactButtons(
                phone: user['phone'] as String?,
                message: 'Hi ${user['name']}, your new temporary password is: $tempPassword',
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _deny(Map<String, dynamic> req) async {
    try {
      await Api.denyReset(req['id'] as String);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Password reset requests')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? const Center(child: Text('No pending reset requests'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _requests.length,
                    itemBuilder: (_, i) {
                      final r = _requests[i] as Map<String, dynamic>;
                      final user = r['user'] as Map<String, dynamic>?;
                      return Card(
                        child: ListTile(
                          title: Text(user?['name'] ?? 'Unknown user'),
                          subtitle: Text(
                              '${user?['email'] ?? ''} · requested ${_timeAgo(r['requestedAt'] as String)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check_circle, color: Colors.green),
                                tooltip: 'Approve',
                                onPressed: () => _approve(r),
                              ),
                              IconButton(
                                icon: const Icon(Icons.cancel, color: Colors.red),
                                tooltip: 'Deny',
                                onPressed: () => _deny(r),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
