import 'package:flutter/material.dart';
import 'api.dart';

// Owner: approve or deny pending account-deletion requests (Feature 176).
// Approving deactivates the account — a soft action, not a hard data wipe.
class DeletionRequestsScreen extends StatefulWidget {
  const DeletionRequestsScreen({super.key});
  @override
  State<DeletionRequestsScreen> createState() => _DeletionRequestsScreenState();
}

class _DeletionRequestsScreenState extends State<DeletionRequestsScreen> {
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
      final requests = await Api.deletionRequests();
      setState(() => _requests = requests);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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

  Future<void> _complete(Map<String, dynamic> req) async {
    final user = req['user'] as Map<String, dynamic>?;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Deactivate this account?'),
        content: Text('${user?['name']} will be deactivated and unable to log in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Api.completeDeletionRequest(req['id'] as String);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deny(Map<String, dynamic> req) async {
    try {
      await Api.denyDeletionRequest(req['id'] as String);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account deletion requests')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? const Center(child: Text('No pending deletion requests'))
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
                                tooltip: 'Approve (deactivate)',
                                onPressed: () => _complete(r),
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
