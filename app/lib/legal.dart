import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'config.dart';

// Profile → Legal. Opens the backend-hosted Terms/Privacy pages and lets the
// user file an account-deletion request (Feature 176).
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  Future<void> _open(String path) async {
    await launchUrl(Uri.parse('${Config.apiBase}$path'), mode: LaunchMode.externalApplication);
  }

  Future<void> _requestDeletion(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete my account?'),
        content: const Text(
          "This files a deletion request with your organization's owner (or a Navish "
          "administrator). Your account stays active until they action it.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Request deletion'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Api.requestAccountDeletion();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deletion request submitted.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Legal')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms & Conditions'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open('/legal/terms'),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open('/legal/privacy'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
            title: const Text('Delete my account', style: TextStyle(color: Colors.red)),
            subtitle: const Text('Files a request; your owner/admin actions it'),
            onTap: () => _requestDeletion(context),
          ),
        ],
      ),
    );
  }
}
