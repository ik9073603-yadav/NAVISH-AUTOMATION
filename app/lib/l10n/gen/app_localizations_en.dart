// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Navish';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get add => 'Add';

  @override
  String get delete => 'Delete';

  @override
  String get confirm => 'Confirm';

  @override
  String get done => 'Done';

  @override
  String get everyone => 'Everyone';

  @override
  String get loginTagline => 'Your operations, on autopilot';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get logIn => 'Log in';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get newCompanyCreateAccount => 'New company? Create an account';

  @override
  String get forgotPasswordDialogTitle => 'Forgot password';

  @override
  String get yourEmailLabel => 'Your email';

  @override
  String get requestReset => 'Request reset';

  @override
  String get createYourCompany => 'Create your company';

  @override
  String get companyNameLabel => 'Company name';

  @override
  String get yourNameOwnerLabel => 'Your name (owner)';

  @override
  String get passwordHintLabel => 'Password (8+ characters)';

  @override
  String get phoneOptionalLabel => 'Phone (optional)';

  @override
  String get acceptTermsPrefix => 'I accept the ';

  @override
  String get termsAndConditions => 'Terms & Conditions';

  @override
  String get andWord => ' and ';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get createAccount => 'Create account';

  @override
  String get fillRequiredFieldsError =>
      'Fill in all required fields (password: 8+ characters)';

  @override
  String get acceptTermsError =>
      'You must accept the Terms & Conditions and Privacy Policy';

  @override
  String get navHome => 'Home';

  @override
  String get navStuck => 'Stuck';

  @override
  String get navTasks => 'Tasks';

  @override
  String get navChecklists => 'Checklists';

  @override
  String get navFlows => 'Flows';

  @override
  String get navInventory => 'Inventory';

  @override
  String get navAnalytics => 'Analytics';

  @override
  String get navMore => 'More';

  @override
  String get navProfile => 'Profile';

  @override
  String get navCompanySettings => 'Company settings';

  @override
  String get navPasswordResetRequests => 'Password reset requests';

  @override
  String get navNavishAdmin => 'Navish Admin';

  @override
  String get alerts => 'Alerts';

  @override
  String get noAlerts => 'No alerts';

  @override
  String helloUser(Object name) {
    return 'Hello, $name';
  }

  @override
  String get dueToday => 'Due today';

  @override
  String get noPendingTasks => 'No pending tasks 🎉';

  @override
  String get nothingHereYet => 'Nothing here yet';

  @override
  String get assignTaskAction => 'Assign task';

  @override
  String get addPerson => 'Add person';

  @override
  String get allTasks => 'All tasks';

  @override
  String get team => 'Team';

  @override
  String get noTasksAssignOne => 'No tasks yet. Assign one 👇';

  @override
  String get doneChasingStopped => 'Done ✅  Chasing stopped.';

  @override
  String dueLabel(Object date) {
    return 'Due: $date';
  }

  @override
  String chasedTimes(Object count, Object priority) {
    return 'Chased $count times · $priority';
  }

  @override
  String get nothingStuckTitle => 'Nothing is stuck.';

  @override
  String get nothingStuckSubtitle => 'Everything is running.';

  @override
  String get moduleTasks => 'Tasks';

  @override
  String get moduleChecklists => 'Checklists';

  @override
  String get moduleFlows => 'Flows';

  @override
  String get moduleInventory => 'Inventory';

  @override
  String get profileTitle => 'Profile';

  @override
  String get basicInfo => 'Basic info';

  @override
  String get nameLabel => 'Name';

  @override
  String get nicknameLabel => 'Nickname';

  @override
  String get designationLabel => 'Post / designation';

  @override
  String get designationHint => 'e.g. Manager, Supervisor, Machine Operator';

  @override
  String get phoneLabel => 'Phone';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get profileUpdated => 'Profile updated';

  @override
  String get account => 'Account';

  @override
  String get roleLabel => 'Role';

  @override
  String get departmentLabel => 'Department';

  @override
  String get notAssigned => 'Not assigned';

  @override
  String get preferences => 'Preferences';

  @override
  String get securityAndActivity => 'Security & activity';

  @override
  String get changePassword => 'Change password';

  @override
  String get myPerformanceStats => 'My performance stats';

  @override
  String get legalMenu => 'Legal (Terms / Privacy / Delete account)';

  @override
  String get accountDeletionRequests => 'Account deletion requests';

  @override
  String get logout => 'Logout';

  @override
  String get myPerformance => 'My performance';

  @override
  String get activeTasksStat => 'Active tasks';

  @override
  String get completedStat => 'Completed';

  @override
  String get onTimePctStat => 'On-time %';

  @override
  String get escalatedStat => 'Escalated';

  @override
  String get companySettingsTitle => 'Company settings';

  @override
  String get companyProfile => 'Company profile';

  @override
  String get industryLabel => 'Industry';

  @override
  String get industryHint => 'e.g. Manufacturing, Retail';

  @override
  String get timezone => 'Timezone';

  @override
  String get workingDays => 'Working days';

  @override
  String get weekdayMon => 'Mon';

  @override
  String get weekdayTue => 'Tue';

  @override
  String get weekdayWed => 'Wed';

  @override
  String get weekdayThu => 'Thu';

  @override
  String get weekdayFri => 'Fri';

  @override
  String get weekdaySat => 'Sat';

  @override
  String get weekdaySun => 'Sun';

  @override
  String get shiftHours => 'Shift hours';

  @override
  String startTime(Object time) {
    return 'Start: $time';
  }

  @override
  String endTime(Object time) {
    return 'End: $time';
  }

  @override
  String get holidays => 'Holidays';

  @override
  String get noHolidaysAdded => 'No holidays added';

  @override
  String get saveSettings => 'Save settings';

  @override
  String get settingsSaved => 'Settings saved';

  @override
  String get requests => 'Requests';

  @override
  String get passwordResetRequestsSubtitle =>
      'Approve or deny employees who forgot their password';

  @override
  String get notifications => 'Notifications';

  @override
  String get pushNotificationsTitle => 'Push notifications on this device';

  @override
  String get pushNotificationsSubtitle => 'Chases, escalations and alerts';

  @override
  String get appearance => 'Appearance';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get system => 'System';

  @override
  String get dataSection => 'Data';

  @override
  String get dataExportDescription =>
      'A full export of your company\'s data — users, tasks, checklists, flow monitoring orders, inventory.';

  @override
  String get preparingBackup => 'Preparing backup...';

  @override
  String get downloadFullBackup => 'Download full company backup';

  @override
  String get delayCostPerHourLabel => 'Delay cost per hour (₹)';

  @override
  String get delayCostPerHourHint =>
      'What one working hour of delay costs you — used to price late stages in ₹.';

  @override
  String get costOfDelayTooltipTitle => 'How is this calculated?';

  @override
  String get costOfDelayTooltipBody =>
      'A stage costs money only if it has a deadline and finishes late. Delay is counted in working hours only — nights, week-offs and holidays never count. Cost = delay hours × your ₹/hr rate. If no rate is set, it\'s estimated instead from the order\'s value, spread over the flow\'s planned hours. If neither is set, no ₹ figure is shown.';

  @override
  String get assignATask => 'Assign a task';

  @override
  String get whatNeedsDoing => 'What needs doing?';

  @override
  String get detailsOptional => 'Details (optional)';

  @override
  String get assignTo => 'Assign to';

  @override
  String get priorityLabel => 'Priority: ';

  @override
  String get priorityHigh => 'High';

  @override
  String get priorityNormal => 'Normal';

  @override
  String get priorityLow => 'Low';

  @override
  String get dueIn => 'Due in: ';

  @override
  String get dueIn2Min => '2 min (test)';

  @override
  String get dueIn1Hour => '1 hour';

  @override
  String get dueIn4Hours => '4 hours';

  @override
  String get dueInTomorrow => 'Tomorrow';

  @override
  String get assigning => 'Assigning...';

  @override
  String assignToNPeople(Object count) {
    return 'Assign to $count person(s)';
  }

  @override
  String get addAPerson => 'Add a person';

  @override
  String get temporaryPassword => 'Temporary password';

  @override
  String get roleFieldLabel => 'Role';

  @override
  String get roleEmployee => 'Employee';

  @override
  String get roleManager => 'Manager';

  @override
  String get adding => 'Adding...';

  @override
  String get inventoryPermissionsTooltip => 'Inventory permissions';

  @override
  String inventoryPermissionsTitle(Object name) {
    return 'Inventory permissions — $name';
  }

  @override
  String get canAddStock => 'Can add stock (Stock IN)';

  @override
  String get canRemoveStock => 'Can remove stock (Stock OUT)';

  @override
  String get noDataYet => 'No data yet';

  @override
  String noTasksYetRole(Object role) {
    return 'No tasks yet · $role';
  }

  @override
  String get companyHealthScore => 'Company Health Score';

  @override
  String get healthBandHealthy => 'Healthy';

  @override
  String get healthBandNeedsAttention => 'Needs attention';

  @override
  String get healthBandAtRisk => 'At risk';

  @override
  String healthTrendUpBy(Object delta) {
    return '+$delta vs last period';
  }

  @override
  String healthTrendDownBy(Object delta) {
    return '$delta vs last period';
  }

  @override
  String get healthTrendFlat => 'No change vs last period';

  @override
  String get healthNoTrendYet => 'Not enough history yet';

  @override
  String get healthBreakdownTitle => 'Health Score breakdown';

  @override
  String get healthBiggestDrags => 'Biggest drags';

  @override
  String get healthNoDrags => 'Nothing dragging your score down 🎉';

  @override
  String healthWeightLabel(Object pct) {
    return '$pct% of score';
  }

  @override
  String get healthExcludedNoData => 'Excluded — no data yet';

  @override
  String healthWindowLabel(Object days) {
    return 'Last $days days';
  }

  @override
  String get healthHowCalculatedTitle => 'How is this score calculated?';

  @override
  String get healthHowCalculatedBody =>
      'Each component below is scored 0-100 and combined using its weight. A component with no data yet (e.g. no checklists) is left out and the other weights are scaled up to fill the gap — it\'s never scored a fake 0. Tap \"Biggest drags\" to jump straight to what needs attention.';

  @override
  String get healthComponentOnTime => 'On-time performance';

  @override
  String get healthComponentStuckLoad => 'Stuck / overdue load';

  @override
  String get healthComponentChecklist => 'Checklist compliance';

  @override
  String get healthComponentInventory => 'Inventory health';

  @override
  String get healthComponentEscalations => 'Escalations';

  @override
  String healthReasonOnTime(Object pct, Object late, Object total) {
    return '$pct% on-time — $late of $total finished late';
  }

  @override
  String get healthReasonStuckLoadZero => 'Nothing stuck or overdue right now';

  @override
  String healthReasonStuckLoad(Object count) {
    return '$count item(s) stuck or overdue right now';
  }

  @override
  String healthReasonChecklist(Object pct, Object done, Object total) {
    return '$pct% compliance — $done of $total completed';
  }

  @override
  String healthReasonInventory(Object alertCount, Object deadPct) {
    return '$alertCount low/over-stock item(s), $deadPct% of stock value is dead';
  }

  @override
  String healthReasonEscalations(Object escalated, Object total) {
    return '$escalated escalation(s) out of $total task(s)';
  }

  @override
  String get activeFilter => 'Active';

  @override
  String get doneFilter => 'Done';

  @override
  String get dateRange => 'Date range';

  @override
  String get assignee => 'Assignee';

  @override
  String get todayPreset => 'Today';

  @override
  String get thisWeekPreset => 'This week';

  @override
  String get thisMonthPreset => 'This month';

  @override
  String get allTimePreset => 'All time';
}
