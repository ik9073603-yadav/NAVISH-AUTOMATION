import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'config.dart';
import 'theme/app_theme.dart';

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
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.of(context).danger,
              foregroundColor: AppColors.of(context).onDanger,
            ),
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

  Widget _iconBadge(BuildContext context, IconData icon, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, color: foreground, size: 20),
    );
  }

  @override
  Widget build(BuildContext context) {
    final semantic = AppColors.of(context);
    final accents = AppAccents.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Legal')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: _iconBadge(context, Icons.description_outlined, accents.tealContainer, accents.onTealContainer),
            title: Text('Terms & Conditions', style: Theme.of(context).textTheme.titleSmall),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open('/legal/terms'),
          ),
          ListTile(
            leading: _iconBadge(context, Icons.privacy_tip_outlined, semantic.infoContainer, semantic.onInfoContainer),
            title: Text('Privacy Policy', style: Theme.of(context).textTheme.titleSmall),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open('/legal/privacy'),
          ),
          const Divider(height: 24),
          ListTile(
            leading: _iconBadge(context, Icons.delete_forever_outlined, semantic.dangerContainer, semantic.danger),
            title: Text('Delete my account', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: semantic.danger)),
            subtitle: const Text('Files a request; your owner/admin actions it'),
            onTap: () => _requestDeletion(context),
          ),
        ],
      ),
    );
  }
}
