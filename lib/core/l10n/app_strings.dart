// lib/core/l10n/app_strings.dart
// Lightweight EN/AR string table. S.t('key') resolves in the active language.
// LocaleController sets S.lang and rebuilds MaterialApp (locale + RTL).

class S {
  S._();

  /// 'en' | 'ar' — set by LocaleController before rebuild.
  static String lang = 'en';

  static bool get isArabic => lang == 'ar';

  static String t(String key) =>
      (_map[lang] ?? _map['en']!)[key] ?? _map['en']![key] ?? key;

  static const Map<String, Map<String, String>> _map = {
    'en': {
      'dashboard': 'Dashboard',
      'tasks': 'Tasks',
      'calendar': 'Calendar',
      'finance': 'Finance',
      'settings': 'Settings',
      'attendance': 'Attendance',
      'expenses': 'Daily Expenses',
      'penalties': 'Penalties',
      'clients': 'Clients',
      'notifications': 'Notifications',
      'language': 'Language',
      'dark_mode': 'Dark Mode',
      'dark_mode_sub': 'Switch between light and dark theme',
      'sign_out': 'Sign Out',
      'team': 'TEAM',
      'preferences': 'PREFERENCES',
      'user_management': 'User Management',
      'penalty_management': 'Penalty Management',
      'save': 'Save',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'approve': 'Approve',
      'check_in': 'Check In',
      'check_out': 'Check Out',
      'add': 'Add',
      'edit': 'Edit',
      'close': 'Close',
      'search': 'Search',
      'today_status': "Today's Status",
    },
    'ar': {
      'dashboard': 'الرئيسية',
      'tasks': 'المهام',
      'calendar': 'التقويم',
      'finance': 'المالية',
      'settings': 'الإعدادات',
      'attendance': 'الحضور',
      'expenses': 'المصروفات اليومية',
      'penalties': 'الجزاءات',
      'clients': 'العملاء',
      'notifications': 'الإشعارات',
      'language': 'اللغة',
      'dark_mode': 'الوضع الداكن',
      'dark_mode_sub': 'التبديل بين الوضع الفاتح والداكن',
      'sign_out': 'تسجيل الخروج',
      'team': 'الفريق',
      'preferences': 'التفضيلات',
      'user_management': 'إدارة المستخدمين',
      'penalty_management': 'إدارة الجزاءات',
      'save': 'حفظ',
      'cancel': 'إلغاء',
      'delete': 'حذف',
      'approve': 'اعتماد',
      'check_in': 'تسجيل حضور',
      'check_out': 'تسجيل انصراف',
      'add': 'إضافة',
      'edit': 'تعديل',
      'close': 'إغلاق',
      'search': 'بحث',
      'today_status': 'حالة اليوم',
    },
  };
}
