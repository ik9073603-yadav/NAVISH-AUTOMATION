import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'analytics.dart';
import 'change_password.dart';
import 'legal.dart';
import 'deletion_requests.dart';
import 'responsive.dart';
import 'theme/app_theme.dart';
import 'widgets/motion.dart';
import 'locale_controller.dart';
import 'l10n/gen/app_localizations.dart';

// The account's own profile — picture, identity fields, preferences, and the
// entry points (change password / performance / logout) that used to live in
// the AppBar's popup menu. Reachable from the bottom nav / rail "More" area.
class ProfileScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const ProfileScreen({super.key, required this.onLogout});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _user;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;

  final _name = TextEditingController();
  final _nickname = TextEditingController();
  final _designation = TextEditingController();
  final _phone = TextEditingController();
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _nickname.dispose();
    _designation.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = await Api.me();
      setState(() {
        _user = user;
        _name.text = user['name'] as String? ?? '';
        _nickname.text = user['nickname'] as String? ?? '';
        _designation.text = user['designation'] as String? ?? '';
        _phone.text = user['phone'] as String? ?? '';
        _dirty = false;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final Uint8List bytes = await file.readAsBytes();
      final url = await Api.uploadImage(bytes, file.name);
      final updated = await Api.updateMe(photoUrl: url);
      if (mounted) setState(() => _user = {..._user!, ...updated});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _saveBasicInfo() async {
    setState(() => _saving = true);
    try {
      final updated = await Api.updateMe(
        name: _name.text.trim(),
        nickname: _nickname.text.trim(),
        designation: _designation.text.trim(),
        phone: _phone.text.trim(),
      );
      if (mounted) {
        setState(() {
          _user = {..._user!, ...updated};
          _dirty = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).profileUpdated)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setLanguage(String lang) async {
    if (_user?['language'] == lang) return;
    final previous = _user?['language'] as String? ?? 'en';
    setState(() => _user = {..._user!, 'language': lang});
    // Flip the whole app's locale immediately — don't wait on the network
    // round-trip, so the toggle feels instant. Rolled back below on failure.
    await LocaleController.set(lang);
    try {
      await Api.updateMe(language: lang);
    } catch (e) {
      if (mounted) {
        setState(() => _user = {..._user!, 'language': previous});
        await LocaleController.set(previous);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  bool get _isOwnerOrManager => _user?['role'] == 'OWNER' || _user?['role'] == 'MANAGER';
  bool get _isOwner => _user?['role'] == 'OWNER';

  void _openPerformance() {
    if (_isOwnerOrManager) {
      Navigator.push(context, sharedAxisRoute(const AnalyticsScreen()));
    } else {
      Navigator.push(context, sharedAxisRoute(const MyStatsScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: _loading
          ? const ShimmerSkeletonList()
          : RefreshIndicator(
              onRefresh: _load,
              child: MaxWidthCenter(
                maxWidth: 720,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _photoSection(),
                    const SizedBox(height: 24),
                    _sectionLabel(l10n.basicInfo),
                    _textField(l10n.nameLabel, _name, onChanged: () => setState(() => _dirty = true)),
                    const SizedBox(height: 12),
                    _textField(l10n.nicknameLabel, _nickname, onChanged: () => setState(() => _dirty = true)),
                    const SizedBox(height: 12),
                    _textField(l10n.designationLabel, _designation,
                        hint: l10n.designationHint,
                        onChanged: () => setState(() => _dirty = true)),
                    const SizedBox(height: 12),
                    _textField(l10n.phoneLabel, _phone,
                        keyboardType: TextInputType.phone,
                        onChanged: () => setState(() => _dirty = true)),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: (_dirty && !_saving) ? _saveBasicInfo : null,
                      child: _saving
                          ? const SizedBox(
                              height: 18, width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(l10n.saveChanges),
                    ),
                    const SizedBox(height: 28),
                    _sectionLabel(l10n.account),
                    _readOnlyTile(Icons.email_outlined, l10n.emailLabel, _user?['email'] as String? ?? '—'),
                    _readOnlyTile(Icons.badge_outlined, l10n.roleLabel, _user?['role'] as String? ?? '—'),
                    _readOnlyTile(Icons.apartment_outlined, l10n.departmentLabel,
                        (_user?['department'] as Map?)?['name'] as String? ?? l10n.notAssigned),
                    const SizedBox(height: 28),
                    _sectionLabel(l10n.preferences),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'en', label: Text('English')),
                          ButtonSegment(value: 'hi', label: Text('हिन्दी')),
                        ],
                        selected: {_user?['language'] as String? ?? 'en'},
                        onSelectionChanged: (s) => _setLanguage(s.first),
                      ),
                    ),
                    const SizedBox(height: 28),
                    _sectionLabel(l10n.securityAndActivity),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.lock_outline),
                            title: Text(l10n.changePassword),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(context,
                                sharedAxisRoute(const ChangePasswordScreen())),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.insights_outlined),
                            title: Text(l10n.myPerformanceStats),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _openPerformance,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.gavel_outlined),
                            title: Text(l10n.legalMenu),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                                context, sharedAxisRoute(const LegalScreen())),
                          ),
                          if (_isOwner) ...[
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.person_remove_outlined),
                              title: Text(l10n.accountDeletionRequests),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.push(context,
                                  sharedAxisRoute(const DeletionRequestsScreen())),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.of(context).danger),
                      onPressed: widget.onLogout,
                      icon: const Icon(Icons.logout),
                      label: Text(l10n.logout),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _photoSection() {
    final photoUrl = _user?['photoUrl'] as String?;
    final displayName = (_user?['nickname'] as String?)?.isNotEmpty == true
        ? _user!['nickname'] as String
        : _user?['name'] as String? ?? '';
    return Center(
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 48,
                backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                child: photoUrl == null
                    ? Text(
                        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 32),
                      )
                    : null,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: InkWell(
                  onTap: _uploadingPhoto ? null : _pickPhoto,
                  borderRadius: BorderRadius.circular(20),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: _uploadingPhoto
                        ? const SizedBox(
                            height: 14, width: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(displayName, style: Theme.of(context).textTheme.headlineSmall),
          if (_user?['designation'] != null && (_user!['designation'] as String).isNotEmpty)
            Text(_user!['designation'] as String,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );

  Widget _textField(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboardType,
    required VoidCallback onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => onChanged(),
    );
  }

  Widget _readOnlyTile(IconData icon, String label, String value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}

// Lightweight self-service performance view for employees — the full
// AnalyticsScreen is OWNER/MANAGER-only server-side, so this computes simple
// counts client-side from the same /api/tasks/my endpoint the Tasks tab uses.
class MyStatsScreen extends StatefulWidget {
  const MyStatsScreen({super.key});
  @override
  State<MyStatsScreen> createState() => _MyStatsScreenState();
}

class _MyStatsScreenState extends State<MyStatsScreen> {
  bool _loading = true;
  String? _error;
  int _activeCount = 0;
  int _doneCount = 0;
  int _onTimeCount = 0;
  int _escalatedCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        Api.myTasks(status: 'ACTIVE'),
        Api.myTasks(status: 'DONE'),
      ]);
      final active = results[0];
      final done = results[1];
      int onTime = 0;
      int escalated = 0;
      for (final t in done) {
        if (t['escalatedAt'] != null) escalated++;
        final dueAt = t['dueAt'];
        final completedAt = t['completedAt'];
        if (dueAt != null && completedAt != null) {
          if (!DateTime.parse(completedAt).isAfter(DateTime.parse(dueAt))) onTime++;
        }
      }
      setState(() {
        _activeCount = active.length;
        _doneCount = done.length;
        _onTimeCount = onTime;
        _escalatedCount = escalated;
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onTimePct = _doneCount == 0 ? 0 : ((_onTimeCount / _doneCount) * 100).round();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.myPerformance)),
      body: _loading
          ? const ShimmerSkeletonList()
          : _error != null
              ? Center(child: Text(_error!))
              : MaxWidthCenter(
                  maxWidth: 720,
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Row(
                          children: [
                            Expanded(child: _statCard(l10n.activeTasksStat, '$_activeCount', AppColors.of(context).warning)),
                            const SizedBox(width: 12),
                            Expanded(child: _statCard(l10n.completedStat, '$_doneCount', AppColors.of(context).success)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _statCard(l10n.onTimePctStat, '$onTimePct%', AppColors.of(context).info)),
                            const SizedBox(width: 12),
                            Expanded(child: _statCard(l10n.escalatedStat, '$_escalatedCount', AppColors.of(context).danger)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
