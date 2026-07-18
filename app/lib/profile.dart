import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'analytics.dart';
import 'change_password.dart';
import 'legal.dart';
import 'deletion_requests.dart';
import 'responsive.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
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
    try {
      await Api.updateMe(language: lang);
    } catch (e) {
      if (mounted) {
        setState(() => _user = {..._user!, 'language': previous});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  bool get _isOwnerOrManager => _user?['role'] == 'OWNER' || _user?['role'] == 'MANAGER';
  bool get _isOwner => _user?['role'] == 'OWNER';

  void _openPerformance() {
    if (_isOwnerOrManager) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalyticsScreen()));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const MyStatsScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: MaxWidthCenter(
                maxWidth: 720,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _photoSection(),
                    const SizedBox(height: 24),
                    _sectionLabel('Basic info'),
                    _textField('Name', _name, onChanged: () => setState(() => _dirty = true)),
                    const SizedBox(height: 12),
                    _textField('Nickname', _nickname, onChanged: () => setState(() => _dirty = true)),
                    const SizedBox(height: 12),
                    _textField('Post / designation', _designation,
                        hint: 'e.g. Manager, Supervisor, Machine Operator',
                        onChanged: () => setState(() => _dirty = true)),
                    const SizedBox(height: 12),
                    _textField('Phone', _phone,
                        keyboardType: TextInputType.phone,
                        onChanged: () => setState(() => _dirty = true)),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: (_dirty && !_saving) ? _saveBasicInfo : null,
                      child: _saving
                          ? const SizedBox(
                              height: 18, width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Save changes'),
                    ),
                    const SizedBox(height: 28),
                    _sectionLabel('Account'),
                    _readOnlyTile(Icons.email_outlined, 'Email', _user?['email'] as String? ?? '—'),
                    _readOnlyTile(Icons.badge_outlined, 'Role', _user?['role'] as String? ?? '—'),
                    _readOnlyTile(Icons.apartment_outlined, 'Department',
                        (_user?['department'] as Map?)?['name'] as String? ?? 'Not assigned'),
                    const SizedBox(height: 28),
                    _sectionLabel('Preferences'),
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
                    _sectionLabel('Security & activity'),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.lock_outline),
                            title: const Text('Change password'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const ChangePasswordScreen())),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.insights_outlined),
                            title: const Text('My performance stats'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _openPerformance,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.gavel_outlined),
                            title: const Text('Legal (Terms / Privacy / Delete account)'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                                context, MaterialPageRoute(builder: (_) => const LegalScreen())),
                          ),
                          if (_isOwner) ...[
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.person_remove_outlined),
                              title: const Text('Account deletion requests'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => const DeletionRequestsScreen())),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: widget.onLogout,
                      icon: const Icon(Icons.logout),
                      label: const Text('Logout'),
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
          Text(displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          if (_user?['designation'] != null && (_user!['designation'] as String).isNotEmpty)
            Text(_user!['designation'] as String, style: TextStyle(color: Colors.grey.shade600)),
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
    final onTimePct = _doneCount == 0 ? 0 : ((_onTimeCount / _doneCount) * 100).round();
    return Scaffold(
      appBar: AppBar(title: const Text('My performance')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                            Expanded(child: _statCard('Active tasks', '$_activeCount', Colors.orange)),
                            const SizedBox(width: 12),
                            Expanded(child: _statCard('Completed', '$_doneCount', Colors.green)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _statCard('On-time %', '$onTimePct%', Colors.blue)),
                            const SizedBox(width: 12),
                            Expanded(child: _statCard('Escalated', '$_escalatedCount', Colors.red)),
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
            Text(label, style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}
