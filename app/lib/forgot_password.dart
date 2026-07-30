import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'theme/app_theme.dart';
import 'validators.dart';
import 'l10n/gen/app_localizations.dart';

const _resendCooldownSeconds = 60;

// Self-service, email-OTP password reset: email -> OTP -> new password ->
// pops back to LoginScreen with a message to show. The EXISTING owner/
// manager-approval flow (Api.requestPasswordReset) stays reachable from a
// fallback link on the first step — this is an additional path, not a
// replacement.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _Step { email, otp, newPassword }

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  _Step _step = _Step.email;
  final _email = TextEditingController();
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(6, (_) => FocusNode());
  final _newPassword = TextEditingController();
  bool _loading = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _newPassword.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
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

  String get _code => _otpControllers.map((c) => c.text).join();

  Future<void> _sendCode() async {
    final l10n = AppLocalizations.of(context);
    final email = _email.text.trim();
    if (!isValidEmail(email)) {
      setState(() => _error = l10n.invalidEmailError);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await Api.forgotPasswordOtp(email);
      if (!mounted) return;
      setState(() => _step = _Step.otp);
      _startCooldown();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() { _loading = true; _error = null; });
    try {
      await Api.forgotPasswordOtp(_email.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).otpCodeResent)));
      _startCooldown();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onOtpChanged(int index, String value) {
    if (value.isNotEmpty && index < 5) _otpFocusNodes[index + 1].requestFocus();
    if (value.isEmpty && index > 0) _otpFocusNodes[index - 1].requestFocus();
  }

  void _submitOtp() {
    final l10n = AppLocalizations.of(context);
    if (_code.length != 6) {
      setState(() => _error = l10n.otpIncompleteCode);
      return;
    }
    setState(() { _error = null; _step = _Step.newPassword; });
  }

  Future<void> _resetPassword() async {
    final l10n = AppLocalizations.of(context);
    if (_newPassword.text.length < 8) {
      setState(() => _error = l10n.fillRequiredFieldsError);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await Api.resetPasswordOtp(_email.text.trim(), _code, _newPassword.text);
      if (!mounted) return;
      Navigator.pop(context, l10n.passwordResetSuccess);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _askManagerInstead() async {
    try {
      final message = await Api.requestPasswordReset(_email.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _otpBox(int index) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 48,
      height: 58,
      child: TextField(
        controller: _otpControllers[index],
        focusNode: _otpFocusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: theme.textTheme.headlineMedium?.copyWith(color: theme.colorScheme.primary),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(counterText: ''),
        onChanged: (v) => _onOtpChanged(index, v),
      ),
    );
  }

  Widget _errorText() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(_error!, style: TextStyle(color: AppColors.of(context).danger)),
    );
  }

  Widget _emailStep(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.forgotPasswordTitle.toUpperCase(), style: AppTheme.eyebrow(context)),
        const SizedBox(height: 6),
        Text(l10n.forgotPasswordStepEmailSubtitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 20),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: l10n.yourEmailLabel),
        ),
        const SizedBox(height: 16),
        _errorText(),
        FilledButton(
          onPressed: _loading ? null : _sendCode,
          style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
          child: _loading
              ? SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary))
              : Text(l10n.sendCode),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _askManagerInstead, child: Text(l10n.askManagerInstead)),
      ],
    );
  }

  Widget _otpStep(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.otpScreenTitle.toUpperCase(),
            textAlign: TextAlign.center, style: AppTheme.eyebrow(context)),
        const SizedBox(height: 6),
        Text(l10n.otpScreenSubtitle(_email.text.trim()),
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: List.generate(6, _otpBox)),
        const SizedBox(height: 16),
        _errorText(),
        FilledButton(
          onPressed: _submitOtp,
          style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
          child: Text(l10n.otpVerify),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: (_cooldown > 0 || _loading) ? null : _resendCode,
          child: Text(_cooldown > 0 ? l10n.otpResendIn(_cooldown) : l10n.otpResendCode),
        ),
      ],
    );
  }

  Widget _newPasswordStep(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.newPasswordLabel.toUpperCase(), style: AppTheme.eyebrow(context)),
        const SizedBox(height: 12),
        TextField(
          controller: _newPassword,
          obscureText: true,
          decoration: InputDecoration(labelText: l10n.newPasswordLabel),
        ),
        const SizedBox(height: 16),
        _errorText(),
        FilledButton(
          onPressed: _loading ? null : _resetPassword,
          style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
          child: _loading
              ? SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary))
              : Text(l10n.resetPasswordButton),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.forgotPasswordTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: switch (_step) {
              _Step.email => _emailStep(l10n),
              _Step.otp => _otpStep(l10n),
              _Step.newPassword => _newPasswordStep(l10n),
            },
          ),
        ),
      ),
    );
  }
}
