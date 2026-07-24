import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'api.dart';
import 'theme/app_theme.dart';
import 'widgets/motion.dart';
import 'owner.dart';
import 'checklist.dart';
import 'fms.dart';
import 'filters.dart';
import 'inventory.dart';
import 'push.dart';
import 'stuck.dart';
import 'health_score.dart';
import 'settings.dart';
import 'profile.dart';
import 'analytics.dart';
import 'admin.dart';
import 'signup.dart';
import 'reset_requests.dart';
import 'responsive.dart';
import 'theme_controller.dart';
import 'locale_controller.dart';
import 'l10n/gen/app_localizations.dart';
import 'offline/write_queue.dart';
import 'offline/connectivity_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.loadToken();
  await ThemeController.load();
  await LocaleController.load();
  await PushService.init();
  await WriteQueue.init();
  ConnectivityService.start(Api.flushQueue);
  runApp(const NavishApp());
}

class NavishApp extends StatelessWidget {
  const NavishApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (_, mode, __) => ValueListenableBuilder<Locale>(
        valueListenable: LocaleController.locale,
        builder: (_, locale, __) => MaterialApp(
          title: 'Navish',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: PushService.scaffoldMessengerKey,
          themeMode: mode,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Api.isLoggedIn ? const HomeScreen() : const LoginScreen(),
        ),
      ),
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
      Navigator.pushReplacement(context, sharedAxisRoute(const HomeScreen()));
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: _email.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.forgotPasswordDialogTitle),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: l10n.yourEmailLabel, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.requestReset),
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
    final theme = Theme.of(context);
    final reduced = reducedMotion(context);
    final l10n = AppLocalizations.of(context);

    Widget stagger(Widget child, int step) {
      if (reduced) return child;
      return child
          .animate(delay: (80 * step).ms)
          .fadeIn(duration: 380.ms, curve: Curves.easeOut)
          .slideY(begin: 0.12, end: 0, duration: 420.ms, curve: Curves.easeOutCubic);
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  stagger(
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [theme.colorScheme.primary, theme.colorScheme.tertiary],
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Text('N',
                            style: TextStyle(
                                color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    0,
                  ),
                  const SizedBox(height: 20),
                  stagger(
                    Text('Navish',
                        style: theme.textTheme.displaySmall, textAlign: TextAlign.center),
                    1,
                  ),
                  const SizedBox(height: 6),
                  stagger(
                    Text(l10n.loginTagline,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center),
                    2,
                  ),
                  const SizedBox(height: 36),
                  stagger(
                    TextField(
                      controller: _email,
                      decoration: InputDecoration(labelText: l10n.emailLabel),
                    ),
                    3,
                  ),
                  const SizedBox(height: 12),
                  stagger(
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: InputDecoration(labelText: l10n.passwordLabel),
                    ),
                    4,
                  ),
                  const SizedBox(height: 20),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: TextStyle(color: AppColors.of(context).danger))
                          .animate()
                          .fadeIn(duration: 200.ms)
                          .shakeX(hz: 6, amount: 4),
                    ),
                  stagger(
                    FilledButton(
                      onPressed: _loading ? null : _login,
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: _loading
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(l10n.logIn),
                    ),
                    5,
                  ),
                  const SizedBox(height: 8),
                  stagger(
                    Column(
                      children: [
                        TextButton(
                          onPressed: _forgotPassword,
                          child: Text(l10n.forgotPassword),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.push(context, sharedAxisRoute(const SignupScreen())),
                          child: Text(l10n.newCompanyCreateAccount),
                        ),
                      ],
                    ),
                    6,
                  ),
                ],
              ),
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
  int _stuckCount = 0;
  Map<String, dynamic>? _healthScore;
  bool _loading = true;
  int _tab = 0;
  String _taskStatus = 'ACTIVE';
  DateRangePreset _datePreset = DateRangePreset.all;
  bool get _isOwner => _user?['role'] == 'OWNER' || _user?['role'] == 'MANAGER';
  bool get _isOwnerRole => _user?['role'] == 'OWNER';
  bool get _isSuperAdmin => _user?['isSuperAdmin'] == true;

  // Module tabs, "Home" hub always first. Owner/Manager get the full module
  // set; Employee gets a trimmed one. Profile/Settings/Admin are reached via
  // the More menu (compact) or the rail's trailing icons (medium/expanded) —
  // they're pushed screens, not part of this index.
  List<String> get _moduleLabels => _isOwner
      ? const ['Home', 'Stuck', 'Tasks', 'Checklists', 'Flows', 'Inventory', 'Analytics']
      : const ['Home', 'Tasks', 'Inventory'];

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

  Future<Map<String, dynamic>?> _tryHealthScore() async {
    try {
      return await Api.healthScore();
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // me()/myTasks()/notifications() don't depend on each other — fire all
      // three at once instead of a 3-deep sequential waterfall. stuck/health
      // are OWNER/MANAGER-only and need the role from me() first, but once
      // that's known they run in parallel with everything else too.
      final userFuture = Api.me();
      final tasksFuture = Api.myTasks(status: _taskStatus, from: _datePreset.from);
      final notifsFuture = Api.notifications();

      final user = await userFuture;
      // Stuck endpoint is OWNER/MANAGER-only server-side — matches _isOwner.
      // Best-effort: the at-a-glance strip just shows 0 if this fails.
      final isOwnerOrManager = user['role'] == 'OWNER' || user['role'] == 'MANAGER';
      final stuckFuture = isOwnerOrManager
          ? Api.stuckList().then((l) => l.length).catchError((_) => 0)
          : Future.value(0);
      // Health Score endpoint is OWNER/MANAGER-only server-side too — best
      // effort, same spirit as stuckCount above: the gauge just hides itself.
      final Future<Map<String, dynamic>?> healthFuture = isOwnerOrManager
          ? _tryHealthScore()
          : Future.value(null);

      final results = await Future.wait([tasksFuture, notifsFuture, stuckFuture, healthFuture]);
      final tasks = results[0] as List<dynamic>;
      final notifs = results[1] as List<dynamic>;
      final stuckCount = results[2] as int;
      final healthScore = results[3] as Map<String, dynamic>?;

      setState(() { _user = user; _tasks = tasks; _notifs = notifs; _stuckCount = stuckCount; _healthScore = healthScore; });
      unawaited(LocaleController.syncFromProfile(user['language'] as String?));
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
        case 'CHECKLIST_DUE': return 3;
        case 'FMS_STAGE': return 4;
        case 'INVENTORY_ALERT': return 5;
        default: return 2; // CHASE, TASK_ASSIGNED, ESCALATION
      }
    }
    switch (type) {
      case 'INVENTORY_ALERT': return 2;
      default: return 1;
    }
  }

  // Stuck tab rows (and Health Score "biggest drags") deep-link into a
  // sibling owner tab.
  int _tabForModule(String module) {
    switch (module) {
      case 'STUCK': return 1;
      case 'CHECKLISTS': return 3;
      case 'FMS': return 4;
      case 'INVENTORY': return 5;
      default: return 2; // TASKS
    }
  }

  Future<void> _done(String id) async {
    try {
      await Api.markDone(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).doneChasingStopped)),
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

  Future<void> _logout() async {
    await PushService.unregisterToken();
    await Api.logout();
    if (!mounted) return;
    // Called from Profile, which sits on top of Home in the nav stack —
    // pushReplacement would only swap out Profile and leave a stale,
    // still-"logged-in" Home screen buried underneath. Clear everything
    // down to a single fresh LoginScreen instead.
    Navigator.of(context).pushAndRemoveUntil(
      sharedAxisRoute(const LoginScreen()),
      (route) => false,
    );
  }

  void _openProfile() {
    Navigator.push(context, sharedAxisRoute(ProfileScreen(onLogout: _logout)))
        .then((_) => _load());
  }

  void _openSettings() {
    Navigator.push(context, sharedAxisRoute(const SettingsScreen()));
  }

  void _openResetRequests() {
    Navigator.push(context, sharedAxisRoute(const ResetRequestsScreen()));
  }

  void _openAdmin() {
    Navigator.push(context, sharedAxisRoute(const AdminScreen()));
  }

  void _openNotifications() {
    Navigator.push(
      context,
      sharedAxisRoute(_NotificationsScreen(notifs: _notifs)),
    ).then((_) => _load());
  }

  // Compact phones can't fit Profile/Settings/Admin as their own bottom
  // destinations alongside every module — they collapse into this sheet.
  void _showMoreSheet() {
    final l10n = AppLocalizations.of(context);
    showAdaptiveSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(l10n.navProfile),
              onTap: () { Navigator.pop(context); _openProfile(); },
            ),
            if (_isOwnerRole)
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text(l10n.navCompanySettings),
                onTap: () { Navigator.pop(context); _openSettings(); },
              ),
            if (_isOwner && !_isOwnerRole)
              ListTile(
                leading: const Icon(Icons.lock_reset),
                title: Text(l10n.navPasswordResetRequests),
                onTap: () { Navigator.pop(context); _openResetRequests(); },
              ),
            if (_isSuperAdmin)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: Text(l10n.navNavishAdmin),
                onTap: () { Navigator.pop(context); _openAdmin(); },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  IconData _moduleIcon(String label) {
    switch (label) {
      case 'Stuck': return Icons.warning_amber;
      case 'Tasks': return Icons.list_alt;
      case 'Checklists': return Icons.event_repeat;
      case 'Flows': return Icons.account_tree;
      case 'Inventory': return Icons.inventory_2;
      case 'Analytics': return Icons.analytics;
      default: return Icons.home;
    }
  }

  // _moduleLabels stays English — it's the identity used by the switch/
  // indexOf logic throughout this screen (_bodyForTab, _homeHub tab
  // switching, _moduleIcon). This maps that identity to display text only,
  // so nav/dashboard labels localize without touching navigation logic.
  String _moduleDisplayLabel(AppLocalizations l10n, String label) {
    switch (label) {
      case 'Home': return l10n.navHome;
      case 'Stuck': return l10n.navStuck;
      case 'Tasks': return l10n.navTasks;
      case 'Checklists': return l10n.navChecklists;
      case 'Flows': return l10n.navFlows;
      case 'Inventory': return l10n.navInventory;
      case 'Analytics': return l10n.navAnalytics;
      default: return label;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final size = screenSizeOf(context);
    final labels = _moduleLabels;
    final l10n = AppLocalizations.of(context);
    final body = Column(
      children: [
        _offlineBanner(),
        Expanded(
          child: MaxWidthCenter(
            child: FadeThroughSwitcher(tabKey: _tab, child: _bodyForTab(labels)),
          ),
        ),
      ],
    );

    final appBar = AppBar(
      title: GestureDetector(
        onTap: _openProfile,
        child: Text(_user?['nickname'] as String? ?? _user?['name'] ?? l10n.appTitle),
      ),
      actions: [_notificationBell(l10n)],
    );

    if (size == ScreenSize.compact) {
      return Scaffold(
        appBar: appBar,
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          onDestinationSelected: (i) {
            if (i == labels.length) {
              _showMoreSheet();
            } else {
              setState(() => _tab = i);
            }
          },
          destinations: [
            for (final l in labels)
              NavigationDestination(icon: Icon(_moduleIcon(l)), label: _moduleDisplayLabel(l10n, l)),
            NavigationDestination(icon: const Icon(Icons.more_horiz), label: l10n.navMore),
          ],
        ),
      );
    }

    // Medium/expanded: a side rail replaces the bottom bar, and there's room
    // to show Profile/Settings/Admin directly instead of behind a menu.
    return Scaffold(
      appBar: appBar,
      body: Row(
        children: [
          // A short window (many modules + a maximized owner/superadmin
          // trailing icon set) can exceed the viewport height — scroll
          // instead of overflowing, same as the rail would on a real device.
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    selectedIndex: _tab,
                    onDestinationSelected: (i) => setState(() => _tab = i),
                    labelType: size == ScreenSize.expanded
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all,
                    extended: size == ScreenSize.expanded,
                    destinations: [
                      for (final l in labels)
                        NavigationRailDestination(icon: Icon(_moduleIcon(l)), label: Text(_moduleDisplayLabel(l10n, l))),
                    ],
                    trailing: Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.person_outline),
                                tooltip: l10n.navProfile,
                                onPressed: _openProfile,
                              ),
                              if (_isOwnerRole)
                                IconButton(
                                  icon: const Icon(Icons.settings_outlined),
                                  tooltip: l10n.navCompanySettings,
                                  onPressed: _openSettings,
                                ),
                              if (_isOwner && !_isOwnerRole)
                                IconButton(
                                  icon: const Icon(Icons.lock_reset),
                                  tooltip: l10n.navPasswordResetRequests,
                                  onPressed: _openResetRequests,
                                ),
                              if (_isSuperAdmin)
                                IconButton(
                                  icon: const Icon(Icons.admin_panel_settings),
                                  tooltip: l10n.navNavishAdmin,
                                  onPressed: _openAdmin,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _notificationBell(AppLocalizations l10n) {
    final unread = _notifs.length;
    return IconButton(
      tooltip: l10n.alerts,
      onPressed: _openNotifications,
      icon: PulseOnChange(
        value: unread,
        child: Badge(
          label: Text('$unread'),
          isLabelVisible: unread > 0,
          child: const Icon(Icons.notifications_outlined),
        ),
      ),
    );
  }

  Widget _bodyForTab(List<String> labels) {
    final label = labels[_tab];
    switch (label) {
      case 'Home':
        return _homeHub(labels);
      case 'Stuck':
        return StuckScreen(onNavigateToModule: (m) => setState(() => _tab = _tabForModule(m)));
      case 'Tasks':
        return _isOwner ? const OwnerScreen() : _tasksView();
      case 'Checklists':
        return const ChecklistScreen();
      case 'Flows':
        return FmsScreen(currentUserId: _user?['id'] as String?, role: _user?['role'] as String?);
      case 'Inventory':
        return InventoryScreen(
          role: _user?['role'] as String?,
          canStockIn: _user?['canStockIn'] == true,
          canStockOut: _user?['canStockOut'] == true,
        );
      case 'Analytics':
        return const AnalyticsScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  int get _dueTodayCount {
    final now = DateTime.now();
    return _tasks.where((t) {
      final dueAt = t['dueAt'];
      if (dueAt == null) return false;
      final d = DateTime.parse(dueAt).toLocal();
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).length;
  }

  // Dashboard-style landing hub: a greeting, an at-a-glance strip pulled
  // from data already loaded this session, then a centered grid of module
  // cards so "where do I go" is answered before the nav is even touched.
  Widget _homeHub(List<String> labels) {
    final modules = labels.where((l) => l != 'Home').toList();
    final crossAxisCount = switch (screenSizeOf(context)) {
      ScreenSize.compact => 2,
      ScreenSize.medium => 3,
      ScreenSize.expanded => 4,
    };
    final theme = Theme.of(context);
    final semantic = AppColors.of(context);
    final reduced = reducedMotion(context);
    final l10n = AppLocalizations.of(context);

    Widget entrance(Widget child, int index) {
      if (reduced) return child;
      return child
          .animate(delay: (40 * index).ms)
          .fadeIn(duration: 320.ms, curve: Curves.easeOut)
          .slideY(begin: 0.08, end: 0, duration: 360.ms, curve: Curves.easeOutCubic);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          entrance(
            Text(
              l10n.helloUser(_user?['nickname'] as String? ?? _user?['name'] ?? ''),
              style: theme.textTheme.displaySmall,
            ),
            0,
          ),
          const SizedBox(height: 4),
          entrance(
            Text(
              _user?['organization']?['name'] as String? ?? '',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            1,
          ),
          const SizedBox(height: 20),
          if (_isOwner) ...[
            entrance(
              HealthGauge(
                score: _healthScore?['overall'] as int?,
                band: _healthScore?['band'] as String?,
                delta: (_healthScore?['trend'] as Map?)?['delta'] as int?,
                onTap: _healthScore == null
                    ? null
                    : () => Navigator.push(
                          context,
                          sharedAxisRoute(HealthScoreScreen(
                            onNavigateToModule: (m) => setState(() => _tab = _tabForModule(m)),
                          )),
                        ),
              ),
              2,
            ),
            const SizedBox(height: 16),
          ],
          entrance(
            Row(
              children: [
                if (_isOwner)
                  Expanded(
                    child: _glanceStat(
                      icon: Icons.warning_amber_rounded,
                      label: l10n.navStuck,
                      value: _stuckCount,
                      color: _stuckCount > 0 ? semantic.danger : semantic.success,
                      onTap: _stuckCount > 0
                          ? () => setState(() => _tab = labels.indexOf('Stuck'))
                          : null,
                    ),
                  ),
                if (_isOwner) const SizedBox(width: 12),
                Expanded(
                  child: _glanceStat(
                    icon: Icons.today_outlined,
                    label: l10n.dueToday,
                    value: _dueTodayCount,
                    color: semantic.info,
                  ),
                ),
              ],
            ),
            3,
          ),
          const SizedBox(height: 24),
          GridView.count(
            crossAxisCount: crossAxisCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              for (final (i, m) in modules.indexed)
                entrance(
                  PressableScale(
                    onTap: () => setState(() => _tab = labels.indexOf(m)),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Icon(_moduleIcon(m), size: 26,
                                  color: theme.colorScheme.onPrimaryContainer),
                            ),
                            const SizedBox(height: 12),
                            Text(_moduleDisplayLabel(l10n, m), style: theme.textTheme.titleMedium),
                          ],
                        ),
                      ),
                    ),
                  ),
                  4 + i,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _glanceStat({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
    VoidCallback? onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      child: Card(
        color: color.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$value',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(color: color)),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tasksView() {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        FilterBar(
          status: _taskStatus,
          onStatusChanged: (s) {
            setState(() => _taskStatus = s);
            _load();
          },
          activeLabel: l10n.activeFilter,
          doneLabel: l10n.doneFilter,
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
                      ? l10n.noPendingTasks
                      : l10n.nothingHereYet),
                )
              : _tasksList(),
        ),
      ],
    );
  }

  Widget _tasksList() {
    final l10n = AppLocalizations.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _tasks.length,
        itemBuilder: (_, i) {
          final t = _tasks[i];
          final overdue = t['dueAt'] != null &&
              DateTime.parse(t['dueAt']).isBefore(DateTime.now());
          return StaggeredListItem(
            index: i,
            child: Card(
              child: ListTile(
                title: Text(t['title'],
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (t['dueAt'] != null)
                      Text(l10n.dueLabel('${DateTime.parse(t['dueAt']).toLocal()}'),
                          style: TextStyle(
                              color: overdue ? AppColors.of(context).danger : Colors.grey,
                              fontSize: 12)),
                    Text(l10n.chasedTimes(t['chaseCount'], t['priority']),
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
                trailing: _taskStatus == 'ACTIVE'
                    ? FilledButton(
                        onPressed: () => playDoneConfirmation(
                          context,
                          onFinished: () => _done(t['id']),
                        ),
                        child: Text(l10n.done),
                      )
                    : null,
              ),
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
}

// Alerts — reachable only via the bell in the AppBar now, never a bottom tab.
class _NotificationsScreen extends StatelessWidget {
  final List<dynamic> notifs;
  const _NotificationsScreen({required this.notifs});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.alerts)),
      body: MaxWidthCenter(
        maxWidth: 800,
        child: notifs.isEmpty
            ? Center(child: Text(l10n.noAlerts))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: notifs.length,
                itemBuilder: (_, i) {
                  final n = notifs[i];
                  return StaggeredListItem(
                    index: i,
                    child: Card(
                      child: ListTile(
                        leading: Icon(
                          n['type'] == 'ESCALATION' ? Icons.warning : Icons.notifications,
                          color: n['type'] == 'ESCALATION'
                              ? AppColors.of(context).danger
                              : AppColors.of(context).info,
                        ),
                        title: Text(n['title']),
                        subtitle: Text(n['body']),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
