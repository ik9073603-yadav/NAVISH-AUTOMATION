import 'package:flutter/material.dart';
import 'api.dart';
import 'owner.dart';
import 'checklist.dart';
import 'fms.dart';
import 'filters.dart';
import 'inventory.dart';
import 'push.dart';
import 'stuck.dart';
import 'settings.dart';
import 'change_password.dart';
import 'reset_requests.dart';
import 'analytics.dart';
import 'admin.dart';
import 'signup.dart';
import 'legal.dart';
import 'deletion_requests.dart';
import 'offline/write_queue.dart';
import 'offline/connectivity_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.loadToken();
  await PushService.init();
  await WriteQueue.init();
  ConnectivityService.start(Api.flushQueue);
  runApp(const NavishApp());
}

class NavishApp extends StatelessWidget {
  const NavishApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Navish',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: PushService.scaffoldMessengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F5132)),
        useMaterial3: true,
      ),
      home: Api.isLoggedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}

// ---------------- LOGIN ----------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController(text: 'suraj@navish.com');
  final _password = TextEditingController(text: 'password123');
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      await Api.login(_email.text.trim(), _password.text);
      await PushService.registerToken();
      if (!mounted) return;
      Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final controller = TextEditingController(text: _email.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Forgot password'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Your email', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Request reset'),
          ),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;
    try {
      final message = await Api.requestPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Navish',
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text('Your operations, on autopilot',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center),
                const SizedBox(height: 32),
                TextField(
                  controller: _email,
                  decoration: const InputDecoration(
                      labelText: 'Email', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Password', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                FilledButton(
                  onPressed: _loading ? null : _login,
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _loading
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Log in'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _forgotPassword,
                  child: const Text('Forgot password?'),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const SignupScreen())),
                  child: const Text("New company? Create an account"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- HOME ----------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _user;
  List<dynamic> _tasks = [];
  List<dynamic> _notifs = [];
  bool _loading = true;
  int _tab = 0;
  String _taskStatus = 'ACTIVE';
  DateRangePreset _datePreset = DateRangePreset.all;
  bool get _isOwner => _user?['role'] == 'OWNER' || _user?['role'] == 'MANAGER';
  bool get _isOwnerRole => _user?['role'] == 'OWNER';
  bool get _isSuperAdmin => _user?['isSuperAdmin'] == true;

  @override
  void initState() {
    super.initState();
    _load();
    PushService.pendingTap.addListener(_onPushTapLive);
    WidgetsBinding.instance.addObserver(this);
  }

  // Extra reliability alongside the connectivity-change trigger: a resumed
  // app is a natural moment to try flushing anything still queued.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) Api.flushQueue();
  }

  @override
  void dispose() {
    PushService.pendingTap.removeListener(_onPushTapLive);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // A tap that arrives while this screen is already alive (app was only
  // backgrounded, not relaunched) needs a fresh _load() — otherwise we'd
  // switch tabs onto whatever stale list was fetched before the push fired.
  void _onPushTapLive() {
    if (PushService.pendingTap.value == null) return;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = await Api.me();
      final tasks = await Api.myTasks(status: _taskStatus, from: _datePreset.from);
      final notifs = await Api.notifications();
      setState(() { _user = user; _tasks = tasks; _notifs = notifs; });
      _consumePendingTap();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Deep link from a tapped push: jump to the tab for whatever fired it.
  // No per-task detail screen exists yet, so we land on the relevant module
  // (the item itself is right there at the top of that list).
  void _consumePendingTap() {
    final data = PushService.pendingTap.value;
    if (data == null || _user == null) return;
    final type = data['type'] as String?;
    setState(() => _tab = _tabForPushType(type));
    PushService.pendingTap.value = null;
  }

  int _tabForPushType(String? type) {
    if (_isOwner) {
      switch (type) {
        case 'CHECKLIST_DUE': return 2;
        case 'FMS_STAGE': return 3;
        case 'INVENTORY_ALERT': return 4;
        default: return 1; // CHASE, TASK_ASSIGNED, ESCALATION
      }
    }
    switch (type) {
      case 'INVENTORY_ALERT': return 1;
      default: return 0;
    }
  }

  // Stuck tab rows deep-link into a sibling owner tab.
  int _tabForModule(String module) {
    switch (module) {
      case 'CHECKLISTS': return 2;
      case 'FMS': return 3;
      case 'INVENTORY': return 4;
      default: return 1; // TASKS
    }
  }

  Future<void> _done(String id) async {
    try {
      await Api.markDone(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Done ✅  Chasing stopped.')),
      );
      _load();
    } on OfflineQueuedException {
      // Still offline — reflect it locally now; the real sync happens later.
      if (!mounted) return;
      setState(() => _tasks = _tasks.where((t) => t['id'] != id).toList());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved offline — will sync when back online')),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _editPhone() async {
    final controller = TextEditingController(text: _user?['phone'] as String? ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Your phone number'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone',
            hintText: '9876543210',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    try {
      await Api.updateMyPhone(result.isEmpty ? null : result);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _editPhone,
          child: Text(_user?['name'] ?? 'Navish'),
        ),
        actions: [
          if (_isSuperAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              tooltip: 'Navish Admin',
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const AdminScreen())),
            ),
          if (_isOwnerRole)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Company settings',
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          if (_isOwner)
            IconButton(
              icon: const Icon(Icons.lock_reset),
              tooltip: 'Password reset requests',
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const ResetRequestsScreen())),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onSelected: (choice) {
              if (choice == 'phone') _editPhone();
              if (choice == 'password') {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));
              }
              if (choice == 'legal') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const LegalScreen()));
              }
              if (choice == 'deletion_requests') {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const DeletionRequestsScreen()));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'phone', child: Text('Edit phone number')),
              const PopupMenuItem(value: 'password', child: Text('Change password')),
              const PopupMenuItem(value: 'legal', child: Text('Legal (Terms / Privacy / Delete account)')),
              if (_isOwnerRole)
                const PopupMenuItem(value: 'deletion_requests', child: Text('Account deletion requests')),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await PushService.unregisterToken();
              await Api.logout();
              if (!mounted) return;
              Navigator.pushReplacement(
                  context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _offlineBanner(),
          Expanded(
            child: _isOwner
                ? [
                    StuckScreen(onNavigateToModule: (m) => setState(() => _tab = _tabForModule(m))),
                    const OwnerScreen(),
                    const ChecklistScreen(),
                    FmsScreen(currentUserId: _user?['id'] as String?, role: _user?['role'] as String?),
                    InventoryScreen(
                      role: _user?['role'] as String?,
                      canStockIn: _user?['canStockIn'] == true,
                      canStockOut: _user?['canStockOut'] == true,
                    ),
                    const AnalyticsScreen(),
                    _notifsView(),
                  ][_tab]
                : [
                    _tasksView(),
                    InventoryScreen(
                      role: _user?['role'] as String?,
                      canStockIn: _user?['canStockIn'] == true,
                      canStockOut: _user?['canStockOut'] == true,
                    ),
                    _notifsView(),
                  ][_tab],
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: _isOwner
            ? const [
                NavigationDestination(icon: Icon(Icons.warning_amber), label: 'Stuck'),
                NavigationDestination(icon: Icon(Icons.list_alt), label: 'Tasks'),
                NavigationDestination(icon: Icon(Icons.event_repeat), label: 'Checklists'),
                NavigationDestination(icon: Icon(Icons.account_tree), label: 'Flows'),
                NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Inventory'),
                NavigationDestination(icon: Icon(Icons.analytics), label: 'Analytics'),
                NavigationDestination(icon: Icon(Icons.notifications), label: 'Alerts'),
              ]
            : const [
                NavigationDestination(icon: Icon(Icons.checklist), label: 'Tasks'),
                NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Inventory'),
                NavigationDestination(icon: Icon(Icons.notifications), label: 'Alerts'),
              ],
      ),
    );
  }

  Widget _tasksView() {
    return Column(
      children: [
        FilterBar(
          status: _taskStatus,
          onStatusChanged: (s) {
            setState(() => _taskStatus = s);
            _load();
          },
          datePreset: _datePreset,
          onDatePresetChanged: (p) {
            setState(() => _datePreset = p);
            _load();
          },
        ),
        Expanded(
          child: _tasks.isEmpty
              ? Center(
                  child: Text(_taskStatus == 'ACTIVE'
                      ? 'No pending tasks 🎉'
                      : 'Nothing here yet'),
                )
              : _tasksList(),
        ),
      ],
    );
  }

  Widget _tasksList() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _tasks.length,
        itemBuilder: (_, i) {
          final t = _tasks[i];
          final overdue = t['dueAt'] != null &&
              DateTime.parse(t['dueAt']).isBefore(DateTime.now());
          return Card(
            child: ListTile(
              title: Text(t['title'],
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (t['dueAt'] != null)
                    Text('Due: ${DateTime.parse(t['dueAt']).toLocal()}',
                        style: TextStyle(
                            color: overdue ? Colors.red : Colors.grey,
                            fontSize: 12)),
                  Text('Chased ${t['chaseCount']} times · ${t['priority']}',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
              trailing: _taskStatus == 'ACTIVE'
                  ? FilledButton(
                      onPressed: () => _done(t['id']),
                      child: const Text('Done'),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }

  // Slim status strip: offline, pending-sync count, or actively syncing.
  // Never blocks the UI — just tells the user what's going on.
  Widget _offlineBanner() {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.isOnline,
      builder: (_, online, __) => ValueListenableBuilder<int>(
        valueListenable: WriteQueue.pendingCount,
        builder: (_, pending, ___) => ValueListenableBuilder<bool>(
          valueListenable: WriteQueue.syncing,
          builder: (_, syncing, ____) {
            if (online && pending == 0 && !syncing) return const SizedBox.shrink();

            final String text;
            final Color color;
            if (syncing) {
              text = 'Syncing $pending change${pending == 1 ? '' : 's'}...';
              color = Colors.blue.shade700;
            } else if (!online) {
              text = pending > 0
                  ? 'Offline — $pending change${pending == 1 ? '' : 's'} will sync'
                  : 'Offline — will sync';
              color = Colors.orange.shade800;
            } else {
              text = '$pending change${pending == 1 ? '' : 's'} pending sync';
              color = Colors.orange.shade800;
            }

            return Container(
              width: double.infinity,
              color: color,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _notifsView() {
    if (_notifs.isEmpty) return const Center(child: Text('No alerts'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _notifs.length,
      itemBuilder: (_, i) {
        final n = _notifs[i];
        return Card(
          child: ListTile(
            leading: Icon(
              n['type'] == 'ESCALATION' ? Icons.warning : Icons.notifications,
              color: n['type'] == 'ESCALATION' ? Colors.red : Colors.blue,
            ),
            title: Text(n['title']),
            subtitle: Text(n['body']),
          ),
        );
      },
    );
  }
}