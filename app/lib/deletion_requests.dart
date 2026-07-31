import 'package:flutter/material.dart';
import 'api.dart';
import 'theme/app_theme.dart';
import 'time_format.dart';

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
      if (mounted) setState(() => _requests = requests);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.of(context).danger,
              foregroundColor: AppColors.of(context).onDanger,
            ),
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
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _deny(Map<String, dynamic> req) async {
    try {
      await Api.denyDeletionRequest(req['id'] as String);
      _load();
    } catch (e) {
      if (mounted) showApiError(context, e);
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
                      final semantic = AppColors.of(context);
                      return Card(
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: semantic.warningContainer, shape: BoxShape.circle),
                            child: Icon(Icons.person_remove_outlined, color: semantic.onWarningContainer, size: 20),
                          ),
                          title: Text(user?['name'] ?? 'Unknown user', style: Theme.of(context).textTheme.titleSmall),
                          subtitle: Text(
                              '${user?['email'] ?? ''} · requested ${timeAgo(r['requestedAt'] as String)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.check_circle, color: semantic.success),
                                tooltip: 'Approve (deactivate)',
                                onPressed: () => _complete(r),
                              ),
                              IconButton(
                                icon: Icon(Icons.cancel, color: semantic.danger),
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
