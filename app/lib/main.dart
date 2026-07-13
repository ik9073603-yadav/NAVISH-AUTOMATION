import 'package:flutter/material.dart';
import 'api.dart';
import 'owner.dart';
import 'checklist.dart';
import 'fms.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.loadToken();
  runApp(const NavishApp());
}

class NavishApp extends StatelessWidget {
  const NavishApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Navish',
      debugShowCheckedModeBanner: false,
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

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _user;
  List<dynamic> _tasks = [];
  List<dynamic> _notifs = [];
  bool _loading = true;
  int _tab = 0;
  bool get _isOwner => _user?['role'] == 'OWNER' || _user?['role'] == 'MANAGER';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = await Api.me();
      final tasks = await Api.myTasks();
      final notifs = await Api.notifications();
      setState(() { _user = user; _tasks = tasks; _notifs = notifs; });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _done(String id) async {
    await Api.markDone(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Done ✅  Chasing stopped.')),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_user?['name'] ?? 'Navish'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Api.logout();
              if (!mounted) return;
              Navigator.pushReplacement(
                  context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
          ),
        ],
      ),
      body: _isOwner
          ? [const OwnerScreen(), const ChecklistScreen(), const FmsScreen(), _notifsView()][_tab]
          : [_tasksView(), _notifsView()][_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: _isOwner
            ? const [
                NavigationDestination(icon: Icon(Icons.list_alt), label: 'Tasks'),
                NavigationDestination(icon: Icon(Icons.event_repeat), label: 'Checklists'),
                NavigationDestination(icon: Icon(Icons.account_tree), label: 'FMS'),
                NavigationDestination(icon: Icon(Icons.notifications), label: 'Alerts'),
              ]
            : const [
                NavigationDestination(icon: Icon(Icons.checklist), label: 'Tasks'),
                NavigationDestination(icon: Icon(Icons.notifications), label: 'Alerts'),
              ],
      ),
    );
  }

  Widget _tasksView() {
    if (_tasks.isEmpty) {
      return const Center(child: Text('No pending tasks 🎉'));
    }
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
              trailing: FilledButton(
                onPressed: () => _done(t['id']),
                child: const Text('Done'),
              ),
            ),
          );
        },
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