import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'config.dart';
import 'push.dart';
import 'main.dart';

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
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                TextField(
                  controller: _companyName,
                  decoration: const InputDecoration(labelText: 'Company name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ownerName,
                  decoration: const InputDecoration(labelText: 'Your name (owner)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password (8+ characters)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone (optional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _accepted,
                  onChanged: (v) => setState(() => _accepted = v ?? false),
                  title: Wrap(
                    children: [
                      const Text('I accept the '),
                      GestureDetector(
                        onTap: () => _open('/legal/terms'),
                        child: const Text('Terms & Conditions',
                            style: TextStyle(color: Colors.green, decoration: TextDecoration.underline)),
                      ),
                      const Text(' and '),
                      GestureDetector(
                        onTap: () => _open('/legal/privacy'),
                        child: const Text('Privacy Policy',
                            style: TextStyle(color: Colors.green, decoration: TextDecoration.underline)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                FilledButton(
                  onPressed: (_loading || !_accepted) ? null : _submit,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _loading
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Create account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
