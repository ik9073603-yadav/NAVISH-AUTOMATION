import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme/app_theme.dart';

// Normalises a raw phone number to E.164, assuming +91 (India) when no
// country code is present. Strips spaces/dashes/parens. Returns null for
// anything that isn't a usable number.
String? normalizePhone(String? raw) {
  if (raw == null) return null;
  final digits = raw.replaceAll(RegExp(r'[^\d+]'), '');
  if (digits.isEmpty) return null;
  if (digits.startsWith('+')) {
    // A bare "+" or "+" followed by too few digits isn't a usable number —
    // reject it the same as if no phone were present at all.
    return digits.substring(1).length >= 8 ? digits : null;
  }
  if (digits.length == 10) return '+91$digits';
  if (digits.startsWith('91') && digits.length == 12) return '+$digits';
  return '+$digits';
}

Future<void> callPhone(String rawPhone) async {
  final phone = normalizePhone(rawPhone);
  if (phone == null) return;
  await launchUrl(Uri.parse('tel:$phone'));
}

Future<void> whatsappMessage(String rawPhone, String message) async {
  final phone = normalizePhone(rawPhone);
  if (phone == null) return;
  final number = phone.replaceFirst('+', '');
  final encoded = Uri.encodeComponent(message);
  await launchUrl(
    Uri.parse('https://wa.me/$number?text=$encoded'),
    mode: LaunchMode.externalApplication,
  );
}

// One-tap Call + WhatsApp icon buttons for wherever a person's name appears.
// Renders nothing if there's no phone number — never show a broken control.
class ContactButtons extends StatelessWidget {
  final String? phone;
  final String message;
  final double iconSize;

  const ContactButtons({
    super.key,
    required this.phone,
    required this.message,
    this.iconSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = normalizePhone(phone);
    if (normalized == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(Icons.call, color: AppColors.of(context).success, size: iconSize),
          tooltip: 'Call',
          onPressed: () => callPhone(normalized),
        ),
        IconButton(
          // WhatsApp's own brand green — a third-party mark, deliberately
          // left as-is so the icon stays instantly recognizable, unlike the
          // app's own (now retired) green theme.
          icon: Icon(Icons.chat, color: const Color(0xFF25D366), size: iconSize),
          tooltip: 'WhatsApp',
          onPressed: () => whatsappMessage(normalized, message),
        ),
      ],
    );
  }
}
