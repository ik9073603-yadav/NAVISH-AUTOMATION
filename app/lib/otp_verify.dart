import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'push.dart';
import 'main.dart';
import 'theme/app_theme.dart';
import 'widgets/motion.dart';
import 'l10n/gen/app_localizations.dart';

const _resendCooldownSeconds = 60;

// Shared OTP-entry screen for both post-signup verification and an
// unverified account's first login (owner-added employee) — both complete
// the same way: Api.verifyOtp() succeeds, a session token is issued, and we
// land in HomeScreen with the whole auth stack cleared behind us.
class OtpVerifyScreen extends StatefulWidget {
  final String email;
  const OtpVerifyScreen({super.key, required this.email});

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());
  bool _verifying = false;
  bool _resending = false;
  String? _error;
  int _cooldown = _resendCooldownSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _cooldown = _resendCooldownSeconds);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  String get _code => _controllers.map((c) => c.text).join();

  void _onChanged(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    if (_code.length == 6) _verify();
  }

  Future<void> _verify() async {
    final l10n = AppLocalizations.of(context);
    if (_code.length != 6) {
      setState(() => _error = l10n.otpIncompleteCode);
      return;
    }
    setState(() { _verifying = true; _error = null; });
    try {
      await Api.verifyOtp(widget.email, _code);
      await PushService.registerToken();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context, sharedAxisRoute(const HomeScreen()), (route) => false);
    } catch (e) {
      if (!mounted) return;
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    setState(() { _resending = true; _error = null; });
    try {
      await Api.resendOtp(widget.email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).otpCodeResent)));
      _startCooldown();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Widget _box(int index) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 48,
      height: 58,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: theme.textTheme.headlineMedium?.copyWith(color: theme.colorScheme.primary),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        // No explicit border here — inherits the theme's filled, rounded,
        // primary-highlighted-on-focus input styling instead of a flat
        // rectangle that ignored the rest of the design system.
        decoration: const InputDecoration(counterText: ''),
        onChanged: (v) => _onChanged(index, v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.otpScreenTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.otpScreenTitle.toUpperCase(),
                    textAlign: TextAlign.center, style: AppTheme.eyebrow(context)),
                const SizedBox(height: 8),
                Text(
                  l10n.otpScreenSubtitle(widget.email),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(6, _box),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: TextStyle(color: AppColors.of(context).danger)),
                  ),
                FilledButton(
                  onPressed: _verifying ? null : _verify,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50)),
                  child: _verifying
                      ? SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary))
                      : Text(l10n.otpVerify),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: (_cooldown > 0 || _resending) ? null : _resend,
                  child: Text(_cooldown > 0 ? l10n.otpResendIn(_cooldown) : l10n.otpResendCode),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
