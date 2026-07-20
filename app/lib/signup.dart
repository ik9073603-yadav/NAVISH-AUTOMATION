import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'config.dart';
import 'push.dart';
import 'main.dart';
import 'theme/app_theme.dart';
import 'widgets/motion.dart';

// New-company signup. The Terms/Privacy checkbox is mandatory — the button
// stays disabled until it's checked, matching the backend's acceptedTerms gate.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _companyName = TextEditingController();
  final _ownerName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  bool _accepted = false;
  bool _loading = false;
  String? _error;

  Future<void> _open(String path) async {
    await launchUrl(Uri.parse('${Config.apiBase}$path'), mode: LaunchMode.externalApplication);
  }

  Future<void> _submit() async {
    if (_companyName.text.trim().length < 2 ||
        _ownerName.text.trim().length < 2 ||
        _email.text.trim().isEmpty ||
        _password.text.length < 8) {
      setState(() => _error = 'Fill in all required fields (password: 8+ characters)');
      return;
    }
    if (!_accepted) {
      setState(() => _error = 'You must accept the Terms & Conditions and Privacy Policy');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      await Api.signup(
        companyName: _companyName.text.trim(),
        ownerName: _ownerName.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        acceptedTerms: _accepted,
      );
      await PushService.registerToken();
      if (!mounted) return;
      Navigator.pushReplacement(context, sharedAxisRoute(const HomeScreen()));
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduced = reducedMotion(context);
    Widget stagger(Widget child, int step) {
      if (reduced) return child;
      return child
          .animate(delay: (60 * step).ms)
          .fadeIn(duration: 320.ms, curve: Curves.easeOut)
          .slideY(begin: 0.08, end: 0, duration: 360.ms, curve: Curves.easeOutCubic);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Create your company')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                stagger(TextField(
                  controller: _companyName,
                  decoration: const InputDecoration(labelText: 'Company name'),
                ), 0),
                const SizedBox(height: 12),
                stagger(TextField(
                  controller: _ownerName,
                  decoration: const InputDecoration(labelText: 'Your name (owner)'),
                ), 1),
                const SizedBox(height: 12),
                stagger(TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ), 2),
                const SizedBox(height: 12),
                stagger(TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password (8+ characters)'),
                ), 3),
                const SizedBox(height: 12),
                stagger(TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone (optional)'),
                ), 4),
                const SizedBox(height: 16),
                stagger(CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _accepted,
                  onChanged: (v) => setState(() => _accepted = v ?? false),
                  title: Wrap(
                    children: [
                      const Text('I accept the '),
                      GestureDetector(
                        onTap: () => _open('/legal/terms'),
                        child: Text('Terms & Conditions',
                            style: TextStyle(
                                color: theme.colorScheme.primary,
                                decoration: TextDecoration.underline)),
                      ),
                      const Text(' and '),
                      GestureDetector(
                        onTap: () => _open('/legal/privacy'),
                        child: Text('Privacy Policy',
                            style: TextStyle(
                                color: theme.colorScheme.primary,
                                decoration: TextDecoration.underline)),
                      ),
                    ],
                  ),
                ), 5),
                const SizedBox(height: 12),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: TextStyle(color: AppColors.of(context).danger)),
                  ),
                stagger(FilledButton(
                  onPressed: (_loading || !_accepted) ? null : _submit,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _loading
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Create account'),
                ), 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
