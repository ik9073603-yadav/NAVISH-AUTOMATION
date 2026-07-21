// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'Navish';

  @override
  String get save => 'सेव करें';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get add => 'जोड़ें';

  @override
  String get delete => 'हटाएं';

  @override
  String get confirm => 'पुष्टि करें';

  @override
  String get done => 'हो गया';

  @override
  String get everyone => 'सभी';

  @override
  String get loginTagline => 'आपका पूरा कामकाज, अपने आप चलता रहे';

  @override
  String get emailLabel => 'ईमेल';

  @override
  String get passwordLabel => 'पासवर्ड';

  @override
  String get logIn => 'लॉग इन करें';

  @override
  String get forgotPassword => 'पासवर्ड भूल गए?';

  @override
  String get newCompanyCreateAccount => 'नई कंपनी? खाता बनाएं';

  @override
  String get forgotPasswordDialogTitle => 'पासवर्ड भूल गए';

  @override
  String get yourEmailLabel => 'आपका ईमेल';

  @override
  String get requestReset => 'रीसेट रिक्वेस्ट भेजें';

  @override
  String get createYourCompany => 'अपनी कंपनी बनाएं';

  @override
  String get companyNameLabel => 'कंपनी का नाम';

  @override
  String get yourNameOwnerLabel => 'आपका नाम (मालिक)';

  @override
  String get passwordHintLabel => 'पासवर्ड (8+ अक्षर)';

  @override
  String get phoneOptionalLabel => 'फ़ोन (वैकल्पिक)';

  @override
  String get acceptTermsPrefix => 'मैं स्वीकार करता/करती हूं ';

  @override
  String get termsAndConditions => 'नियम व शर्तें';

  @override
  String get andWord => ' और ';

  @override
  String get privacyPolicy => 'प्राइवेसी पॉलिसी';

  @override
  String get createAccount => 'खाता बनाएं';

  @override
  String get fillRequiredFieldsError =>
      'सभी ज़रूरी फ़ील्ड भरें (पासवर्ड: 8+ अक्षर)';

  @override
  String get acceptTermsError =>
      'आपको नियम व शर्तें और प्राइवेसी पॉलिसी स्वीकार करनी होंगी';

  @override
  String get navHome => 'होम';

  @override
  String get navStuck => 'अटका हुआ';

  @override
  String get navTasks => 'टास्क';

  @override
  String get navChecklists => 'चेकलिस्ट';

  @override
  String get navFlows => 'फ्लो';

  @override
  String get navInventory => 'स्टॉक';

  @override
  String get navAnalytics => 'एनालिटिक्स';

  @override
  String get navMore => 'और';

  @override
  String get navProfile => 'प्रोफ़ाइल';

  @override
  String get navCompanySettings => 'कंपनी सेटिंग्स';

  @override
  String get navPasswordResetRequests => 'पासवर्ड रीसेट रिक्वेस्ट';

  @override
  String get navNavishAdmin => 'नविश एडमिन';

  @override
  String get alerts => 'अलर्ट';

  @override
  String get noAlerts => 'कोई अलर्ट नहीं';

  @override
  String helloUser(Object name) {
    return 'नमस्ते, $name';
  }

  @override
  String get dueToday => 'आज ड्यू';

  @override
  String get noPendingTasks => 'कोई पेंडिंग टास्क नहीं 🎉';

  @override
  String get nothingHereYet => 'अभी यहां कुछ नहीं है';

  @override
  String get assignTaskAction => 'टास्क असाइन करें';

  @override
  String get addPerson => 'व्यक्ति जोड़ें';

  @override
  String get allTasks => 'सभी टास्क';

  @override
  String get team => 'टीम';

  @override
  String get noTasksAssignOne => 'अभी कोई टास्क नहीं है। एक असाइन करें 👇';

  @override
  String get doneChasingStopped => 'हो गया ✅  रिमाइंडर बंद।';

  @override
  String dueLabel(Object date) {
    return 'ड्यू: $date';
  }

  @override
  String chasedTimes(Object count, Object priority) {
    return '$count बार रिमाइंडर भेजा · $priority';
  }

  @override
  String get nothingStuckTitle => 'कुछ भी अटका नहीं है।';

  @override
  String get nothingStuckSubtitle => 'सब कुछ सही चल रहा है।';

  @override
  String get moduleTasks => 'टास्क';

  @override
  String get moduleChecklists => 'चेकलिस्ट';

  @override
  String get moduleFlows => 'फ्लो';

  @override
  String get moduleInventory => 'स्टॉक';

  @override
  String get profileTitle => 'प्रोफ़ाइल';

  @override
  String get basicInfo => 'बुनियादी जानकारी';

  @override
  String get nameLabel => 'नाम';

  @override
  String get nicknameLabel => 'निकनेम';

  @override
  String get designationLabel => 'पद';

  @override
  String get designationHint => 'जैसे मैनेजर, सुपरवाइज़र, मशीन ऑपरेटर';

  @override
  String get phoneLabel => 'फ़ोन';

  @override
  String get saveChanges => 'बदलाव सेव करें';

  @override
  String get profileUpdated => 'प्रोफ़ाइल अपडेट हो गई';

  @override
  String get account => 'खाता';

  @override
  String get roleLabel => 'रोल';

  @override
  String get departmentLabel => 'डिपार्टमेंट';

  @override
  String get notAssigned => 'तय नहीं है';

  @override
  String get preferences => 'प्राथमिकताएं';

  @override
  String get securityAndActivity => 'सुरक्षा और गतिविधि';

  @override
  String get changePassword => 'पासवर्ड बदलें';

  @override
  String get myPerformanceStats => 'मेरी परफॉर्मेंस';

  @override
  String get legalMenu => 'कानूनी जानकारी (नियम / प्राइवेसी / खाता हटाएं)';

  @override
  String get accountDeletionRequests => 'खाता हटाने के अनुरोध';

  @override
  String get logout => 'लॉगआउट';

  @override
  String get myPerformance => 'मेरी परफॉर्मेंस';

  @override
  String get activeTasksStat => 'एक्टिव टास्क';

  @override
  String get completedStat => 'पूरे हुए';

  @override
  String get onTimePctStat => 'समय पर %';

  @override
  String get escalatedStat => 'एस्केलेटेड';

  @override
  String get companySettingsTitle => 'कंपनी सेटिंग्स';

  @override
  String get companyProfile => 'कंपनी प्रोफ़ाइल';

  @override
  String get industryLabel => 'इंडस्ट्री';

  @override
  String get industryHint => 'जैसे मैन्युफैक्चरिंग, रिटेल';

  @override
  String get timezone => 'टाइमज़ोन';

  @override
  String get workingDays => 'काम के दिन';

  @override
  String get weekdayMon => 'सोम';

  @override
  String get weekdayTue => 'मंगल';

  @override
  String get weekdayWed => 'बुध';

  @override
  String get weekdayThu => 'गुरु';

  @override
  String get weekdayFri => 'शुक्र';

  @override
  String get weekdaySat => 'शनि';

  @override
  String get weekdaySun => 'रवि';

  @override
  String get shiftHours => 'शिफ्ट का समय';

  @override
  String startTime(Object time) {
    return 'शुरू: $time';
  }

  @override
  String endTime(Object time) {
    return 'खत्म: $time';
  }

  @override
  String get holidays => 'छुट्टियां';

  @override
  String get noHolidaysAdded => 'कोई छुट्टी जोड़ी नहीं गई';

  @override
  String get saveSettings => 'सेटिंग्स सेव करें';

  @override
  String get settingsSaved => 'सेटिंग्स सेव हो गईं';

  @override
  String get requests => 'रिक्वेस्ट';

  @override
  String get passwordResetRequestsSubtitle =>
      'जो कर्मचारी पासवर्ड भूल गए हैं उन्हें मंज़ूर या ख़ारिज करें';

  @override
  String get notifications => 'नोटिफिकेशन';

  @override
  String get pushNotificationsTitle => 'इस डिवाइस पर पुश नोटिफिकेशन';

  @override
  String get pushNotificationsSubtitle => 'रिमाइंडर, एस्केलेशन और अलर्ट';

  @override
  String get appearance => 'दिखावट';

  @override
  String get light => 'लाइट';

  @override
  String get dark => 'डार्क';

  @override
  String get system => 'सिस्टम';

  @override
  String get dataSection => 'डेटा';

  @override
  String get dataExportDescription =>
      'आपकी कंपनी के पूरे डेटा का एक्सपोर्ट — यूज़र, टास्क, चेकलिस्ट, फ्लो के ऑर्डर, स्टॉक।';

  @override
  String get preparingBackup => 'बैकअप तैयार हो रहा है...';

  @override
  String get downloadFullBackup => 'पूरा कंपनी बैकअप डाउनलोड करें';

  @override
  String get delayCostPerHourLabel => 'प्रति घंटा देरी की लागत (₹)';

  @override
  String get delayCostPerHourHint =>
      'देरी के एक काम के घंटे की कीमत — देर से पूरी हुई स्टेज की ₹ लागत निकालने के लिए इस्तेमाल होती है।';

  @override
  String get costOfDelayTooltipTitle => 'यह कैसे कैलकुलेट होता है?';

  @override
  String get costOfDelayTooltipBody =>
      'किसी स्टेज की लागत तभी बनती है जब उसकी डेडलाइन हो और वह देर से पूरी हो। देरी सिर्फ काम के घंटों में गिनी जाती है — रात, साप्ताहिक छुट्टी और छुट्टियां कभी नहीं गिनी जातीं। लागत = देरी के घंटे × आपकी ₹/घंटा दर। अगर दर सेट नहीं है, तो ऑर्डर की वैल्यू और फ्लो के प्लान किए घंटों से अनुमान लगाया जाता है। अगर दोनों में से कुछ भी सेट नहीं है, तो कोई ₹ आंकड़ा नहीं दिखाया जाता।';

  @override
  String get assignATask => 'टास्क असाइन करें';

  @override
  String get whatNeedsDoing => 'क्या करना है?';

  @override
  String get detailsOptional => 'जानकारी (वैकल्पिक)';

  @override
  String get assignTo => 'किसे असाइन करें';

  @override
  String get priorityLabel => 'प्रायोरिटी: ';

  @override
  String get priorityHigh => 'हाई';

  @override
  String get priorityNormal => 'नॉर्मल';

  @override
  String get priorityLow => 'लो';

  @override
  String get dueIn => 'कब तक: ';

  @override
  String get dueIn2Min => '2 मिनट (टेस्ट)';

  @override
  String get dueIn1Hour => '1 घंटा';

  @override
  String get dueIn4Hours => '4 घंटे';

  @override
  String get dueInTomorrow => 'कल';

  @override
  String get assigning => 'असाइन हो रहा है...';

  @override
  String assignToNPeople(Object count) {
    return '$count व्यक्ति को असाइन करें';
  }

  @override
  String get addAPerson => 'व्यक्ति जोड़ें';

  @override
  String get temporaryPassword => 'अस्थायी पासवर्ड';

  @override
  String get roleFieldLabel => 'रोल';

  @override
  String get roleEmployee => 'एम्प्लॉई';

  @override
  String get roleManager => 'मैनेजर';

  @override
  String get adding => 'जोड़ा जा रहा है...';

  @override
  String get inventoryPermissionsTooltip => 'स्टॉक परमिशन';

  @override
  String inventoryPermissionsTitle(Object name) {
    return 'स्टॉक परमिशन — $name';
  }

  @override
  String get canAddStock => 'स्टॉक जोड़ सकते हैं (स्टॉक IN)';

  @override
  String get canRemoveStock => 'स्टॉक निकाल सकते हैं (स्टॉक OUT)';

  @override
  String get noDataYet => 'अभी कोई डेटा नहीं';

  @override
  String noTasksYetRole(Object role) {
    return 'अभी कोई टास्क नहीं · $role';
  }

  @override
  String get activeFilter => 'एक्टिव';

  @override
  String get doneFilter => 'पूरे';

  @override
  String get dateRange => 'तारीख की रेंज';

  @override
  String get assignee => 'किसको';

  @override
  String get todayPreset => 'आज';

  @override
  String get thisWeekPreset => 'इस हफ्ते';

  @override
  String get thisMonthPreset => 'इस महीने';

  @override
  String get allTimePreset => 'सभी समय';
}
