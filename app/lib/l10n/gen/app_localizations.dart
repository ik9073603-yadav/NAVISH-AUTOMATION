import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Navish'**
  String get appTitle;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @everyone.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get everyone;

  /// No description provided for @loginTagline.
  ///
  /// In en, this message translates to:
  /// **'Your operations, on autopilot'**
  String get loginTagline;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @logIn.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get logIn;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @newCompanyCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'New company? Create an account'**
  String get newCompanyCreateAccount;

  /// No description provided for @forgotPasswordDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Forgot password'**
  String get forgotPasswordDialogTitle;

  /// No description provided for @yourEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Your email'**
  String get yourEmailLabel;

  /// No description provided for @requestReset.
  ///
  /// In en, this message translates to:
  /// **'Request reset'**
  String get requestReset;

  /// No description provided for @createYourCompany.
  ///
  /// In en, this message translates to:
  /// **'Create your company'**
  String get createYourCompany;

  /// No description provided for @companyNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Company name'**
  String get companyNameLabel;

  /// No description provided for @yourNameOwnerLabel.
  ///
  /// In en, this message translates to:
  /// **'Your name (owner)'**
  String get yourNameOwnerLabel;

  /// No description provided for @passwordHintLabel.
  ///
  /// In en, this message translates to:
  /// **'Password (8+ characters)'**
  String get passwordHintLabel;

  /// No description provided for @phoneOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone (optional)'**
  String get phoneOptionalLabel;

  /// No description provided for @acceptTermsPrefix.
  ///
  /// In en, this message translates to:
  /// **'I accept the '**
  String get acceptTermsPrefix;

  /// No description provided for @termsAndConditions.
  ///
  /// In en, this message translates to:
  /// **'Terms & Conditions'**
  String get termsAndConditions;

  /// No description provided for @andWord.
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get andWord;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @fillRequiredFieldsError.
  ///
  /// In en, this message translates to:
  /// **'Fill in all required fields (password: 8+ characters)'**
  String get fillRequiredFieldsError;

  /// No description provided for @acceptTermsError.
  ///
  /// In en, this message translates to:
  /// **'You must accept the Terms & Conditions and Privacy Policy'**
  String get acceptTermsError;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navStuck.
  ///
  /// In en, this message translates to:
  /// **'Stuck'**
  String get navStuck;

  /// No description provided for @navTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get navTasks;

  /// No description provided for @navChecklists.
  ///
  /// In en, this message translates to:
  /// **'Checklists'**
  String get navChecklists;

  /// No description provided for @navFlows.
  ///
  /// In en, this message translates to:
  /// **'Flows'**
  String get navFlows;

  /// No description provided for @navInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get navInventory;

  /// No description provided for @navAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get navAnalytics;

  /// No description provided for @navMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get navMore;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @navCompanySettings.
  ///
  /// In en, this message translates to:
  /// **'Company settings'**
  String get navCompanySettings;

  /// No description provided for @navPasswordResetRequests.
  ///
  /// In en, this message translates to:
  /// **'Password reset requests'**
  String get navPasswordResetRequests;

  /// No description provided for @navNavishAdmin.
  ///
  /// In en, this message translates to:
  /// **'Navish Admin'**
  String get navNavishAdmin;

  /// No description provided for @alerts.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get alerts;

  /// No description provided for @noAlerts.
  ///
  /// In en, this message translates to:
  /// **'No alerts'**
  String get noAlerts;

  /// No description provided for @helloUser.
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}'**
  String helloUser(Object name);

  /// No description provided for @dueToday.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get dueToday;

  /// No description provided for @noPendingTasks.
  ///
  /// In en, this message translates to:
  /// **'No pending tasks 🎉'**
  String get noPendingTasks;

  /// No description provided for @nothingHereYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get nothingHereYet;

  /// No description provided for @assignTaskAction.
  ///
  /// In en, this message translates to:
  /// **'Assign task'**
  String get assignTaskAction;

  /// No description provided for @addPerson.
  ///
  /// In en, this message translates to:
  /// **'Add person'**
  String get addPerson;

  /// No description provided for @allTasks.
  ///
  /// In en, this message translates to:
  /// **'All tasks'**
  String get allTasks;

  /// No description provided for @team.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get team;

  /// No description provided for @noTasksAssignOne.
  ///
  /// In en, this message translates to:
  /// **'No tasks yet. Assign one 👇'**
  String get noTasksAssignOne;

  /// No description provided for @doneChasingStopped.
  ///
  /// In en, this message translates to:
  /// **'Done ✅  Chasing stopped.'**
  String get doneChasingStopped;

  /// No description provided for @dueLabel.
  ///
  /// In en, this message translates to:
  /// **'Due: {date}'**
  String dueLabel(Object date);

  /// No description provided for @chasedTimes.
  ///
  /// In en, this message translates to:
  /// **'Chased {count} times · {priority}'**
  String chasedTimes(Object count, Object priority);

  /// No description provided for @nothingStuckTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing is stuck.'**
  String get nothingStuckTitle;

  /// No description provided for @nothingStuckSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Everything is running.'**
  String get nothingStuckSubtitle;

  /// No description provided for @moduleTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get moduleTasks;

  /// No description provided for @moduleChecklists.
  ///
  /// In en, this message translates to:
  /// **'Checklists'**
  String get moduleChecklists;

  /// No description provided for @moduleFlows.
  ///
  /// In en, this message translates to:
  /// **'Flows'**
  String get moduleFlows;

  /// No description provided for @moduleInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get moduleInventory;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @basicInfo.
  ///
  /// In en, this message translates to:
  /// **'Basic info'**
  String get basicInfo;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameLabel;

  /// No description provided for @nicknameLabel.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get nicknameLabel;

  /// No description provided for @designationLabel.
  ///
  /// In en, this message translates to:
  /// **'Post / designation'**
  String get designationLabel;

  /// No description provided for @designationHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Manager, Supervisor, Machine Operator'**
  String get designationHint;

  /// No description provided for @phoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phoneLabel;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @profileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated'**
  String get profileUpdated;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @roleLabel.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get roleLabel;

  /// No description provided for @departmentLabel.
  ///
  /// In en, this message translates to:
  /// **'Department'**
  String get departmentLabel;

  /// No description provided for @notAssigned.
  ///
  /// In en, this message translates to:
  /// **'Not assigned'**
  String get notAssigned;

  /// No description provided for @preferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferences;

  /// No description provided for @securityAndActivity.
  ///
  /// In en, this message translates to:
  /// **'Security & activity'**
  String get securityAndActivity;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePassword;

  /// No description provided for @myPerformanceStats.
  ///
  /// In en, this message translates to:
  /// **'My performance stats'**
  String get myPerformanceStats;

  /// No description provided for @legalMenu.
  ///
  /// In en, this message translates to:
  /// **'Legal (Terms / Privacy / Delete account)'**
  String get legalMenu;

  /// No description provided for @accountDeletionRequests.
  ///
  /// In en, this message translates to:
  /// **'Account deletion requests'**
  String get accountDeletionRequests;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @myPerformance.
  ///
  /// In en, this message translates to:
  /// **'My performance'**
  String get myPerformance;

  /// No description provided for @activeTasksStat.
  ///
  /// In en, this message translates to:
  /// **'Active tasks'**
  String get activeTasksStat;

  /// No description provided for @completedStat.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completedStat;

  /// No description provided for @onTimePctStat.
  ///
  /// In en, this message translates to:
  /// **'On-time %'**
  String get onTimePctStat;

  /// No description provided for @escalatedStat.
  ///
  /// In en, this message translates to:
  /// **'Escalated'**
  String get escalatedStat;

  /// No description provided for @companySettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Company settings'**
  String get companySettingsTitle;

  /// No description provided for @companyProfile.
  ///
  /// In en, this message translates to:
  /// **'Company profile'**
  String get companyProfile;

  /// No description provided for @industryLabel.
  ///
  /// In en, this message translates to:
  /// **'Industry'**
  String get industryLabel;

  /// No description provided for @industryHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Manufacturing, Retail'**
  String get industryHint;

  /// No description provided for @timezone.
  ///
  /// In en, this message translates to:
  /// **'Timezone'**
  String get timezone;

  /// No description provided for @workingDays.
  ///
  /// In en, this message translates to:
  /// **'Working days'**
  String get workingDays;

  /// No description provided for @weekdayMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get weekdayMon;

  /// No description provided for @weekdayTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get weekdayTue;

  /// No description provided for @weekdayWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get weekdayWed;

  /// No description provided for @weekdayThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get weekdayThu;

  /// No description provided for @weekdayFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get weekdayFri;

  /// No description provided for @weekdaySat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get weekdaySat;

  /// No description provided for @weekdaySun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get weekdaySun;

  /// No description provided for @shiftHours.
  ///
  /// In en, this message translates to:
  /// **'Shift hours'**
  String get shiftHours;

  /// No description provided for @startTime.
  ///
  /// In en, this message translates to:
  /// **'Start: {time}'**
  String startTime(Object time);

  /// No description provided for @endTime.
  ///
  /// In en, this message translates to:
  /// **'End: {time}'**
  String endTime(Object time);

  /// No description provided for @holidays.
  ///
  /// In en, this message translates to:
  /// **'Holidays'**
  String get holidays;

  /// No description provided for @noHolidaysAdded.
  ///
  /// In en, this message translates to:
  /// **'No holidays added'**
  String get noHolidaysAdded;

  /// No description provided for @saveSettings.
  ///
  /// In en, this message translates to:
  /// **'Save settings'**
  String get saveSettings;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get settingsSaved;

  /// No description provided for @requests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get requests;

  /// No description provided for @passwordResetRequestsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Approve or deny employees who forgot their password'**
  String get passwordResetRequestsSubtitle;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @pushNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Push notifications on this device'**
  String get pushNotificationsTitle;

  /// No description provided for @pushNotificationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Chases, escalations and alerts'**
  String get pushNotificationsSubtitle;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @dataSection.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get dataSection;

  /// No description provided for @dataExportDescription.
  ///
  /// In en, this message translates to:
  /// **'A full export of your company\'s data — users, tasks, checklists, flow monitoring orders, inventory.'**
  String get dataExportDescription;

  /// No description provided for @preparingBackup.
  ///
  /// In en, this message translates to:
  /// **'Preparing backup...'**
  String get preparingBackup;

  /// No description provided for @downloadFullBackup.
  ///
  /// In en, this message translates to:
  /// **'Download full company backup'**
  String get downloadFullBackup;

  /// No description provided for @delayCostPerHourLabel.
  ///
  /// In en, this message translates to:
  /// **'Delay cost per hour (₹)'**
  String get delayCostPerHourLabel;

  /// No description provided for @delayCostPerHourHint.
  ///
  /// In en, this message translates to:
  /// **'What one working hour of delay costs you — used to price late stages in ₹.'**
  String get delayCostPerHourHint;

  /// No description provided for @costOfDelayTooltipTitle.
  ///
  /// In en, this message translates to:
  /// **'How is this calculated?'**
  String get costOfDelayTooltipTitle;

  /// No description provided for @costOfDelayTooltipBody.
  ///
  /// In en, this message translates to:
  /// **'A stage costs money only if it has a deadline and finishes late. Delay is counted in working hours only — nights, week-offs and holidays never count. Cost = delay hours × your ₹/hr rate. If no rate is set, it\'s estimated instead from the order\'s value, spread over the flow\'s planned hours. If neither is set, no ₹ figure is shown.'**
  String get costOfDelayTooltipBody;

  /// No description provided for @assignATask.
  ///
  /// In en, this message translates to:
  /// **'Assign a task'**
  String get assignATask;

  /// No description provided for @whatNeedsDoing.
  ///
  /// In en, this message translates to:
  /// **'What needs doing?'**
  String get whatNeedsDoing;

  /// No description provided for @detailsOptional.
  ///
  /// In en, this message translates to:
  /// **'Details (optional)'**
  String get detailsOptional;

  /// No description provided for @assignTo.
  ///
  /// In en, this message translates to:
  /// **'Assign to'**
  String get assignTo;

  /// No description provided for @priorityLabel.
  ///
  /// In en, this message translates to:
  /// **'Priority: '**
  String get priorityLabel;

  /// No description provided for @priorityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get priorityHigh;

  /// No description provided for @priorityNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get priorityNormal;

  /// No description provided for @priorityLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get priorityLow;

  /// No description provided for @dueIn.
  ///
  /// In en, this message translates to:
  /// **'Due in: '**
  String get dueIn;

  /// No description provided for @dueIn2Min.
  ///
  /// In en, this message translates to:
  /// **'2 min (test)'**
  String get dueIn2Min;

  /// No description provided for @dueIn1Hour.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get dueIn1Hour;

  /// No description provided for @dueIn4Hours.
  ///
  /// In en, this message translates to:
  /// **'4 hours'**
  String get dueIn4Hours;

  /// No description provided for @dueInTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get dueInTomorrow;

  /// No description provided for @assigning.
  ///
  /// In en, this message translates to:
  /// **'Assigning...'**
  String get assigning;

  /// No description provided for @assignToNPeople.
  ///
  /// In en, this message translates to:
  /// **'Assign to {count} person(s)'**
  String assignToNPeople(Object count);

  /// No description provided for @addAPerson.
  ///
  /// In en, this message translates to:
  /// **'Add a person'**
  String get addAPerson;

  /// No description provided for @temporaryPassword.
  ///
  /// In en, this message translates to:
  /// **'Temporary password'**
  String get temporaryPassword;

  /// No description provided for @roleFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get roleFieldLabel;

  /// No description provided for @roleEmployee.
  ///
  /// In en, this message translates to:
  /// **'Employee'**
  String get roleEmployee;

  /// No description provided for @roleManager.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get roleManager;

  /// No description provided for @adding.
  ///
  /// In en, this message translates to:
  /// **'Adding...'**
  String get adding;

  /// No description provided for @inventoryPermissionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Inventory permissions'**
  String get inventoryPermissionsTooltip;

  /// No description provided for @inventoryPermissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Inventory permissions — {name}'**
  String inventoryPermissionsTitle(Object name);

  /// No description provided for @canAddStock.
  ///
  /// In en, this message translates to:
  /// **'Can add stock (Stock IN)'**
  String get canAddStock;

  /// No description provided for @canRemoveStock.
  ///
  /// In en, this message translates to:
  /// **'Can remove stock (Stock OUT)'**
  String get canRemoveStock;

  /// No description provided for @noDataYet.
  ///
  /// In en, this message translates to:
  /// **'No data yet'**
  String get noDataYet;

  /// No description provided for @noTasksYetRole.
  ///
  /// In en, this message translates to:
  /// **'No tasks yet · {role}'**
  String noTasksYetRole(Object role);

  /// No description provided for @companyHealthScore.
  ///
  /// In en, this message translates to:
  /// **'Company Health Score'**
  String get companyHealthScore;

  /// No description provided for @healthBandHealthy.
  ///
  /// In en, this message translates to:
  /// **'Healthy'**
  String get healthBandHealthy;

  /// No description provided for @healthBandNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get healthBandNeedsAttention;

  /// No description provided for @healthBandAtRisk.
  ///
  /// In en, this message translates to:
  /// **'At risk'**
  String get healthBandAtRisk;

  /// No description provided for @healthTrendUpBy.
  ///
  /// In en, this message translates to:
  /// **'+{delta} vs last period'**
  String healthTrendUpBy(Object delta);

  /// No description provided for @healthTrendDownBy.
  ///
  /// In en, this message translates to:
  /// **'{delta} vs last period'**
  String healthTrendDownBy(Object delta);

  /// No description provided for @healthTrendFlat.
  ///
  /// In en, this message translates to:
  /// **'No change vs last period'**
  String get healthTrendFlat;

  /// No description provided for @healthNoTrendYet.
  ///
  /// In en, this message translates to:
  /// **'Not enough history yet'**
  String get healthNoTrendYet;

  /// No description provided for @healthBreakdownTitle.
  ///
  /// In en, this message translates to:
  /// **'Health Score breakdown'**
  String get healthBreakdownTitle;

  /// No description provided for @healthBiggestDrags.
  ///
  /// In en, this message translates to:
  /// **'Biggest drags'**
  String get healthBiggestDrags;

  /// No description provided for @healthNoDrags.
  ///
  /// In en, this message translates to:
  /// **'Nothing dragging your score down 🎉'**
  String get healthNoDrags;

  /// No description provided for @healthWeightLabel.
  ///
  /// In en, this message translates to:
  /// **'{pct}% of score'**
  String healthWeightLabel(Object pct);

  /// No description provided for @healthExcludedNoData.
  ///
  /// In en, this message translates to:
  /// **'Excluded — no data yet'**
  String get healthExcludedNoData;

  /// No description provided for @healthWindowLabel.
  ///
  /// In en, this message translates to:
  /// **'Last {days} days'**
  String healthWindowLabel(Object days);

  /// No description provided for @healthHowCalculatedTitle.
  ///
  /// In en, this message translates to:
  /// **'How is this score calculated?'**
  String get healthHowCalculatedTitle;

  /// No description provided for @healthHowCalculatedBody.
  ///
  /// In en, this message translates to:
  /// **'Each component below is scored 0-100 and combined using its weight. A component with no data yet (e.g. no checklists) is left out and the other weights are scaled up to fill the gap — it\'s never scored a fake 0. Tap \"Biggest drags\" to jump straight to what needs attention.'**
  String get healthHowCalculatedBody;

  /// No description provided for @healthComponentOnTime.
  ///
  /// In en, this message translates to:
  /// **'On-time performance'**
  String get healthComponentOnTime;

  /// No description provided for @healthComponentStuckLoad.
  ///
  /// In en, this message translates to:
  /// **'Stuck / overdue load'**
  String get healthComponentStuckLoad;

  /// No description provided for @healthComponentChecklist.
  ///
  /// In en, this message translates to:
  /// **'Checklist compliance'**
  String get healthComponentChecklist;

  /// No description provided for @healthComponentInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory health'**
  String get healthComponentInventory;

  /// No description provided for @healthComponentEscalations.
  ///
  /// In en, this message translates to:
  /// **'Escalations'**
  String get healthComponentEscalations;

  /// No description provided for @healthReasonOnTime.
  ///
  /// In en, this message translates to:
  /// **'{pct}% on-time — {late} of {total} finished late'**
  String healthReasonOnTime(Object pct, Object late, Object total);

  /// No description provided for @healthReasonStuckLoadZero.
  ///
  /// In en, this message translates to:
  /// **'Nothing stuck or overdue right now'**
  String get healthReasonStuckLoadZero;

  /// No description provided for @healthReasonStuckLoad.
  ///
  /// In en, this message translates to:
  /// **'{count} item(s) stuck or overdue right now'**
  String healthReasonStuckLoad(Object count);

  /// No description provided for @healthReasonChecklist.
  ///
  /// In en, this message translates to:
  /// **'{pct}% compliance — {done} of {total} completed'**
  String healthReasonChecklist(Object pct, Object done, Object total);

  /// No description provided for @healthReasonInventory.
  ///
  /// In en, this message translates to:
  /// **'{alertCount} low/over-stock item(s), {deadPct}% of stock value is dead'**
  String healthReasonInventory(Object alertCount, Object deadPct);

  /// No description provided for @healthReasonEscalations.
  ///
  /// In en, this message translates to:
  /// **'{escalated} escalation(s) out of {total} task(s)'**
  String healthReasonEscalations(Object escalated, Object total);

  /// No description provided for @activeFilter.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get activeFilter;

  /// No description provided for @doneFilter.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get doneFilter;

  /// No description provided for @dateRange.
  ///
  /// In en, this message translates to:
  /// **'Date range'**
  String get dateRange;

  /// No description provided for @assignee.
  ///
  /// In en, this message translates to:
  /// **'Assignee'**
  String get assignee;

  /// No description provided for @todayPreset.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get todayPreset;

  /// No description provided for @thisWeekPreset.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get thisWeekPreset;

  /// No description provided for @thisMonthPreset.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get thisMonthPreset;

  /// No description provided for @allTimePreset.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get allTimePreset;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
