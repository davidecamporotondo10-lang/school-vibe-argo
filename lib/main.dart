import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT', null);
  await NotificationService.instance.init();
  final storage = await StorageService.init();
  runApp(SchoolVibeApp(storage: storage));
}

Color alphaCol(Color c, double opacity) =>
    c.withAlpha((opacity.clamp(0.0, 1.0) * 255).round());

BoxDecoration cardDeco(Color card, Color border, [double radius = 24]) =>
    BoxDecoration(
      color: card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border),
    );

InputDecoration fieldDeco(String label, {IconData? icon, Widget? suffix}) =>
    InputDecoration(
      labelText: label,
      prefixIcon: icon != null ? Icon(icon, size: 19) : null,
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    );

String fmtMin(int totalMinutes) {
  final m = totalMinutes.clamp(0, 23 * 60 + 59);
  final hh = (m ~/ 60).toString().padLeft(2, '0');
  final mm = (m % 60).toString().padLeft(2, '0');
  return '$hh:$mm';
}

(int, int)? parseSlotMinutes(String raw) {
  final reg = RegExp(r'(\d{1,2})(?:[:.](\d{2}))?\s*[-–/]\s*(\d{1,2})(?:[:.](\d{2}))?');
  final m = reg.firstMatch(raw);
  if (m == null) return null;
  final h1 = int.tryParse(m.group(1) ?? '');
  final m1 = int.tryParse(m.group(2) ?? '0') ?? 0;
  final h2 = int.tryParse(m.group(3) ?? '');
  final m2 = int.tryParse(m.group(4) ?? '0') ?? 0;
  if (h1 == null || h2 == null) return null;
  return (h1 * 60 + m1, h2 * 60 + m2);
}

Color subjectAccent(String subject) {
  const palette = [
    Color(0xFF3D85C6),
    Color(0xFF635BFF),
    Color(0xFF00C2A8),
    Color(0xFFFF6B6B),
    Color(0xFFFFA502),
    Color(0xFFA855F7),
    Color(0xFFEC4899),
    Color(0xFF10B981),
  ];
  final s = subject.trim().toLowerCase();
  if (s.isEmpty) return VibePalette.primary;
  final seed = s.codeUnits.fold<int>(0, (a, c) => a + c);
  return palette[seed % palette.length];
}

class VibePalette {
  static const Color capBlue = Color(0xFF3D85C6);
  static const Color primary = Color(0xFF635BFF);
  static const Color primaryGlow = Color(0xFF8B5CF6);
  static const Color verificaRed = Color(0xFFFF4757);
  static const Color interrogazioneAmber = Color(0xFFFFA502);
  static const Color okGreen = Color(0xFF00C2A8);
  static const Color altroPurple = Color(0xFFA855F7);

  static const Color darkBg = Color(0xFF080C16);
  static const Color darkCard = Color(0xFF111728);
  static const Color darkCardAlt = Color(0xFF161E33);
  static const Color darkBorder = Color(0xFF1F2A44);

  static const Color lightBg = Color(0xFFF3F6FC);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightCardAlt = Color(0xFFEEF2FA);
  static const Color lightBorder = Color(0xFFDCE3F0);

  static ThemeData _base(Brightness b, Color bg, Color card, Color border, Color snackBg) {
    final dark = b == Brightness.dark;
    final onSurface = dark ? const Color(0xFFF2F5FA) : const Color(0xFF0B1220);
    final mutedInk = dark ? const Color(0xFF98A6BC) : const Color(0xFF64748B);
    final fieldFill = dark ? const Color(0xFF151D30) : const Color(0xFFF3F6FC);

    final base = ThemeData(
      useMaterial3: true,
      brightness: b,
      splashFactory: InkRipple.splashFactory,
      colorScheme: ColorScheme(
        brightness: b,
        primary: primary,
        onPrimary: Colors.white,
        secondary: primaryGlow,
        onSecondary: Colors.white,
        error: verificaRed,
        onError: Colors.white,
        surface: card,
        onSurface: onSurface,
      ),
      scaffoldBackgroundColor: bg,
      cardColor: card,
      dividerColor: border,
    );

    return base.copyWith(
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: snackBg,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF222C44) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(9),
        ),
        textStyle:
            const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
        waitDuration: const Duration(milliseconds: 450),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: TextStyle(color: mutedInk, fontSize: 13.5, fontWeight: FontWeight.w500),
        floatingLabelStyle:
            const TextStyle(color: primary, fontSize: 12.5, fontWeight: FontWeight.w800),
        prefixIconColor: mutedInk,
        suffixIconColor: mutedInk,
        hintStyle: TextStyle(color: mutedInk, fontSize: 13.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: alphaCol(verificaRed, 0.7)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          foregroundColor: dark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: dark ? const Color(0xFFA5B4FC) : primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: fieldFill,
        selectedColor: alphaCol(primary, dark ? 0.24 : 0.16),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: onSurface),
        secondaryLabelStyle:
            const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: primary),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle:
            TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: onSurface),
        contentTextStyle: TextStyle(fontSize: 13.5, height: 1.45, color: mutedInk),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: card,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: onSurface),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: alphaCol(primary, 0.18),
        thumbColor: primary,
        overlayColor: alphaCol(primary, 0.16),
        valueIndicatorColor: primary,
      ),
    );
  }

  static ThemeData darkTheme() => _base(Brightness.dark, darkBg, darkCard, darkBorder, darkCardAlt);
  static ThemeData lightTheme() =>
      _base(Brightness.light, lightBg, lightCard, lightBorder, const Color(0xFF0F172A));
}

// ============================================================================
// MODELLI DATI (EVENTI, NOTIFICHE PERSONALIZZATE, SCANSIONE ORARIA SCUOLA)
// ============================================================================

enum EventCategory { verifica, interrogazione, altro }

extension EventCategoryX on EventCategory {
  String get label => const {
        EventCategory.verifica: 'Verifica',
        EventCategory.interrogazione: 'Interrogazione',
        EventCategory.altro: 'Altro',
      }[this]!;

  Color get color => const {
        EventCategory.verifica: VibePalette.verificaRed,
        EventCategory.interrogazione: VibePalette.interrogazioneAmber,
        EventCategory.altro: VibePalette.altroPurple,
      }[this]!;
}

enum EventReminderMode {
  defaultBoth,
  dayBefore17,
  twoDaysBefore17,
  morningOf,
  hourBefore,
  custom,
  none,
}

extension EventReminderModeX on EventReminderMode {
  String get key => const {
        EventReminderMode.defaultBoth: 'default_both',
        EventReminderMode.dayBefore17: 'day_before_17',
        EventReminderMode.twoDaysBefore17: 'two_days_17',
        EventReminderMode.morningOf: 'morning_0715',
        EventReminderMode.hourBefore: 'hour_before',
        EventReminderMode.custom: 'custom',
        EventReminderMode.none: 'none',
      }[this]!;

  String get label => const {
        EventReminderMode.defaultBoth: 'Giorno prima (17:00) + Mattina (07:15)',
        EventReminderMode.dayBefore17: 'Giorno prima alle 17:00',
        EventReminderMode.twoDaysBefore17: '2 giorni prima alle 17:00',
        EventReminderMode.morningOf: 'Mattina stessa alle 07:15',
        EventReminderMode.hourBefore: '1 ora prima dell\'evento',
        EventReminderMode.custom: 'Data e ora personalizzata',
        EventReminderMode.none: 'Nessuna notifica',
      }[this]!;

  static EventReminderMode fromKey(String? raw) {
    for (final m in EventReminderMode.values) {
      if (m.key == raw) return m;
    }
    return EventReminderMode.defaultBoth;
  }
}

class SchoolEvent {
  final String id, title, subject, notes;
  final DateTime dateTime;
  final EventCategory category;
  final bool completed, fromArgo, editedByUser;
  final EventReminderMode reminderMode;
  final DateTime? customReminderAt;

  const SchoolEvent({
    required this.id,
    required this.title,
    required this.subject,
    this.notes = '',
    required this.dateTime,
    required this.category,
    this.completed = false,
    this.fromArgo = false,
    this.editedByUser = false,
    this.reminderMode = EventReminderMode.defaultBoth,
    this.customReminderAt,
  });

  SchoolEvent copyWith({
    String? title,
    String? subject,
    String? notes,
    DateTime? dateTime,
    EventCategory? category,
    bool? completed,
    bool? editedByUser,
    EventReminderMode? reminderMode,
    DateTime? customReminderAt,
  }) =>
      SchoolEvent(
        id: id,
        title: title ?? this.title,
        subject: subject ?? this.subject,
        notes: notes ?? this.notes,
        dateTime: dateTime ?? this.dateTime,
        category: category ?? this.category,
        completed: completed ?? this.completed,
        fromArgo: fromArgo,
        editedByUser: editedByUser ?? this.editedByUser,
        reminderMode: reminderMode ?? this.reminderMode,
        customReminderAt: customReminderAt ?? this.customReminderAt,
      );

  String reminderSummary() {
    switch (reminderMode) {
      case EventReminderMode.defaultBoth:
        return 'Notifica: giorno prima 17:00 + 07:15';
      case EventReminderMode.dayBefore17:
        return 'Notifica: giorno prima 17:00';
      case EventReminderMode.twoDaysBefore17:
        return 'Notifica: 2 giorni prima 17:00';
      case EventReminderMode.morningOf:
        return 'Notifica: mattina 07:15';
      case EventReminderMode.hourBefore:
        return 'Notifica: 1 ora prima';
      case EventReminderMode.custom:
        if (customReminderAt == null) return 'Notifica personalizzata';
        return 'Notifica: ${DateFormat('dd/MM HH:mm').format(customReminderAt!)}';
      case EventReminderMode.none:
        return 'Nessuna notifica';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subject': subject,
        'notes': notes,
        'dateTime': dateTime.toIso8601String(),
        'category': category.name,
        'completed': completed,
        'fromArgo': fromArgo,
        'editedByUser': editedByUser,
        'reminderMode': reminderMode.key,
        if (customReminderAt != null) 'customReminderAt': customReminderAt!.toIso8601String(),
      };

  factory SchoolEvent.fromJson(Map<String, dynamic> j) {
    final cat = EventCategory.values.firstWhere(
      (e) => e.name == '${j['category'] ?? 'altro'}',
      orElse: () => EventCategory.altro,
    );
    final customRaw = j['customReminderAt'] as String?;
    return SchoolEvent(
      id: '${j['id'] ?? ''}',
      title: '${j['title'] ?? ''}',
      subject: '${j['subject'] ?? 'Materia'}',
      notes: '${j['notes'] ?? ''}',
      dateTime: DateTime.tryParse('${j['dateTime'] ?? ''}') ?? DateTime.now(),
      category: cat,
      completed: j['completed'] as bool? ?? false,
      fromArgo: j['fromArgo'] as bool? ?? false,
      editedByUser: j['editedByUser'] as bool? ?? false,
      reminderMode: EventReminderModeX.fromKey(j['reminderMode'] as String?),
      customReminderAt: customRaw != null ? DateTime.tryParse(customRaw) : null,
    );
  }
}

class SchoolGrade {
  final String id, subject, type, description;
  final double value, weight;
  final DateTime date;
  final bool fromArgo;

  const SchoolGrade({
    required this.id,
    required this.subject,
    required this.value,
    this.weight = 1.0,
    this.type = 'Scritto',
    this.description = '',
    required this.date,
    this.fromArgo = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': id.isEmpty ? '' : subject,
        'value': value,
        'weight': weight,
        'type': type,
        'description': description,
        'date': date.toIso8601String(),
        'fromArgo': fromArgo,
      };

  factory SchoolGrade.fromJson(Map<String, dynamic> j) => SchoolGrade(
        id: '${j['id'] ?? ''}',
        subject: '${j['subject'] ?? 'Materia'}',
        value: (j['value'] as num?)?.toDouble() ?? 6.0,
        weight: (j['weight'] as num?)?.toDouble() ?? 1.0,
        type: '${j['type'] ?? 'Scritto'}',
        description: '${j['description'] ?? ''}',
        date: DateTime.tryParse('${j['date'] ?? ''}') ?? DateTime.now(),
        fromArgo: j['fromArgo'] as bool? ?? false,
      );
}

class LessonSlot {
  final String subject, time;
  const LessonSlot({this.subject = '', this.time = ''});

  bool isAfternoon(int slotIndex) {
    final parsed = parseSlotMinutes(time);
    if (parsed != null) return parsed.$1 >= (13 * 60 + 45);
    return slotIndex >= 6;
  }

  Map<String, dynamic> toJson() => {'subject': subject, 'time': time};

  factory LessonSlot.fromJson(Map<String, dynamic> j, int idx) {
    final rawTime = '${j['time'] ?? ''}'.trim();
    return LessonSlot(
      subject: '${j['subject'] ?? ''}',
      time: rawTime.isNotEmpty ? rawTime : DaySchedule.defaultSlotTime(idx),
    );
  }
}

class DaySchedule {
  static const List<String> officialTimes = [
    '07:55 - 08:55',
    '08:55 - 09:55',
    '09:55 - 10:50',
    '11:00 - 11:55',
    '11:55 - 12:50',
    '12:50 - 13:45',
    '14:30 - 15:30',
    '15:30 - 16:30',
  ];

  final List<LessonSlot> slots;
  const DaySchedule({required this.slots});

  static String defaultSlotTime(int idx) {
    if (idx >= 0 && idx < officialTimes.length) return officialTimes[idx];
    final extra = idx - 6;
    final sh = (14 + extra).clamp(0, 22);
    return '${sh.toString().padLeft(2, '0')}:30 - ${(sh + 1).toString().padLeft(2, '0')}:30';
  }

  static (int, int) officialBounds(int idx) =>
      parseSlotMinutes(defaultSlotTime(idx)) ?? (8 * 60, 9 * 60);

  int get afternoonCount =>
      [for (int i = 0; i < slots.length; i++) if (slots[i].isAfternoon(i)) 1].length;

  factory DaySchedule.initial() => DaySchedule(
        slots: List.generate(6, (i) => LessonSlot(time: defaultSlotTime(i))),
      );

  Map<String, dynamic> toJson() => {
        'slots': slots.map((e) => e.toJson()).toList(),
      };

  factory DaySchedule.fromJson(Map<String, dynamic> j) {
    if (j['slots'] is List) {
      final raw = j['slots'] as List;
      return DaySchedule(
        slots: [
          for (int i = 0; i < raw.length; i++)
            LessonSlot.fromJson(raw[i] as Map<String, dynamic>, i),
        ],
      );
    }
    return DaySchedule.initial();
  }

  factory DaySchedule.migrateLegacy(Map<String, dynamic> legacy) {
    final m = (legacy['morning'] as List?) ?? const [];
    final a = (legacy['afternoon'] as List?) ?? const [];
    final migrated = List.generate(6, (i) {
      if (i < m.length && m[i] is Map<String, dynamic>) {
        final item = m[i] as Map<String, dynamic>;
        return LessonSlot(
          subject: '${item['subject'] ?? ''}',
          time: defaultSlotTime(i),
        );
      }
      return LessonSlot(time: defaultSlotTime(i));
    });
    for (int j = 0; j < a.length; j++) {
      if (a[j] is Map<String, dynamic>) {
        final item = a[j] as Map<String, dynamic>;
        migrated.add(LessonSlot(
          subject: '${item['subject'] ?? ''}',
          time: defaultSlotTime(6 + j),
        ));
      }
    }
    return DaySchedule(slots: migrated);
  }
}

class ArgoCredentials {
  final String schoolCode, username, password, studentName, refreshToken;
  final DateTime? lastSync;

  const ArgoCredentials({
    this.schoolCode = '',
    this.username = '',
    this.password = '',
    this.studentName = '',
    this.refreshToken = '',
    this.lastSync,
  });
}

// ============================================================================
// STORAGE OFFLINE & NOTIFICHE CON LOGO APP (ic_stat_school + ic_notif_logo)
// ============================================================================

class StorageService {
  static const _kEvents = 'sv_events_v1';
  static const _kGrades = 'sv_grades_v1';
  static const _kTimetableV2 = 'sv_timetable_v2';
  static const _kTimetableLegacy = 'sv_timetable_v1';
  static const _kDeletedArgo = 'sv_deleted_argo_v1';
  static const _kDark = 'sv_dark_v1';
  static const _kNotify = 'sv_notify_v1';
  static const _kMorningNotify = 'sv_morning_notify_v1';
  static const _kSchool = 'sv_argo_school';
  static const _kUser = 'sv_argo_user';
  static const _kPass = 'sv_argo_pass';
  static const _kStudent = 'sv_argo_student';
  static const _kRefresh = 'sv_argo_refresh';
  static const _kSync = 'sv_argo_sync';

  final SharedPreferences _p;
  StorageService._(this._p);

  static Future<StorageService> init() async =>
      StorageService._(await SharedPreferences.getInstance());

  bool loadDarkMode() => _p.getBool(_kDark) ?? true;
  Future<void> saveDarkMode(bool v) => _p.setBool(_kDark, v);

  bool loadNotifyEnabled() => _p.getBool(_kNotify) ?? true;
  Future<void> saveNotifyEnabled(bool v) => _p.setBool(_kNotify, v);

  bool loadMorningNotifyEnabled() => _p.getBool(_kMorningNotify) ?? true;
  Future<void> saveMorningNotifyEnabled(bool v) => _p.setBool(_kMorningNotify, v);

  Set<String> loadDeletedArgoIds() => (_p.getStringList(_kDeletedArgo) ?? const []).toSet();
  Future<void> saveDeletedArgoIds(Set<String> ids) =>
      _p.setStringList(_kDeletedArgo, ids.toList());

  List<SchoolEvent> loadEvents() {
    final raw = _p.getString(_kEvents);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = <SchoolEvent>[];
      for (final item in (jsonDecode(raw) as List)) {
        if (item is! Map<String, dynamic>) continue;
        final id = '${item['id'] ?? ''}';
        if (item['category'] == 'compito' ||
            id.startsWith('argo_c_') ||
            id.startsWith('sn_c_') ||
            id == 'demo_3') {
          continue;
        }
        list.add(SchoolEvent.fromJson(item));
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveEvents(List<SchoolEvent> list) =>
      _p.setString(_kEvents, jsonEncode(list.map((e) => e.toJson()).toList()));

  List<SchoolGrade> loadGrades() {
    final raw = _p.getString(_kGrades);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((g) => SchoolGrade.fromJson(g as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveGrades(List<SchoolGrade> list) =>
      _p.setString(_kGrades, jsonEncode(list.map((g) => g.toJson()).toList()));

  Map<int, DaySchedule> loadTimetable() {
    final out = {for (int d = 1; d <= 5; d++) d: DaySchedule.initial()};
    final rawV2 = _p.getString(_kTimetableV2);
    if (rawV2 != null && rawV2.isNotEmpty) {
      try {
        final map = jsonDecode(rawV2) as Map<String, dynamic>;
        for (int d = 1; d <= 5; d++) {
          final v = map['$d'];
          if (v is Map<String, dynamic>) out[d] = DaySchedule.fromJson(v);
        }
        return out;
      } catch (_) {}
    }

    final legacyRaw = _p.getString(_kTimetableLegacy);
    if (legacyRaw != null && legacyRaw.isNotEmpty) {
      try {
        final map = jsonDecode(legacyRaw) as Map<String, dynamic>;
        for (int d = 1; d <= 5; d++) {
          final v = map['$d'];
          if (v is Map<String, dynamic>) out[d] = DaySchedule.migrateLegacy(v);
        }
      } catch (_) {}
    }
    return out;
  }

  Future<void> saveTimetable(Map<int, DaySchedule> map) => _p.setString(
        _kTimetableV2,
        jsonEncode({
          for (final e in map.entries)
            if (e.key >= 1 && e.key <= 5) '${e.key}': e.value.toJson(),
        }),
      );

  ArgoCredentials loadArgo() {
    final s = _p.getString(_kSync);
    return ArgoCredentials(
      schoolCode: _p.getString(_kSchool) ?? '',
      username: _p.getString(_kUser) ?? '',
      password: _p.getString(_kPass) ?? '',
      studentName: _p.getString(_kStudent) ?? '',
      refreshToken: _p.getString(_kRefresh) ?? '',
      lastSync: s != null ? DateTime.tryParse(s) : null,
    );
  }

  Future<void> saveArgo(ArgoCredentials c) async {
    await _p.setString(_kSchool, c.schoolCode.trim().toUpperCase());
    await _p.setString(_kUser, c.username.trim());
    await _p.setString(_kPass, c.password);
    await _p.setString(_kStudent, c.studentName);
    await _p.setString(_kRefresh, c.refreshToken);
    if (c.lastSync != null) await _p.setString(_kSync, c.lastSync!.toIso8601String());
  }

  Future<void> clearAll() async {
    for (final k in [_kEvents, _kGrades, _kDeletedArgo, _kStudent, _kRefresh, _kSync]) {
      await _p.remove(k);
    }
  }
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const int _dailyTimetableId = 990720;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Europe/Rome'));
    } catch (_) {}
    try {
      await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_school'),
      ));
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {}
  }

  NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails(
          'calendario_scuola_v2',
          'Orario & Promemoria Scolastici',
          channelDescription: 'Notifica orario alle 07:20 e promemoria impegni',
          icon: 'ic_stat_school',
          color: VibePalette.capBlue,
          largeIcon: DrawableResourceAndroidBitmap('ic_notif_logo'),
          importance: Importance.max,
          priority: Priority.high,
        ),
      );

  Future<void> sendTestNotification() async {
    if (!_ready) await init();
    await _plugin.show(
      999001,
      'Calendario Scuola · Notifiche attive',
      'Ecco l\'anteprima della notifica con il logo di Calendario Scuola.',
      _details(),
    );
  }

  Future<void> syncNotifications(
    List<SchoolEvent> events, {
    required bool enabled,
    bool morningEnabled = true,
  }) async {
    if (!_ready) await init();
    try {
      await _plugin.cancelAll();
    } catch (_) {}

    if (morningEnabled) {
      final nowTz = tz.TZDateTime.now(tz.local);
      var next0720 = tz.TZDateTime(tz.local, nowTz.year, nowTz.month, nowTz.day, 7, 20);
      if (!next0720.isAfter(nowTz)) {
        next0720 = next0720.add(const Duration(days: 1));
      }
      await _scheduleTz(
        _dailyTimetableId,
        'Orario scolastico di oggi',
        'Buongiorno! Apri Calendario Scuola per controllare l\'orario di oggi.',
        next0720,
        matchComponents: DateTimeComponents.time,
      );
    }

    if (!enabled) return;

    final now = DateTime.now();
    for (int i = 0; i < events.length; i++) {
      final ev = events[i];
      if (ev.completed || ev.reminderMode == EventReminderMode.none) continue;

      final baseDay = DateTime(ev.dateTime.year, ev.dateTime.month, ev.dateTime.day);
      final baseId = 1000 + i * 3;
      final titleDomani = 'Domani: ${ev.category.label} di ${ev.subject}';
      final titleOggi = 'Oggi: ${ev.category.label} di ${ev.subject}';
      final titleGen = '${ev.category.label} di ${ev.subject}';

      switch (ev.reminderMode) {
        case EventReminderMode.defaultBoth:
          final d1 = baseDay.subtract(const Duration(days: 1)).add(const Duration(hours: 17));
          final d2 = baseDay.add(const Duration(hours: 7, minutes: 15));
          if (d1.isAfter(now)) await _scheduleDate(baseId, titleDomani, ev.title, d1);
          if (d2.isAfter(now)) await _scheduleDate(baseId + 1, titleOggi, ev.title, d2);
          break;
        case EventReminderMode.dayBefore17:
          final d1 = baseDay.subtract(const Duration(days: 1)).add(const Duration(hours: 17));
          if (d1.isAfter(now)) await _scheduleDate(baseId, titleDomani, ev.title, d1);
          break;
        case EventReminderMode.twoDaysBefore17:
          final d1 = baseDay.subtract(const Duration(days: 2)).add(const Duration(hours: 17));
          if (d1.isAfter(now)) {
            await _scheduleDate(baseId, 'Tra 2 giorni: $titleGen', ev.title, d1);
          }
          break;
        case EventReminderMode.morningOf:
          final d1 = baseDay.add(const Duration(hours: 7, minutes: 15));
          if (d1.isAfter(now)) await _scheduleDate(baseId, titleOggi, ev.title, d1);
          break;
        case EventReminderMode.hourBefore:
          final d1 = ev.dateTime.subtract(const Duration(hours: 1));
          if (d1.isAfter(now)) {
            await _scheduleDate(baseId, 'Tra 1 ora: $titleGen', ev.title, d1);
          }
          break;
        case EventReminderMode.custom:
          final custom = ev.customReminderAt;
          if (custom != null && custom.isAfter(now)) {
            await _scheduleDate(baseId, 'Promemoria: $titleGen', ev.title, custom);
          }
          break;
        case EventReminderMode.none:
          break;
      }
    }
  }

  Future<void> _scheduleDate(int id, String title, String body, DateTime when) =>
      _scheduleTz(id, title, body, tz.TZDateTime.from(when, tz.local));

  Future<void> _scheduleTz(
    int id,
    String title,
    String body,
    tz.TZDateTime when, {
    DateTimeComponents? matchComponents,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        _details(),
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: matchComponents,
      );
    } catch (_) {
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          _details(),
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: matchComponents,
        );
      } catch (_) {}
    }
  }
}

// ============================================================================
// INTEGRAZIONE REGISTRO ELETTRONICO ARGO (INVARIATA AL 100%)
// ============================================================================

class ArgoSyncResult {
  final List<SchoolEvent> events;
  final List<SchoolGrade> grades;
  final String studentName;
  final String refreshToken;

  const ArgoSyncResult({
    required this.events,
    required this.grades,
    required this.studentName,
    this.refreshToken = '',
  });
}

class _HttpStep {
  final int status;
  final String? location;
  final String body;
  const _HttpStep({required this.status, required this.location, required this.body});
}

class _ScopedCookieJar {
  final Map<String, Map<String, String>> _byHost = {};

  void storeFromResponse(Uri requestUri, HttpClientResponse res) {
    final rawHeaders = res.headers[HttpHeaders.setCookieHeader];
    if (rawHeaders == null) return;
    final host = requestUri.host.toLowerCase();
    final bucket = _byHost.putIfAbsent(host, () => <String, String>{});

    for (final raw in rawHeaders) {
      final parts = raw.split(';');
      if (parts.isEmpty) continue;
      final head = parts.first.trim();
      final eq = head.indexOf('=');
      if (eq <= 0) continue;
      final name = head.substring(0, eq).trim();
      final val = head.substring(eq + 1).trim();

      bool remove = val.isEmpty;
      for (final attr in parts.skip(1)) {
        final s = attr.trim();
        final aEq = s.indexOf('=');
        final aKey = (aEq < 0 ? s : s.substring(0, aEq)).trim().toLowerCase();
        final aVal = aEq < 0 ? '' : s.substring(aEq + 1).trim();
        if (aKey == 'max-age') {
          final ma = int.tryParse(aVal);
          if (ma != null && ma <= 0) remove = true;
        } else if (aKey == 'expires' && aVal.contains('1970')) {
          remove = true;
        }
      }

      if (remove) {
        bucket.remove(name);
      } else {
        bucket[name] = val;
      }
    }
  }

  String? headerFor(Uri uri) {
    final bucket = _byHost[uri.host.toLowerCase()];
    if (bucket == null || bucket.isEmpty) return null;
    return bucket.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }
}

class ArgoApiService {
  static const _clientId = '72fd6dea-d0ab-4bb9-8eaa-3ac24c84886c';
  static const _redirectUri = 'it.argosoft.didup.famiglia.new://login-callback';
  static const _scopes = 'openid offline profile user.roles argo';
  static const _defaultAppVersion = '1.30.2';
  static const _dataInizioDefault = '2000-01-01 00:00:00.000';
  static const _ua = 'okhttp/4.12.0';

  static String _fmtArgoDate(DateTime d) {
    final u = d.toUtc();
    return '${u.year.toString().padLeft(4, '0')}-${u.month.toString().padLeft(2, '0')}-${u.day.toString().padLeft(2, '0')} '
        '${u.hour.toString().padLeft(2, '0')}:${u.minute.toString().padLeft(2, '0')}:${u.second.toString().padLeft(2, '0')}.'
        '${u.millisecond.toString().padLeft(3, '0')}';
  }

  static Future<String> _resolveClientVersion() async {
    try {
      final res = await http
          .get(Uri.parse(
              'https://itunes.apple.com/lookup?bundleId=it.argosoft.didup.famiglia.new&country=it'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final results = ((jsonDecode(res.body) as Map<String, dynamic>)['results'] as List?) ?? [];
        if (results.isNotEmpty) {
          final ver = '${(results.first as Map<String, dynamic>)['version'] ?? ''}'.trim();
          if (ver.isNotEmpty && _cmpVer(ver, _defaultAppVersion) >= 0) return ver;
        }
      }
    } catch (_) {}
    return _defaultAppVersion;
  }

  static int _cmpVer(String a, String b) {
    final pa = a.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    final pb = b.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final d = (i < pa.length ? pa[i] : 0).compareTo(i < pb.length ? pb[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }

  static List<Map<String, dynamic>> _applyArgoOps(List<dynamic>? rawList) {
    if (rawList == null) return [];
    final deleted = <String>{
      for (final item in rawList)
        if (item is Map<String, dynamic> && item['operazione'] == 'D' && item['pk'] != null)
          '${item['pk']}',
    };
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final item in rawList) {
      if (item is! Map<String, dynamic> || item['operazione'] == 'D') continue;
      final pk = item['pk'] != null ? '${item['pk']}' : '';
      if (pk.isNotEmpty && (deleted.contains(pk) || !seen.add(pk))) continue;
      out.add(item);
    }
    return out;
  }

  static String _unescapeUrl(String s) => s
      .trim()
      .replaceAll('&amp;', '&')
      .replaceAll('&#38;', '&')
      .replaceAll('&#x26;', '&')
      .replaceAll('&#X26;', '&')
      .replaceAll('&#61;', '=')
      .replaceAll('&#x3d;', '=')
      .replaceAll('&#x3D;', '=')
      .replaceAll('&#47;', '/')
      .replaceAll('&#x2f;', '/')
      .replaceAll('&#x2F;', '/')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(r'\u0026', '&')
      .replaceAll(r'\u003d', '=')
      .replaceAll(r'\u003D', '=')
      .replaceAll(r'\u002f', '/')
      .replaceAll(r'\u002F', '/')
      .replaceAll(r'\x26', '&')
      .replaceAll(r'\x3d', '=')
      .replaceAll(r'\x3D', '=')
      .replaceAll(r'\/', '/');

  static String? _extractNextUrlFromHtml(String html) {
    final decoded = _unescapeUrl(html);

    final customScheme =
        RegExp(r'it\.argosoft\.didup\.famiglia\.new://[^\s"\x27<>`\\]+').firstMatch(decoded);
    if (customScheme != null) return _unescapeUrl(customScheme.group(0)!);

    final intentMatch = RegExp(
      r'intent://([^\s"\x27<>`#]+)#Intent;[^"\x27<>`]*scheme=it\.argosoft\.didup\.famiglia\.new',
      caseSensitive: false,
    ).firstMatch(decoded);
    if (intentMatch != null) {
      return 'it.argosoft.didup.famiglia.new://${_unescapeUrl(intentMatch.group(1)!)}';
    }

    final hydraUrl = RegExp(
      r'https?://auth\.portaleargo\.it/oauth2/auth\?[^\s"\x27<>`\\]+',
      caseSensitive: false,
    ).firstMatch(decoded);
    if (hydraUrl != null) return _unescapeUrl(hydraUrl.group(0)!);

    final aTags = RegExp(
      r'<a\b[^>]*\bhref\s*=\s*["\x27]([^"\x27]+)["\x27][^>]*>([\s\S]*?)</a>',
      caseSensitive: false,
    ).allMatches(html);
    String? fallbackHref;
    for (final m in aTags) {
      final href = _unescapeUrl(m.group(1) ?? '');
      final text = (m.group(2) ?? '').toLowerCase();
      if (href.isEmpty ||
          href.startsWith('#') ||
          href.toLowerCase().startsWith('javascript:') ||
          href.toLowerCase().startsWith('mailto:') ||
          href.toLowerCase().startsWith('tel:')) {
        continue;
      }
      if (text.contains('continua') ||
          href.contains('it.argosoft.') ||
          href.contains('oauth2') ||
          href.contains('consent') ||
          href.contains('code=')) {
        return href;
      }
      if (!href.endsWith('.css') && !href.endsWith('.png') && !href.endsWith('.ico')) {
        fallbackHref ??= href;
      }
    }

    final meta = RegExp(
      r'<meta\b[^>]*content\s*=\s*["\x27][^"\x27]*url\s*=\s*([^"\x27>\s;]+)',
      caseSensitive: false,
    ).firstMatch(html);
    if (meta != null) return _unescapeUrl(meta.group(1)!);

    final jsPatterns = [
      RegExp(
        r'(?:window\.|document\.|self\.|top\.)?location\.(?:replace|assign)\s*\(\s*["\x27`]([^"\x27`]+)["\x27`]\s*\)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:window\.|document\.|self\.|top\.)?location(?:\.href)?\s*=\s*["\x27`]([^"\x27`]+)["\x27`]',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:redirectUrl|redirect_uri|redirect_to|returnUrl|nextUrl|callbackUrl|targetUrl|continueUrl)\s*[:=]\s*["\x27`]([^"\x27`]+)["\x27`]',
        caseSensitive: false,
      ),
    ];
    for (final reg in jsPatterns) {
      final m = reg.firstMatch(html);
      if (m != null) {
        final cand = _unescapeUrl(m.group(1) ?? '');
        if (cand.isNotEmpty && !cand.startsWith('#')) return cand;
      }
    }

    return fallbackHref;
  }

  static (String, Uri, String?)? _extractHtmlFormSubmission(String html, Uri currentUri) {
    final formMatch = RegExp(
      r'<form\b([^>]*)>([\s\S]*?)</form>',
      caseSensitive: false,
    ).firstMatch(html);
    if (formMatch == null) return null;

    final formAttrs = formMatch.group(1) ?? '';
    final formInner = formMatch.group(2) ?? '';
    final method = (_attrVal(formAttrs, 'method') ?? 'get').toUpperCase();
    final rawAction = _unescapeUrl(_attrVal(formAttrs, 'action') ?? '');
    final actionUri = rawAction.isEmpty ? currentUri : currentUri.resolve(rawAction);

    final fields = <String, List<String>>{};
    final inputReg = RegExp(r'<input\b([^>]*)/?>', caseSensitive: false);
    for (final m in inputReg.allMatches(formInner)) {
      final a = m.group(1) ?? '';
      final name = _attrVal(a, 'name');
      if (name == null || name.isEmpty) continue;
      final type = (_attrVal(a, 'type') ?? 'text').toLowerCase();
      final val = _unescapeUrl(_attrVal(a, 'value') ?? '');
      if (type == 'submit') {
        final low = '$name $val'.toLowerCase();
        if (low.contains('deny') ||
            low.contains('reject') ||
            low.contains('rifiut') ||
            low.contains('annull')) {
          continue;
        }
      }
      if ((type == 'checkbox' || type == 'radio') &&
          !RegExp(r'\bchecked\b', caseSensitive: false).hasMatch(a)) {
        if (name.toLowerCase().contains('scope') || name.toLowerCase().contains('accept')) {
          fields.putIfAbsent(name, () => []).add(val.isEmpty ? 'true' : val);
        }
        continue;
      }
      fields.putIfAbsent(name, () => []).add(val);
    }

    final btnReg = RegExp(r'<button\b([^>]*)>', caseSensitive: false);
    for (final m in btnReg.allMatches(formInner)) {
      final a = m.group(1) ?? '';
      final name = _attrVal(a, 'name');
      final val = _unescapeUrl(_attrVal(a, 'value') ?? '');
      if (name != null && name.isNotEmpty) {
        final low = '$name $val'.toLowerCase();
        if (!low.contains('deny') &&
            !low.contains('reject') &&
            !low.contains('rifiut') &&
            !low.contains('annull')) {
          fields.putIfAbsent(name, () => []).add(val.isEmpty ? 'accept' : val);
        }
      }
    }

    if (method != 'POST') {
      if (fields.isEmpty && rawAction.isEmpty) return null;
      if (actionUri.scheme == 'it.argosoft.didup.famiglia.new') {
        return ('GET', actionUri, null);
      }
      final merged = <String, List<String>>{
        ...actionUri.queryParametersAll,
        ...fields,
      };
      final q = [
        for (final e in merged.entries)
          for (final v in e.value) '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(v)}',
      ].join('&');
      final getUri = q.isEmpty ? actionUri : actionUri.replace(query: q);
      return ('GET', getUri, null);
    }

    if (fields.isEmpty && currentUri.queryParameters['consent_challenge'] != null) {
      fields['challenge'] = [currentUri.queryParameters['consent_challenge']!];
      fields['submit'] = ['accept'];
    }
    if (fields.isEmpty) return null;

    final encoded = [
      for (final e in fields.entries)
        for (final v in e.value) '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(v)}',
    ].join('&');
    return ('POST', actionUri, encoded);
  }

  static String? _attrVal(String attrs, String attrName) {
    final m = RegExp(
      '$attrName\\s*=\\s*["\\x27]([^"\\x27]*)["\\x27]',
      caseSensitive: false,
    ).firstMatch(attrs);
    return m?.group(1);
  }

  static String _readableHtmlHint(String html) {
    final clean = html
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final low = clean.toLowerCase();
    if (low.contains('cambio password') || low.contains('cambiare la password')) {
      return 'Argo richiede il cambio password al primo accesso: accedi una volta da browser su portaleargo.it e poi riprova.';
    }
    if (low.contains('bloccato') || low.contains('disabilitat')) {
      return 'L\'utenza Argo risulta bloccata o disabilitata sul portale della scuola.';
    }
    if (clean.isEmpty) return '';
    return clean.length > 140 ? '${clean.substring(0, 140)}...' : clean;
  }

  static Future<(String, String, DateTime)> _tryRefreshToken(String refreshToken) async {
    final res = await http
        .post(
          Uri.parse('https://auth.portaleargo.it/oauth2/token'),
          headers: {'content-type': 'application/x-www-form-urlencoded', 'user-agent': _ua},
          body: {
            'grant_type': 'refresh_token',
            'refresh_token': refreshToken,
            'client_id': _clientId,
            'scope': _scopes,
          },
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw 'Refresh token scaduto';
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final access = '${j['access_token'] ?? ''}';
    if (access.isEmpty) throw 'Access token assente';
    final nextRefresh = '${j['refresh_token'] ?? ''}'.trim();
    final expSec = (j['expires_in'] as num?)?.toInt() ?? 3600;
    return (
      access,
      nextRefresh.isNotEmpty ? nextRefresh : refreshToken,
      DateTime.now().add(Duration(seconds: expSec)),
    );
  }

  static Future<(String, String, DateTime)> _obtainFreshTokens(
    String school,
    String user,
    String pass,
  ) async {
    final verifier = _rndStr(43);
    final state = _rndStr(22);
    final nonce = _rndStr(22);
    final challenge =
        base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');

    final authUri = Uri.parse(
      'https://auth.portaleargo.it/oauth2/auth'
      '?redirect_uri=${Uri.encodeComponent(_redirectUri)}'
      '&client_id=$_clientId'
      '&response_type=code'
      '&prompt=login'
      '&state=$state'
      '&nonce=$nonce'
      '&scope=${Uri.encodeComponent(_scopes)}'
      '&code_challenge=$challenge'
      '&code_challenge_method=S256',
    );

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 25)
      ..userAgent = _ua;
    final jar = _ScopedCookieJar();

    Future<_HttpStep> passo(
      String method,
      Uri uri, {
      String? formBody,
      bool sendHostCookies = true,
    }) async {
      final req = await client.openUrl(method, uri);
      req.followRedirects = false;
      req.headers.set(
        HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      );
      if (sendHostCookies) {
        final cookieHdr = jar.headerFor(uri);
        if (cookieHdr != null && cookieHdr.isNotEmpty) {
          req.headers.set(HttpHeaders.cookieHeader, cookieHdr);
        }
      }
      if (formBody != null) {
        final bytes = utf8.encode(formBody);
        req.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/x-www-form-urlencoded',
        );
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close().timeout(const Duration(seconds: 25));
      jar.storeFromResponse(uri, res);
      final bodyBytes = await res.fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
      final bodyStr = utf8.decode(bodyBytes, allowMalformed: true);
      return _HttpStep(
        status: res.statusCode,
        location: res.headers.value(HttpHeaders.locationHeader),
        body: bodyStr,
      );
    }

    try {
      final r0 = await passo('GET', authUri, sendHostCookies: false);
      if (r0.location == null) {
        throw 'Connessione OAuth Argo non riuscita (HTTP ${r0.status}).';
      }
      final loginUri = authUri.resolve(r0.location!);
      final loginChallenge = loginUri.queryParameters['login_challenge'];
      if (loginChallenge == null || loginChallenge.isEmpty) {
        throw 'Parametro login_challenge non ricevuto da Argo.';
      }

      final ssoUri = Uri.parse('https://www.portaleargo.it/auth/sso/login');
      final formBody = [
        'challenge=${Uri.encodeComponent(loginChallenge)}',
        'client_id=${Uri.encodeComponent(_clientId)}',
        'prefill=false',
        'famiglia_customer_code=${Uri.encodeComponent(school)}',
        'username=${Uri.encodeComponent(user)}',
        'password=${Uri.encodeComponent(pass)}',
        'login=true',
      ].join('&');

      final r1 = await passo('POST', ssoUri, formBody: formBody, sendHostCookies: true);
      final loc1 = r1.location ?? _extractNextUrlFromHtml(r1.body);
      if (loc1 == null ||
          loc1.contains('/auth/sso/login') ||
          loc1.contains('login_error') ||
          loc1.contains('error=')) {
        final hint = _readableHtmlHint(r1.body);
        if (hint.contains('cambio password') || hint.contains('bloccata')) throw hint;
        throw 'Credenziali non valide: controlla Codice Scuola ($school), Nome Utente e Password.';
      }

      String? callbackUrl;
      Uri currentBase = ssoUri;
      String nextLocation = loc1;

      for (int hop = 0; hop < 12; hop++) {
        if (nextLocation.startsWith('it.argosoft.didup.famiglia.new://')) {
          callbackUrl = nextLocation;
          break;
        }
        final targetUri = currentBase.resolve(nextLocation);
        if (targetUri.scheme == 'it.argosoft.didup.famiglia.new') {
          callbackUrl = targetUri.toString();
          break;
        }

        var step = await passo('GET', targetUri, sendHostCookies: true);
        String? loc = step.location ?? _extractNextUrlFromHtml(step.body);

        if (loc == null) {
          final formSub = _extractHtmlFormSubmission(step.body, targetUri);
          if (formSub != null) {
            if (formSub.$1 == 'GET') {
              currentBase = targetUri;
              loc = formSub.$2.toString();
            } else {
              final postRes = await passo(
                'POST',
                formSub.$2,
                formBody: formSub.$3,
                sendHostCookies: true,
              );
              currentBase = formSub.$2;
              loc = postRes.location ?? _extractNextUrlFromHtml(postRes.body);
              step = postRes;
            }
          } else {
            currentBase = targetUri;
          }
        } else {
          currentBase = targetUri;
        }

        if (loc == null) {
          final hint = _readableHtmlHint(step.body);
          throw hint.isNotEmpty
              ? 'Accesso Argo interrotto su ${targetUri.path} (HTTP ${step.status}): $hint'
              : 'Accesso Argo interrotto su ${targetUri.host}${targetUri.path} (HTTP ${step.status}).';
        }
        nextLocation = loc;
      }

      if (callbackUrl == null) {
        throw 'Catena di login Argo troppo lunga o non completata.';
      }

      final cbUri = Uri.parse(callbackUrl);
      final authCode = cbUri.queryParameters['code'];
      if (authCode == null || authCode.isEmpty) {
        final err = cbUri.queryParameters['error_description'] ??
            cbUri.queryParameters['error'] ??
            'codice OAuth assente';
        throw 'Autorizzazione Argo rifiutata ($err).';
      }

      final tokRes = await http
          .post(
            Uri.parse('https://auth.portaleargo.it/oauth2/token'),
            headers: {'content-type': 'application/x-www-form-urlencoded', 'user-agent': _ua},
            body: {
              'code': authCode,
              'grant_type': 'authorization_code',
              'redirect_uri': _redirectUri,
              'code_verifier': verifier,
              'client_id': _clientId,
            },
          )
          .timeout(const Duration(seconds: 25));

      final tokJson = jsonDecode(tokRes.body) as Map<String, dynamic>;
      if (tokJson['access_token'] == null) {
        throw 'Token OAuth non ottenuto: ${tokJson['error_description'] ?? tokRes.statusCode}';
      }
      final bearer = '${tokJson['access_token']}';
      final refresh = '${tokJson['refresh_token'] ?? ''}';
      final expAt = DateTime.now().add(
        Duration(seconds: (tokJson['expires_in'] as num?)?.toInt() ?? 3600),
      );
      return (bearer, refresh, expAt);
    } finally {
      client.close(force: true);
    }
  }

  static Future<ArgoSyncResult> sync({
    required String schoolCode,
    required String username,
    required String password,
    String savedRefreshToken = '',
  }) async {
    final school = schoolCode.trim().toUpperCase();
    final user = username.trim();
    final appVersion = await _resolveClientVersion();

    String bearer;
    String refreshToken;
    DateTime expAt;

    if (savedRefreshToken.isNotEmpty) {
      try {
        final r = await _tryRefreshToken(savedRefreshToken);
        bearer = r.$1;
        refreshToken = r.$2;
        expAt = r.$3;
      } catch (_) {
        final r = await _obtainFreshTokens(school, user, password);
        bearer = r.$1;
        refreshToken = r.$2;
        expAt = r.$3;
      }
    } else {
      final r = await _obtainFreshTokens(school, user, password);
      bearer = r.$1;
      refreshToken = r.$2;
      expAt = r.$3;
    }

    final expStr = _fmtArgoDate(expAt);
    Map<String, String> didupHeaders([String? xToken, String? codMin]) => {
          'accept': 'application/json',
          'argo-client-version': appVersion,
          'content-type': 'application/json; charset=utf-8',
          'authorization': 'Bearer $bearer',
          'x-date-exp-auth': expStr,
          'user-agent': _ua,
          if (xToken != null) 'x-auth-token': xToken,
          if (codMin != null) 'x-cod-min': codMin,
        };

    var loginRes = await http
        .post(
          Uri.parse('https://www.portaleargo.it/appfamiglia/api/rest/login'),
          headers: didupHeaders(),
          body: jsonEncode({
            'lista-opzioni-notifiche': '{}',
            'lista-x-auth-token': '[]',
            'clientID': _rndStr(163),
          }),
        )
        .timeout(const Duration(seconds: 25));

    if ((loginRes.statusCode == 401 || loginRes.statusCode == 403) &&
        savedRefreshToken.isNotEmpty) {
      final fresh = await _obtainFreshTokens(school, user, password);
      bearer = fresh.$1;
      refreshToken = fresh.$2;
      expAt = fresh.$3;
      loginRes = await http
          .post(
            Uri.parse('https://www.portaleargo.it/appfamiglia/api/rest/login'),
            headers: {
              ...didupHeaders(),
              'authorization': 'Bearer $bearer',
              'x-date-exp-auth': _fmtArgoDate(expAt),
            },
            body: jsonEncode({
              'lista-opzioni-notifiche': '{}',
              'lista-x-auth-token': '[]',
              'clientID': _rndStr(163),
            }),
          )
          .timeout(const Duration(seconds: 25));
    }

    if (loginRes.statusCode == 410) {
      throw 'Versione DidUP ($appVersion) rifiutata dal server Argo (HTTP 410).';
    }
    final loginRoot = jsonDecode(loginRes.body) as Map<String, dynamic>;
    if (loginRoot['success'] == false) {
      throw '${loginRoot['msg'] ?? 'Login applicativo Argo non riuscito'}';
    }
    final profili = ((loginRoot['data'] as List?) ?? []).whereType<Map<String, dynamic>>().toList();
    if (profili.isEmpty) throw 'Nessun profilo alunno trovato su questo account Argo.';

    final attivi = profili.where((p) => p['profiloDisabilitato'] != true).toList();
    final pool = attivi.isNotEmpty ? attivi : profili;
    final prof = pool.firstWhere(
      (p) => '${p['codMin'] ?? ''}'.toUpperCase() == school,
      orElse: () => pool.first,
    );

    final xToken = '${prof['token'] ?? ''}';
    final codMin = '${prof['codMin'] ?? school}';
    final opzioniMap = <String, dynamic>{
      for (final o in (prof['opzioni'] as List? ?? []))
        if (o is Map<String, dynamic> && o['chiave'] != null) '${o['chiave']}': o['valore'],
    };

    final activeHeaders = {
      'accept': 'application/json',
      'argo-client-version': appVersion,
      'content-type': 'application/json; charset=utf-8',
      'authorization': 'Bearer $bearer',
      'x-date-exp-auth': _fmtArgoDate(expAt),
      'user-agent': _ua,
      'x-auth-token': xToken,
      'x-cod-min': codMin,
    };

    String studentName = user;
    try {
      final pRes = await http
          .get(
            Uri.parse('https://www.portaleargo.it/appfamiglia/api/rest/profilo'),
            headers: activeHeaders,
          )
          .timeout(const Duration(seconds: 15));
      final alunno = ((jsonDecode(pRes.body) as Map<String, dynamic>)['data'] as Map?)?['alunno'];
      if (alunno is Map) {
        final nom = '${alunno['nominativo'] ?? ''}'.trim();
        if (nom.isNotEmpty) studentName = nom;
      }
    } catch (_) {}

    final dashRes = await http
        .post(
          Uri.parse('https://www.portaleargo.it/appfamiglia/api/rest/dashboard/dashboard'),
          headers: activeHeaders,
          body: jsonEncode({
            'dataultimoaggiornamento': _dataInizioDefault,
            'opzioni': jsonEncode(opzioniMap),
          }),
        )
        .timeout(const Duration(seconds: 30));

    final dashRoot = jsonDecode(dashRes.body) as Map<String, dynamic>;
    if (dashRoot['success'] == false) {
      throw '${dashRoot['msg'] ?? 'Errore scaricamento dashboard Argo'}';
    }
    final datiList = (dashRoot['data'] is Map<String, dynamic>)
        ? ((dashRoot['data']['dati'] as List?) ?? [])
        : [];
    if (datiList.isEmpty || datiList.first is! Map<String, dynamic>) {
      return ArgoSyncResult(
        events: [],
        grades: [],
        studentName: studentName,
        refreshToken: refreshToken,
      );
    }
    final dash = datiList.first as Map<String, dynamic>;

    final matByPk = <String, String>{
      for (final m in (dash['listaMaterie'] as List? ?? []))
        if (m is Map<String, dynamic> && m['pk'] != null)
          '${m['pk']}': _cleanSubj('${m['materia'] ?? ''}'),
    };
    final docMateria = <String, String>{};
    for (final doc in (dash['listaDocentiClasse'] as List? ?? [])) {
      if (doc is Map<String, dynamic> && doc['pk'] != null) {
        final ml = (doc['materie'] as List?) ?? [];
        if (ml.isNotEmpty) {
          final k = '${ml.first}';
          docMateria['${doc['pk']}'] = matByPk[k] ?? _cleanSubj(k);
        }
      }
    }

    final events = <SchoolEvent>[];
    final grades = <SchoolGrade>[];

    for (final m in _applyArgoOps(dash['promemoria'] as List?)) {
      final txt = '${m['desAnnotazioni'] ?? ''}'.trim();
      if (txt.isEmpty) continue;
      final d = DateTime.tryParse('${m['datGiorno'] ?? ''}') ?? DateTime.now();
      final docName = '${m['docente'] ?? ''}'.trim();
      final subj =
          docMateria['${m['pkDocente'] ?? ''}'] ?? (docName.isNotEmpty ? docName : 'Promemoria');
      final cat = classifyText(txt);
      events.add(SchoolEvent(
        id: 'argo_p_${m['pk'] ?? txt.hashCode}',
        title: txt,
        subject: subj,
        notes: docName.isNotEmpty ? 'Docente: $docName' : 'Promemoria Argo',
        dateTime: DateTime(d.year, d.month, d.day, 8, 15),
        category: cat,
        reminderMode: (cat == EventCategory.verifica || cat == EventCategory.interrogazione)
            ? EventReminderMode.defaultBoth
            : EventReminderMode.dayBefore17,
        fromArgo: true,
      ));
    }

    for (final m in _applyArgoOps(dash['voti'] as List?)) {
      final rawVal = m['valore'];
      final val = rawVal is num ? rawVal.toDouble() : double.tryParse('$rawVal');
      if (val == null || val <= 0) continue;
      final rawT = '${m['codVotoPratico'] ?? 'S'}'.toUpperCase();
      grades.add(SchoolGrade(
        id: 'argo_v_${m['pk'] ?? m.hashCode}',
        subject: _cleanSubj('${m['desMateria'] ?? 'Materia'}'),
        value: val,
        weight: '${m['faMenoMedia'] ?? 'S'}' == 'N' ? 0.0 : 1.0,
        type: (rawT == 'N' || rawT == 'O') ? 'Orale' : (rawT == 'P' ? 'Pratico' : 'Scritto'),
        description: '${m['descrizioneProva'] ?? m['desCommento'] ?? ''}'.trim(),
        date: DateTime.tryParse('${m['datGiorno'] ?? ''}') ?? DateTime.now(),
        fromArgo: true,
      ));
    }

    return ArgoSyncResult(
      events: events,
      grades: grades,
      studentName: studentName,
      refreshToken: refreshToken,
    );
  }

  static EventCategory classifyText(String text) {
    final l = text.toLowerCase();
    if (l.contains('verifica') ||
        l.contains('compito in classe') ||
        l.contains('simulazione') ||
        l.contains('prova') ||
        l.contains('test')) {
      return EventCategory.verifica;
    }
    if (l.contains('interrogazion') ||
        l.contains('colloquio') ||
        l.contains('orale') ||
        l.contains('esposizione')) {
      return EventCategory.interrogazione;
    }
    return EventCategory.altro;
  }

  static String _cleanSubj(String s) =>
      s.trim().isEmpty ? 'Materia' : s.trim()[0].toUpperCase() + s.trim().substring(1).toLowerCase();

  static String _rndStr(int len) {
    const ch = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(len, (_) => ch[r.nextInt(ch.length)]).join();
  }

  static ArgoSyncResult demoData() {
    final now = DateTime.now();
    DateTime d(int add, int h) => DateTime(now.year, now.month, now.day + add, h, 15);
    return ArgoSyncResult(
      studentName: 'Studente Demo · 4ª Scientifico',
      events: [
        SchoolEvent(
          id: 'demo_1',
          title: 'Verifica scritta su limiti, continuità e asintoti',
          subject: 'Matematica',
          dateTime: d(2, 8),
          category: EventCategory.verifica,
          fromArgo: true,
        ),
        SchoolEvent(
          id: 'demo_2',
          title: 'Interrogazione programmata su Leopardi e Romanticismo',
          subject: 'Italiano',
          dateTime: d(4, 9),
          category: EventCategory.interrogazione,
          fromArgo: true,
        ),
        SchoolEvent(
          id: 'demo_4',
          title: 'Verifica di laboratorio SQL (JOIN & GROUP BY)',
          subject: 'Informatica',
          dateTime: d(6, 11),
          category: EventCategory.verifica,
          fromArgo: true,
        ),
      ],
      grades: [
        SchoolGrade(
            id: 'dg1',
            subject: 'Matematica',
            value: 7.5,
            type: 'Scritto',
            description: 'Esponenziali e logaritmi',
            date: now.subtract(const Duration(days: 16)),
            fromArgo: true),
        SchoolGrade(
            id: 'dg2',
            subject: 'Matematica',
            value: 8.0,
            type: 'Orale',
            description: 'Studio di funzione',
            date: now.subtract(const Duration(days: 5)),
            fromArgo: true),
        SchoolGrade(
            id: 'dg3',
            subject: 'Italiano',
            value: 7.0,
            type: 'Scritto',
            description: 'Tema argomentativo',
            date: now.subtract(const Duration(days: 12)),
            fromArgo: true),
        SchoolGrade(
            id: 'dg4',
            subject: 'Fisica',
            value: 5.5,
            type: 'Scritto',
            description: 'Teorema di Gauss',
            date: now.subtract(const Duration(days: 10)),
            fromArgo: true),
        SchoolGrade(
            id: 'dg5',
            subject: 'Inglese',
            value: 8.5,
            type: 'Orale',
            description: 'Victorian Age speaking',
            date: now.subtract(const Duration(days: 7)),
            fromArgo: true),
        SchoolGrade(
            id: 'dg6',
            subject: 'Informatica',
            value: 9.0,
            type: 'Pratico',
            description: 'Database ER Biblioteca',
            date: now.subtract(const Duration(days: 3)),
            fromArgo: true),
      ],
    );
  }
}

// ============================================================================
// APP ROOT & HOME SHELL (4 SEZIONI: CALENDARIO, ORARIO, VOTI, IMPOSTAZIONI)
// ============================================================================

/// Punto unico di verità per colori, superfici, ombre e spaziature.
/// Tutti i widget leggono da qui, così l'app resta coerente in ogni schermata.
class VibeSkin {
  final bool dark;
  const VibeSkin(this.dark);

  bool get isDark => dark;

  Color get card => dark ? VibePalette.darkCard : VibePalette.lightCard;
  Color get cardAlt => dark ? VibePalette.darkCardAlt : VibePalette.lightCardAlt;
  Color get border => dark ? VibePalette.darkBorder : VibePalette.lightBorder;
  Color get txt => dark ? const Color(0xFFF2F5FA) : const Color(0xFF0B1220);
  Color get muted => dark ? const Color(0xFF98A6BC) : const Color(0xFF64748B);
  Color get faint => dark ? const Color(0xFF76849C) : const Color(0xFF98A2B3);
  Color get hairline => dark ? alphaCol(Colors.white, 0.06) : alphaCol(const Color(0xFF0F172A), 0.06);
  Color get ink => dark ? const Color(0xFF050810) : const Color(0xFFF7F9FD);

  List<BoxShadow> get cardShadow => dark
      ? [
          BoxShadow(
              color: alphaCol(Colors.black, 0.55),
              blurRadius: 28,
              offset: const Offset(0, 14),
              spreadRadius: -6),
        ]
      : [
          BoxShadow(
              color: alphaCol(const Color(0xFF0F172A), 0.07),
              blurRadius: 28,
              offset: const Offset(0, 14),
              spreadRadius: -8),
        ];

  BoxDecoration panel([double radius = 24, Color? color, Color? borderColor]) => BoxDecoration(
        color: color ?? card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? border),
        boxShadow: cardShadow,
      );
}

/// Piccoli token condivisi: raggi, spaziature e durate.
class VibeMetrics {
  static const double gap = 14;
  static const double pagePad = 16;
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 280);
}

/// Sfondo atmosferico: due aloni morbidi che danno profondità senza rumore.
class _AmbientBackground extends StatelessWidget {
  final bool dark;
  const _AmbientBackground({required this.dark});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: dark
                  ? const [Color(0xFF0A1020), Color(0xFF05080F)]
                  : const [Color(0xFFF7FAFF), Color(0xFFEDF2FA)],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -120,
                right: -80,
                child: _glow(
                  dark ? alphaCol(VibePalette.primary, 0.30) : alphaCol(VibePalette.primary, 0.16),
                  320,
                ),
              ),
              Positioned(
                top: 180,
                left: -140,
                child: _glow(
                  dark ? alphaCol(VibePalette.capBlue, 0.22) : alphaCol(VibePalette.capBlue, 0.12),
                  280,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glow(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, alphaCol(color, 0.0)]),
        ),
      );
}

class SchoolVibeApp extends StatefulWidget {
  final StorageService storage;
  const SchoolVibeApp({super.key, required this.storage});

  @override
  State<SchoolVibeApp> createState() => _SchoolVibeAppState();
}

class _SchoolVibeAppState extends State<SchoolVibeApp> {
  late bool _isDark = widget.storage.loadDarkMode();

  void _toggleTheme() {
    setState(() => _isDark = !_isDark);
    widget.storage.saveDarkMode(_isDark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calendario Scuola',
      debugShowCheckedModeBanner: false,
      theme: VibePalette.lightTheme(),
      darkTheme: VibePalette.darkTheme(),
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      locale: const Locale('it', 'IT'),
      supportedLocales: const [Locale('it', 'IT'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: HomeShell(storage: widget.storage, isDark: _isDark, onToggleTheme: _toggleTheme),
    );
  }
}

class HomeShell extends StatefulWidget {
  final StorageService storage;
  final bool isDark;
  final VoidCallback onToggleTheme;

  const HomeShell({
    super.key,
    required this.storage,
    required this.isDark,
    required this.onToggleTheme,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with SingleTickerProviderStateMixin {
  static const _chillEmptyQuotes = [
    'Agenda vuota, mente leggera.',
    'Zero scadenze in vista per questo giorno.',
    'Tutto tranquillo qui: nessun impegno segnato.',
    'Giornata libera da verifiche e interrogazioni.',
  ];

  static const _dayNames = {
    1: 'Lunedì',
    2: 'Martedì',
    3: 'Mercoledì',
    4: 'Giovedì',
    5: 'Venerdì',
  };
  static const _dayShort = {1: 'Lun', 2: 'Mar', 3: 'Mer', 4: 'Gio', 5: 'Ven'};

  int _tab = 0;
  late List<SchoolEvent> _events = widget.storage.loadEvents();
  late List<SchoolGrade> _grades = widget.storage.loadGrades();
  late Map<int, DaySchedule> _timetable = widget.storage.loadTimetable();
  late Set<String> _deletedArgoIds = widget.storage.loadDeletedArgoIds();
  late ArgoCredentials _argo = widget.storage.loadArgo();
  late bool _notifyOn = widget.storage.loadNotifyEnabled();
  late bool _morningNotifyOn = widget.storage.loadMorningNotifyEnabled();

  bool _isListView = false;
  EventCategory? _catFilter;
  CalendarFormat _calFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  int _emptyIdx = Random().nextInt(_chillEmptyQuotes.length);

  int _ttDay = DateTime.now().weekday > 5 ? 1 : DateTime.now().weekday;
  bool _ttWeekOverview = false;

  bool _syncing = false;
  String? _lastSyncError;
  bool _weightedAvg = true;
  Timer? _ticker;

  late final AnimationController _tabFade =
      AnimationController(vsync: this, duration: VibeMetrics.normal, value: 1);

  @override
  void initState() {
    super.initState();
    _resyncNotifications();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _tabFade.dispose();
    super.dispose();
  }

  Future<void> _resyncNotifications() => NotificationService.instance.syncNotifications(
        _events,
        enabled: _notifyOn,
        morningEnabled: _morningNotifyOn,
      );

  Future<void> _saveEvents() async {
    _events.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    await widget.storage.saveEvents(_events);
    await _resyncNotifications();
  }

  Future<void> _saveGrades() async {
    _grades.sort((a, b) => b.date.compareTo(a.date));
    await widget.storage.saveGrades(_grades);
  }

  Future<void> _saveTimetable() => widget.storage.saveTimetable(_timetable);

  List<SchoolEvent> _eventsForDay(DateTime day) => _events
      .where((e) => isSameDay(e.dateTime, day) && (_catFilter == null || e.category == _catFilter))
      .toList();

  List<SchoolEvent> get _upcomingFiltered {
    final startToday = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    return _events
        .where((e) =>
            (!e.dateTime.isBefore(startToday) || !e.completed) &&
            (_catFilter == null || e.category == _catFilter))
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  int get _next7DaysCount {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 7, hours: 23, minutes: 59));
    return _events
        .where((e) => !e.completed && !e.dateTime.isBefore(start) && !e.dateTime.isAfter(end))
        .length;
  }

  int get _todoTotal => _events.where((e) => !e.completed).length;

  Future<void> _deleteEvent(SchoolEvent ev) async {
    setState(() => _events.removeWhere((x) => x.id == ev.id));
    if (ev.fromArgo) {
      _deletedArgoIds.add(ev.id);
      await widget.storage.saveDeletedArgoIds(_deletedArgoIds);
    }
    await _saveEvents();
  }

  Future<void> _runArgoSync(String school, String user, String pass, {bool demo = false}) async {
    setState(() {
      _syncing = true;
      _lastSyncError = null;
    });
    try {
      final sameAccount = _argo.schoolCode.toUpperCase() == school.trim().toUpperCase() &&
          _argo.username == user.trim() &&
          _argo.password == pass;

      final res = demo
          ? ArgoApiService.demoData()
          : await ArgoApiService.sync(
              schoolCode: school,
              username: user,
              password: pass,
              savedRefreshToken: sameAccount ? _argo.refreshToken : '',
            );
      final creds = ArgoCredentials(
        schoolCode: demo && school.isEmpty ? 'SG00000' : school.trim().toUpperCase(),
        username: demo && user.isEmpty ? 'studente.demo' : user.trim(),
        password: pass,
        studentName: res.studentName,
        refreshToken: res.refreshToken,
        lastSync: DateTime.now(),
      );

      final existingById = {for (final e in _events) e.id: e};
      final mergedArgo = <SchoolEvent>[];
      for (final inc in res.events) {
        if (_deletedArgoIds.contains(inc.id)) continue;
        final prev = existingById[inc.id];
        if (prev != null && prev.editedByUser) {
          mergedArgo.add(prev);
        } else if (prev != null) {
          mergedArgo.add(inc.copyWith(
            completed: prev.completed,
            reminderMode: prev.reminderMode,
            customReminderAt: prev.customReminderAt,
          ));
        } else {
          mergedArgo.add(inc);
        }
      }
      for (final prev in _events) {
        if (prev.fromArgo &&
            prev.editedByUser &&
            !_deletedArgoIds.contains(prev.id) &&
            !mergedArgo.any((x) => x.id == prev.id)) {
          mergedArgo.add(prev);
        }
      }

      setState(() {
        _events = [..._events.where((e) => !e.fromArgo), ...mergedArgo];
        _grades = [..._grades.where((g) => !g.fromArgo), ...res.grades];
        _argo = creds;
      });
      await widget.storage.saveArgo(creds);
      await _saveEvents();
      await _saveGrades();
      if (mounted) {
        _toast('Sincronizzati ${mergedArgo.length} impegni e ${res.grades.length} voti.', ok: true);
      }
    } catch (e) {
      final cleanErr = e.toString().replaceFirst('Exception: ', '');
      setState(() => _lastSyncError = cleanErr);
      if (mounted) _toast(cleanErr);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _toast(String message, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              Icon(
                ok ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.exclamationmark_circle,
                size: 19,
                color: ok ? VibePalette.okGreen : VibePalette.interrogazioneAmber,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ],
          ),
        ),
      );
  }

  void _selectTab(int i) {
    if (i == _tab) return;
    HapticFeedback.selectionClick();
    setState(() => _tab = i);
    _tabFade.forward(from: 0.35);
  }

  @override
  Widget build(BuildContext context) {
    final s = VibeSkin(widget.isDark);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        children: [
          _AmbientBackground(dark: widget.isDark),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(s),
                Expanded(
                  child: FadeTransition(
                    opacity: CurvedAnimation(parent: _tabFade, curve: Curves.easeOut),
                    child: IndexedStack(
                      index: _tab,
                      children: [
                        _buildDashboardTab(s),
                        _buildTimetableTab(s),
                        _buildGradesTab(s),
                        _SettingsTab(
                          isDark: widget.isDark,
                          cardColor: s.card,
                          borderColor: s.border,
                          creds: _argo,
                          syncing: _syncing,
                          lastError: _lastSyncError,
                          notifyOn: _notifyOn,
                          morningNotifyOn: _morningNotifyOn,
                          onSync: (s2, u, p) => _runArgoSync(s2, u, p),
                          onDemo: (s2, u, p) => _runArgoSync(s2, u, p, demo: true),
                          onToggleNotify: (v) async {
                            setState(() => _notifyOn = v);
                            await widget.storage.saveNotifyEnabled(v);
                            await _resyncNotifications();
                          },
                          onToggleMorningNotify: (v) async {
                            setState(() => _morningNotifyOn = v);
                            await widget.storage.saveMorningNotifyEnabled(v);
                            await _resyncNotifications();
                          },
                          onReset: () async {
                            await widget.storage.clearAll();
                            setState(() {
                              _events = [];
                              _grades = [];
                              _deletedArgoIds = {};
                              _argo = const ArgoCredentials();
                              _lastSyncError = null;
                            });
                            await _resyncNotifications();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: (_tab == 0 || _tab == 2)
          ? Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                gradient:
                    const LinearGradient(colors: [VibePalette.primary, VibePalette.primaryGlow]),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: alphaCol(VibePalette.primary, 0.45),
                      blurRadius: 22,
                      offset: const Offset(0, 10)),
                ],
              ),
              child: FloatingActionButton(
                heroTag: 'vibe_fab',
                elevation: 0,
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                shape: const CircleBorder(),
                tooltip: _tab == 0 ? 'Nuovo impegno' : 'Nuovo voto',
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  _tab == 0 ? _showEventModal(baseDate: _selectedDay) : _showAddGradeModal();
                },
                child: const Icon(CupertinoIcons.add, size: 26),
              ),
            )
          : null,
      bottomNavigationBar: _buildNavBar(s),
    );
  }

  // --------------------------------------------------------------------------
  // HEADER
  // --------------------------------------------------------------------------

  Widget _buildHeader(VibeSkin s) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Buongiorno' : (hour < 18 ? 'Buon pomeriggio' : 'Buonasera');
    final name = _argo.studentName.trim();
    final notifOn = _notifyOn || _morningNotifyOn;

    return Padding(
      padding: const EdgeInsets.fromLTRB(VibeMetrics.pagePad, 10, 12, 10),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [VibePalette.primary, VibePalette.primaryGlow],
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                    color: alphaCol(VibePalette.primary, 0.42),
                    blurRadius: 16,
                    offset: const Offset(0, 7)),
              ],
            ),
            child: const Icon(Icons.school_rounded, color: Colors.white, size: 25),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  greeting.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: s.faint,
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name.isNotEmpty ? name : 'Calendario Scuola',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: s.txt,
                        ),
                      ),
                    ),
                    if (_argo.lastSync != null) ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: alphaCol(VibePalette.okGreen, 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: alphaCol(VibePalette.okGreen, 0.4)),
                        ),
                        child: const Text(
                          'ARGO',
                          style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                              color: VibePalette.okGreen),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          _headerButton(
            s,
            notifOn ? CupertinoIcons.bell_fill : CupertinoIcons.bell_slash,
            onTap: () => _selectTab(3),
            dot: notifOn,
          ),
          const SizedBox(width: 8),
          _headerButton(
            s,
            widget.isDark ? CupertinoIcons.moon_stars_fill : CupertinoIcons.sun_max_fill,
            onTap: widget.onToggleTheme,
          ),
        ],
      ),
    );
  }

  Widget _headerButton(VibeSkin s, IconData icon,
      {required VoidCallback onTap, bool dot = false}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: s.card,
          shape: BoxShape.circle,
          border: Border.all(color: s.border),
          boxShadow: s.cardShadow,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 18, color: s.txt),
            if (dot)
              Positioned(
                top: 11,
                right: 11,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: VibePalette.okGreen,
                    shape: BoxShape.circle,
                    border: Border.all(color: s.card, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // BOTTOM NAVIGATION (capsule flottante)
  // --------------------------------------------------------------------------

  Widget _buildNavBar(VibeSkin s) {
    final items = [
      (CupertinoIcons.calendar, CupertinoIcons.calendar, 'Calendario'),
      (CupertinoIcons.clock, CupertinoIcons.clock_fill, 'Orario'),
      (CupertinoIcons.chart_bar_square, CupertinoIcons.chart_bar_square_fill, 'Voti'),
      (CupertinoIcons.gear, CupertinoIcons.gear_solid, 'Impostazioni'),
    ];

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: s.card,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: s.border),
          boxShadow: [
            BoxShadow(
                color: alphaCol(s.dark ? Colors.black : const Color(0xFF0F172A), 0.22),
                blurRadius: 26,
                offset: const Offset(0, 10),
                spreadRadius: -6),
          ],
        ),
        child: Row(
          children: [
            for (int i = 0; i < items.length; i++)
              Expanded(
                child: _navItem(
                  s,
                  icon: items[i].$1,
                  activeIcon: items[i].$2,
                  label: items[i].$3,
                  active: _tab == i,
                  onTap: () => _selectTab(i),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(
    VibeSkin s, {
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: VibeMetrics.fast,
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [VibePalette.primary, VibePalette.primaryGlow],
                )
              : null,
          borderRadius: BorderRadius.circular(20),
          boxShadow: active
              ? [
                  BoxShadow(
                      color: alphaCol(VibePalette.primary, 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 6)),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? activeIcon : icon,
              size: 20,
              color: active ? Colors.white : s.muted,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: -0.1,
                color: active ? Colors.white : s.faint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // ELEMENTI CONDIVISI
  // --------------------------------------------------------------------------

  Widget _sectionLabel(VibeSkin s, String text, IconData icon) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 14, color: VibePalette.primary),
            const SizedBox(width: 6),
            Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: s.faint,
              ),
            ),
          ],
        ),
      );

  Widget _pill({
    required VibeSkin s,
    required String label,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    final fg = selected ? Colors.white : (s.dark ? const Color(0xFFCBD5E1) : const Color(0xFF334155));
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: VibeMetrics.fast,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(colors: [accent, alphaCol(accent, 0.75)])
              : null,
          color: selected ? null : s.cardAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.transparent : s.border),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: alphaCol(accent, 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 5)),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _softIconButton(VibeSkin s, IconData icon, VoidCallback onTap, {String? tip}) {
    final btn = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: s.cardAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: s.border),
        ),
        child: Icon(icon, size: 15, color: s.muted),
      ),
    );
    return tip == null ? btn : Tooltip(message: tip, child: btn);
  }

  // --------------------------------------------------------------------------
  // TAB 1: CALENDARIO & SCADENZE
  // --------------------------------------------------------------------------

  Widget _buildDashboardTab(VibeSkin s) {
    final rawMonth = DateFormat('MMMM yyyy', 'it_IT').format(_focusedDay);
    final monthTitle = rawMonth[0].toUpperCase() + rawMonth.substring(1);
    final dayEvents = _eventsForDay(_selectedDay);
    final nextEv = _upcomingFiltered.where((e) => !e.completed).firstOrNull;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(VibeMetrics.pagePad, 4, VibeMetrics.pagePad, 120),
      children: [
        _nextUpHero(s, nextEv),
        const SizedBox(height: 12),
        _statsStrip(s),
        const SizedBox(height: 16),
        _viewSwitcher(s),
        const SizedBox(height: 12),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              _pill(
                s: s,
                label: 'Tutti',
                selected: _catFilter == null,
                accent: VibePalette.primary,
                onTap: () => setState(() => _catFilter = null),
              ),
              for (final c in EventCategory.values) ...[
                const SizedBox(width: 8),
                _pill(
                  s: s,
                  label: c.label,
                  selected: _catFilter == c,
                  accent: c.color,
                  onTap: () => setState(() => _catFilter = c),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (!_isListView) ...[
          _calendarCard(s, monthTitle),
          const SizedBox(height: 14),
          _dayAgendaCard(s, dayEvents),
        ] else
          _buildListWithCountdown(s),
      ],
    );
  }

  Widget _nextUpHero(VibeSkin s, SchoolEvent? ev) {
    if (ev == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          color: s.card,
          border: Border.all(color: s.border),
          boxShadow: s.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: alphaCol(VibePalette.okGreen, 0.14),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(CupertinoIcons.sparkles, color: VibePalette.okGreen, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tutto sotto controllo',
                      style: TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w800, color: s.txt)),
                  const SizedBox(height: 3),
                  Text('Nessun impegno in arrivo: buona giornata.',
                      style: TextStyle(fontSize: 12.5, color: s.muted)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final diff = ev.dateTime.difference(DateTime.now());
    final grad = _heroGradient(ev.category);
    return GestureDetector(
      onTap: () => _showEventModal(existing: ev),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: grad,
          ),
          boxShadow: [
            BoxShadow(
                color: alphaCol(grad.last, 0.45),
                blurRadius: 26,
                offset: const Offset(0, 12),
                spreadRadius: -6),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Stack(
            children: [
              Positioned(
                right: -40,
                top: -50,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: alphaCol(Colors.white, 0.10),
                  ),
                ),
              ),
              Positioned(
                right: 40,
                bottom: -70,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: alphaCol(Colors.white, 0.07),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: alphaCol(Colors.white, 0.18),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: alphaCol(Colors.white, 0.25)),
                          ),
                          child: Text(
                            ev.category.label.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.9,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'PROSSIMO IMPEGNO',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              color: alphaCol(Colors.white, 0.75),
                            ),
                          ),
                        ),
                        Text(
                          _countdownText(ev.dateTime),
                          style: const TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      ev.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: alphaCol(Colors.white, 0.82),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      ev.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18.5,
                        fontWeight: FontWeight.w800,
                        height: 1.22,
                        letterSpacing: -0.4,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(CupertinoIcons.calendar,
                            size: 12, color: alphaCol(Colors.white, 0.8)),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            DateFormat('EEE d MMM · HH:mm', 'it_IT').format(ev.dateTime),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: alphaCol(Colors.white, 0.85)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _cdBox('${max(0, diff.inDays)}', 'GIORNI')),
                        const SizedBox(width: 8),
                        Expanded(child: _cdBox('${max(0, diff.inHours % 24)}', 'ORE')),
                        const SizedBox(width: 8),
                        Expanded(child: _cdBox('${max(0, diff.inMinutes % 60)}', 'MIN')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Color> _heroGradient(EventCategory c) {
    switch (c) {
      case EventCategory.verifica:
        return const [Color(0xFFF44E62), Color(0xFFAF1F53)];
      case EventCategory.interrogazione:
        return const [Color(0xFFFFA53D), Color(0xFFE2591B)];
      case EventCategory.altro:
        return const [Color(0xFF8B5CF6), Color(0xFF4338CA)];
    }
  }

  Widget _cdBox(String val, String unit) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: alphaCol(Colors.black, 0.22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: alphaCol(Colors.white, 0.12)),
        ),
        child: Column(
          children: [
            Text(val,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white, height: 1.1)),
            Text(unit,
                style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: alphaCol(Colors.white, 0.7))),
          ],
        ),
      );

  Widget _statsStrip(VibeSkin s) {
    final today = DateTime.now();
    final todayCount =
        _events.where((e) => isSameDay(e.dateTime, today) && !e.completed).length;

    Widget cell(IconData icon, Color color, int value, String label) => Expanded(
          child: Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: alphaCol(color, 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(height: 7),
              Text('$value',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900, color: s.txt, height: 1.05)),
              const SizedBox(height: 2),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: s.faint)),
            ],
          ),
        );

    Widget divider() => Container(width: 1, height: 44, color: s.hairline);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: s.panel(22),
      child: Row(
        children: [
          cell(CupertinoIcons.calendar_badge_plus, VibePalette.primary, _next7DaysCount,
              'Prossimi 7 giorni'),
          divider(),
          cell(CupertinoIcons.checkmark_rectangle, VibePalette.okGreen, _todoTotal, 'Da fare'),
          divider(),
          cell(CupertinoIcons.bolt_fill, VibePalette.interrogazioneAmber, todayCount, 'Oggi'),
        ],
      ),
    );
  }

  Widget _viewSwitcher(VibeSkin s) {
    Widget item(bool listMode, IconData icon, String label) {
      final active = _isListView == listMode;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _isListView = listMode),
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: active ? Colors.white : s.muted),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: active ? Colors.white : s.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: s.panel(22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final half = constraints.maxWidth / 2;
          return Stack(
            children: [
              AnimatedAlign(
                alignment: _isListView ? Alignment.centerRight : Alignment.centerLeft,
                duration: VibeMetrics.normal,
                curve: Curves.easeOutCubic,
                child: Container(
                  width: half,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [VibePalette.primary, VibePalette.primaryGlow]),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                          color: alphaCol(VibePalette.primary, 0.32),
                          blurRadius: 12,
                          offset: const Offset(0, 5)),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  item(false, CupertinoIcons.calendar, 'Calendario'),
                  item(true, CupertinoIcons.list_bullet, 'Lista'),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _calendarCard(VibeSkin s, String monthTitle) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: s.panel(24),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  monthTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: s.txt),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _calFormat = _calFormat == CalendarFormat.month
                    ? CalendarFormat.week
                    : CalendarFormat.month),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: s.cardAlt,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: s.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _calFormat == CalendarFormat.month
                            ? CupertinoIcons.calendar
                            : CupertinoIcons.calendar_today,
                        size: 13,
                        color: s.dark ? const Color(0xFFA5B4FC) : VibePalette.primary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _calFormat == CalendarFormat.month ? 'Mese' : 'Sett.',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: s.dark ? const Color(0xFFA5B4FC) : VibePalette.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: s.cardAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: s.border),
                ),
                child: Row(
                  children: [
                    _softIconButton(
                      s,
                      CupertinoIcons.chevron_left,
                      () => setState(() =>
                          _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1, 1)),
                    ),
                    _softIconButton(
                      s,
                      CupertinoIcons.chevron_right,
                      () => setState(() =>
                          _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 1)),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _focusedDay = DateTime.now();
                    _selectedDay = DateTime.now();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(
                    color: alphaCol(VibePalette.primary, 0.13),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: alphaCol(VibePalette.primary, 0.35)),
                  ),
                  child: const Row(
                    children: [
                      Icon(CupertinoIcons.location_solid, size: 12, color: Color(0xFF818CF8)),
                      SizedBox(width: 5),
                      Text('Oggi',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF818CF8))),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TableCalendar<SchoolEvent>(
            locale: 'it_IT',
            firstDay: DateTime.utc(2023, 9, 1),
            lastDay: DateTime.utc(2030, 8, 31),
            focusedDay: _focusedDay,
            calendarFormat: _calFormat,
            startingDayOfWeek: StartingDayOfWeek.monday,
            availableGestures: AvailableGestures.horizontalSwipe,
            headerVisible: false,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            eventLoader: _eventsForDay,
            onDaySelected: (sel, foc) {
              HapticFeedback.selectionClick();
              setState(() {
                _selectedDay = sel;
                _focusedDay = foc;
                _emptyIdx = (_emptyIdx + 1) % _chillEmptyQuotes.length;
              });
            },
            onPageChanged: (foc) => setState(() => _focusedDay = foc),
            daysOfWeekHeight: 26,
            rowHeight: 46,
            daysOfWeekStyle: DaysOfWeekStyle(
              dowTextFormatter: (dt, loc) =>
                  DateFormat.E(loc).format(dt).replaceAll('.', '').toUpperCase(),
              weekdayStyle: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: s.faint),
              weekendStyle: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: s.faint),
            ),
            calendarStyle: CalendarStyle(
              cellMargin: const EdgeInsets.all(4),
              defaultTextStyle: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13.5, color: s.txt),
              weekendTextStyle: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13.5, color: s.txt),
              outsideTextStyle: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13, color: alphaCol(s.muted, 0.4)),
              todayDecoration: BoxDecoration(
                color: alphaCol(VibePalette.primary, 0.10),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: alphaCol(VibePalette.primary, 0.8), width: 1.4),
              ),
              todayTextStyle: TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 13.5, color: s.txt),
              selectedDecoration: BoxDecoration(
                gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [VibePalette.primary, VibePalette.primaryGlow]),
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                      color: alphaCol(VibePalette.primary, 0.42),
                      blurRadius: 12,
                      offset: const Offset(0, 5)),
                ],
              ),
              selectedTextStyle: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 13.5, color: Colors.white),
            ),
            calendarBuilders: CalendarBuilders(
              markerBuilder: (_, __, evs) => evs.isEmpty
                  ? const SizedBox.shrink()
                  : Positioned(
                      bottom: 3,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: evs
                            .take(3)
                            .map((e) => Container(
                                  width: 5,
                                  height: 5,
                                  margin: const EdgeInsets.symmetric(horizontal: 1.2),
                                  decoration: BoxDecoration(
                                      color: e.category.color, shape: BoxShape.circle),
                                ))
                            .toList(),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Divider(color: s.hairline, height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: EventCategory.values
                .map((c) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(color: c.color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(c.label,
                            style: TextStyle(
                                fontSize: 11.5, fontWeight: FontWeight.w600, color: s.muted)),
                      ],
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _dayAgendaCard(VibeSkin s, List<SchoolEvent> dayEvents) {
    final rawDay = DateFormat('EEEE d MMMM', 'it_IT').format(_selectedDay);
    final dayTitle =
        rawDay.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: s.panel(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: s.txt)),
                    const SizedBox(height: 2),
                    Text(
                      dayEvents.isEmpty
                          ? 'Nessun impegno'
                          : '${dayEvents.length} ${dayEvents.length == 1 ? 'impegno' : 'impegni'} in agenda',
                      style: TextStyle(fontSize: 11.5, color: s.faint),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _showEventModal(baseDate: _selectedDay),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: alphaCol(VibePalette.primary, 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: alphaCol(VibePalette.primary, 0.35)),
                  ),
                  child: const Row(
                    children: [
                      Icon(CupertinoIcons.add, size: 13, color: Color(0xFF818CF8)),
                      SizedBox(width: 4),
                      Text('Aggiungi',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF818CF8))),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (dayEvents.isEmpty)
            CustomPaint(
              painter: _DashedRRectPainter(color: s.border, radius: 18),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
                decoration: BoxDecoration(
                  color: s.dark ? alphaCol(VibePalette.darkCardAlt, 0.5) : VibePalette.lightCardAlt,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    Icon(CupertinoIcons.calendar_badge_minus, size: 26, color: s.faint),
                    const SizedBox(height: 8),
                    Text(_chillEmptyQuotes[_emptyIdx],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            color: s.muted)),
                  ],
                ),
              ),
            )
          else
            ...dayEvents.map((e) => _eventCardTile(e, s)),
        ],
      ),
    );
  }

  String _countdownText(DateTime dt) {
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return isSameDay(dt, DateTime.now()) ? 'Oggi' : 'Passato';
    if (diff.inDays >= 1) return 'Tra ${diff.inDays}g ${diff.inHours % 24}h';
    if (diff.inHours >= 1) return 'Tra ${diff.inHours}h ${diff.inMinutes % 60}m';
    return 'Tra ${max(1, diff.inMinutes)}m';
  }

  Widget _eventCardTile(SchoolEvent ev, VibeSkin s, {bool showDate = false}) {
    final c = ev.category.color;
    final accent = ev.completed ? s.faint : c;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showEventModal(existing: ev),
          child: Ink(
            decoration: BoxDecoration(
              color: s.cardAlt,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: ev.completed ? s.border : alphaCol(c, s.dark ? 0.38 : 0.28)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      final i = _events.indexWhere((x) => x.id == ev.id);
                      if (i != -1) {
                        setState(() =>
                            _events[i] = _events[i].copyWith(completed: !ev.completed));
                        await _saveEvents();
                      }
                    },
                    child: AnimatedContainer(
                      duration: VibeMetrics.fast,
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ev.completed ? VibePalette.okGreen : alphaCol(c, 0.12),
                        border: Border.all(
                            color: ev.completed ? VibePalette.okGreen : alphaCol(c, 0.75),
                            width: 1.8),
                      ),
                      child: ev.completed
                          ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                ev.category.label.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.7,
                                  color: accent,
                                ),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              width: 3,
                              height: 3,
                              decoration: BoxDecoration(
                                  color: alphaCol(s.muted, 0.5), shape: BoxShape.circle),
                            ),
                            Flexible(
                              child: Text(
                                ev.subject,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: s.muted,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (!ev.completed)
                              Text(
                                _countdownText(ev.dateTime),
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: s.faint),
                              ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          ev.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            height: 1.28,
                            letterSpacing: -0.2,
                            color: ev.completed ? s.faint : s.txt,
                            decoration: ev.completed ? TextDecoration.lineThrough : null,
                            decorationColor: s.faint,
                          ),
                        ),
                        if (ev.notes.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(ev.notes,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: s.faint)),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(CupertinoIcons.clock, size: 11, color: s.faint),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                showDate
                                    ? '${_dayLabel(ev.dateTime)} · ${DateFormat('HH:mm').format(ev.dateTime)}'
                                    : DateFormat('d MMM · HH:mm', 'it_IT').format(ev.dateTime),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: s.faint),
                              ),
                            ),
                            if (ev.fromArgo) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: alphaCol(VibePalette.okGreen, 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  ev.editedByUser ? 'ARGO ✎' : 'ARGO',
                                  style: const TextStyle(
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.3,
                                      color: VibePalette.okGreen),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Azioni',
                    padding: EdgeInsets.zero,
                    splashRadius: 18,
                    icon: Icon(CupertinoIcons.ellipsis, size: 17, color: s.faint),
                    color: s.card,
                    elevation: 8,
                    position: PopupMenuPosition.under,
                    shape:
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    onSelected: (v) {
                      if (v == 'edit') {
                        _showEventModal(existing: ev);
                      } else if (v == 'delete') {
                        _deleteEvent(ev);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            const Icon(CupertinoIcons.pencil,
                                size: 15, color: Color(0xFF818CF8)),
                            const SizedBox(width: 9),
                            Text('Modifica', style: TextStyle(fontSize: 13, color: s.txt)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(CupertinoIcons.trash,
                                size: 15, color: VibePalette.verificaRed),
                            const SizedBox(width: 9),
                            Text('Elimina',
                                style: TextStyle(
                                    fontSize: 13, color: VibePalette.verificaRed)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return 'Oggi';
    if (diff == 1) return 'Domani';
    if (diff == -1) return 'Ieri';
    final raw = DateFormat('EEE d MMM', 'it_IT').format(d);
    return raw[0].toUpperCase() + raw.substring(1);
  }

  Widget _buildListWithCountdown(VibeSkin s) {
    final list = _upcomingFiltered;
    final groups = <DateTime, List<SchoolEvent>>{};
    for (final e in list) {
      final key = DateTime(e.dateTime.year, e.dateTime.month, e.dateTime.day);
      groups.putIfAbsent(key, () => []).add(e);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (list.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(26),
            decoration: s.panel(24),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: alphaCol(VibePalette.primary, 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(CupertinoIcons.checkmark_seal,
                      color: VibePalette.primary, size: 24),
                ),
                const SizedBox(height: 12),
                Text('Nessun impegno in programma',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800, color: s.txt)),
                const SizedBox(height: 4),
                Text('Aggiungi una verifica o un\'interrogazione per iniziare.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: s.muted)),
              ],
            ),
          )
        else
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4, bottom: 8),
              child: Row(
                children: [
                  Text(
                    _dayLabel(entry.key).toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                      color: s.faint,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      DateFormat('d MMMM', 'it_IT').format(entry.key),
                      style: TextStyle(fontSize: 11, color: s.faint),
                    ),
                  ),
                  if (entry.key.difference(DateTime.now()).inDays.abs() <= 7)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: alphaCol(VibePalette.primary, 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${entry.value.where((e) => !e.completed).length} da fare',
                        style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF818CF8)),
                      ),
                    ),
                ],
              ),
            ),
            ...entry.value.map((e) => _eventCardTile(e, s, showDate: false)),
            const SizedBox(height: 4),
          ],
      ],
    );
  }

  // --------------------------------------------------------------------------
  // TAB 2: ORARIO SCOLASTICO (SEGUE IN .ui_part2)
  // --------------------------------------------------------------------------

  // --------------------------------------------------------------------------
  // TAB 2: ORARIO SCOLASTICO
  // --------------------------------------------------------------------------

  Widget _buildTimetableTab(VibeSkin s) {
    final sched = _timetable[_ttDay] ?? DaySchedule.initial();
    final todayWd = DateTime.now().weekday;
    final totalHours = _timetable.values
        .fold<int>(0, (acc, d) => acc + d.slots.where((x) => x.subject.trim().isNotEmpty).length);

    final dayRows = <Widget>[];
    bool gapAdded = false;
    bool hasMorningBefore = false;

    for (int i = 0; i < sched.slots.length; i++) {
      final slot = sched.slots[i];
      final afternoon = slot.isAfternoon(i);
      if (afternoon && hasMorningBefore && !gapAdded) {
        dayRows.add(_lunchBreak(s));
        gapAdded = true;
      }
      if (!afternoon) hasMorningBefore = true;
      dayRows.add(_lessonRow(
        slotIndex: i,
        slot: slot,
        isAfternoon: afternoon,
        s: s,
        onTap: () => _editLessonSlotModal(_ttDay, i),
      ));
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(VibeMetrics.pagePad, 4, VibeMetrics.pagePad, 110),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Orario Scolastico',
                      style: TextStyle(
                          fontSize: 19.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          color: s.txt)),
                  const SizedBox(height: 2),
                  Text('$totalHours ore di lezione in settimana',
                      style: TextStyle(fontSize: 11.5, color: s.faint)),
                ],
              ),
            ),
            _iconToggle(
              s,
              left: CupertinoIcons.calendar_today,
              right: CupertinoIcons.square_grid_2x2,
              leftLabel: 'Giorno',
              rightLabel: 'Settimana',
              rightActive: _ttWeekOverview,
              onChanged: (v) => setState(() => _ttWeekOverview = v),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_ttWeekOverview)
          _buildWeekOverview(s)
        else ...[
          _daySelector(s, todayWd),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: s.panel(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _dayNames[_ttDay]!,
                            style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                color: s.txt),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${sched.slots.length} ore'
                            '${sched.afternoonCount > 0 ? ' · ${sched.afternoonCount} al pomeriggio' : ''}',
                            style: TextStyle(fontSize: 11.5, color: s.faint),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: s.cardAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: s.border),
                      ),
                      child: Row(
                        children: [
                          _softIconButton(
                            s,
                            CupertinoIcons.minus,
                            sched.slots.isEmpty
                                ? () {}
                                : () async {
                                    final next = [...sched.slots]..removeLast();
                                    setState(() =>
                                        _timetable[_ttDay] = DaySchedule(slots: next));
                                    await _saveTimetable();
                                  },
                          ),
                          _softIconButton(
                            s,
                            CupertinoIcons.plus,
                            sched.slots.length >= 10
                                ? () {}
                                : () async {
                                    final newIdx = sched.slots.length;
                                    final next = [
                                      ...sched.slots,
                                      LessonSlot(time: DaySchedule.defaultSlotTime(newIdx)),
                                    ];
                                    setState(() =>
                                        _timetable[_ttDay] = DaySchedule(slots: next));
                                    await _saveTimetable();
                                  },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (dayRows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(CupertinoIcons.clock, size: 26, color: s.faint),
                          const SizedBox(height: 8),
                          Text('Nessuna ora impostata',
                              style: TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w700, color: s.muted)),
                          const SizedBox(height: 2),
                          Text('Usa + per aggiungere la prima ora.',
                              style: TextStyle(fontSize: 11.5, color: s.faint)),
                        ],
                      ),
                    ),
                  )
                else
                  ...dayRows,
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _iconToggle(
    VibeSkin s, {
    required IconData left,
    required IconData right,
    required String leftLabel,
    required String rightLabel,
    required bool rightActive,
    required ValueChanged<bool> onChanged,
  }) {
    Widget btn(IconData icon, String label, bool active, bool value) => GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onChanged(value);
          },
          child: AnimatedContainer(
            duration: VibeMetrics.fast,
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: active
                  ? const LinearGradient(
                      colors: [VibePalette.primary, VibePalette.primaryGlow])
                  : null,
              borderRadius: BorderRadius.circular(10),
              boxShadow: active
                  ? [
                      BoxShadow(
                          color: alphaCol(VibePalette.primary, 0.32),
                          blurRadius: 10,
                          offset: const Offset(0, 4)),
                    ]
                  : null,
            ),
            child: Tooltip(
              message: label,
              child: Icon(icon, size: 15, color: active ? Colors.white : s.muted),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: s.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: s.border),
        boxShadow: s.cardShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(left, leftLabel, !rightActive, false),
          const SizedBox(width: 3),
          btn(right, rightLabel, rightActive, true),
        ],
      ),
    );
  }

  Widget _daySelector(VibeSkin s, int todayWd) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));

    return Row(
      children: [
        for (int wd = 1; wd <= 5; wd++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: wd < 5 ? 7 : 0),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _ttDay = wd);
                },
                child: AnimatedContainer(
                  duration: VibeMetrics.fast,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: _ttDay == wd
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [VibePalette.primary, VibePalette.primaryGlow])
                        : null,
                    color: _ttDay == wd ? null : s.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _ttDay == wd
                          ? Colors.transparent
                          : (todayWd == wd ? alphaCol(VibePalette.capBlue, 0.6) : s.border),
                    ),
                    boxShadow: _ttDay == wd
                        ? [
                            BoxShadow(
                                color: alphaCol(VibePalette.primary, 0.35),
                                blurRadius: 16,
                                offset: const Offset(0, 7)),
                          ]
                        : s.cardShadow,
                  ),
                  child: Column(
                    children: [
                      Text(
                        _dayShort[wd]!,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                          color: _ttDay == wd ? Colors.white : s.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${monday.add(Duration(days: wd - 1)).day}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                          color: _ttDay == wd ? Colors.white : s.txt,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: todayWd == wd
                              ? (_ttDay == wd ? Colors.white : VibePalette.capBlue)
                              : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _lunchBreak(VibeSkin s) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(child: Divider(color: s.hairline, height: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(Icons.restaurant_rounded, size: 11, color: s.faint),
                  const SizedBox(width: 5),
                  Text('Pausa pranzo',
                      style: TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w700, color: s.faint)),
                ],
              ),
            ),
            Expanded(child: Divider(color: s.hairline, height: 1)),
          ],
        ),
      );

  Widget _lessonRow({
    required int slotIndex,
    required LessonSlot slot,
    required bool isAfternoon,
    required VibeSkin s,
    required VoidCallback onTap,
  }) {
    final hasSubj = slot.subject.trim().isNotEmpty;
    final col = hasSubj
        ? subjectAccent(slot.subject)
        : (isAfternoon ? VibePalette.interrogazioneAmber : VibePalette.capBlue);
    final displayTime =
        slot.time.trim().isNotEmpty ? slot.time.trim() : DaySchedule.defaultSlotTime(slotIndex);
    final parts = displayTime.split('-');
    final start = parts.isNotEmpty ? parts.first.trim() : displayTime;
    final end = parts.length > 1 ? parts.last.trim() : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: hasSubj ? alphaCol(col, s.dark ? 0.10 : 0.07) : s.cardAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: hasSubj ? alphaCol(col, 0.32) : s.border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 34,
                    decoration: BoxDecoration(
                      color: hasSubj ? col : alphaCol(s.muted, 0.35),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 46,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          start,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            color: hasSubj ? s.txt : s.muted,
                          ),
                        ),
                        Text(
                          end,
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: s.faint),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasSubj ? slot.subject : 'Ora libera',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: hasSubj ? FontWeight.w800 : FontWeight.w500,
                            fontStyle: hasSubj ? FontStyle.normal : FontStyle.italic,
                            color: hasSubj ? s.txt : s.faint,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${slotIndex + 1}ª ora${isAfternoon ? ' · pomeriggio' : ''}',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600, color: s.faint),
                        ),
                      ],
                    ),
                  ),
                  Icon(CupertinoIcons.pencil, size: 15, color: alphaCol(col, 0.75)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeekOverview(VibeSkin s) {
    return Column(
      children: [
        for (int wd = 1; wd <= 5; wd++)
          Builder(builder: (_) {
            final day = _timetable[wd] ?? DaySchedule.initial();
            final filled = day.slots.where((x) => x.subject.trim().isNotEmpty).toList();
            return GestureDetector(
              onTap: () => setState(() {
                _ttDay = wd;
                _ttWeekOverview = false;
              }),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
                decoration: s.panel(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: alphaCol(VibePalette.primary, 0.12),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            _dayShort[wd]!,
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: VibePalette.primary),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_dayNames[wd]!,
                                  style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                      color: s.txt)),
                              Text(
                                filled.isEmpty
                                    ? 'Nessuna materia'
                                    : '${filled.length} ore'
                                        '${day.afternoonCount > 0 ? ' · ${day.afternoonCount} pom' : ''}',
                                style: TextStyle(fontSize: 10.5, color: s.faint),
                              ),
                            ],
                          ),
                        ),
                        Icon(CupertinoIcons.chevron_right, size: 15, color: s.faint),
                      ],
                    ),
                    if (day.slots.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          for (int i = 0; i < day.slots.length; i++)
                            Expanded(
                              child: Container(
                                height: 5,
                                margin: EdgeInsets.only(
                                    right: i == day.slots.length - 1 ? 0 : 3),
                                decoration: BoxDecoration(
                                  color: day.slots[i].subject.trim().isEmpty
                                      ? alphaCol(s.muted, 0.22)
                                      : subjectAccent(day.slots[i].subject),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (filled.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (int i = 0; i < day.slots.length; i++)
                            if (day.slots[i].subject.trim().isNotEmpty)
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: alphaCol(
                                      subjectAccent(day.slots[i].subject), 0.14),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  '${i + 1}ª ${day.slots[i].subject}',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: subjectAccent(day.slots[i].subject),
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  // Tendina modifica materia: nessun orario nel titolo, nessuna materia
  // consigliata, max 2 ore, nessuna casella Aula. Logica invariata.
  void _editLessonSlotModal(int weekday, int idx) {
    final sched = _timetable[weekday] ?? DaySchedule.initial();
    if (idx < 0 || idx >= sched.slots.length) return;
    final s = VibeSkin(widget.isDark);

    (int, int) boundsOf(int i) {
      if (i < sched.slots.length) {
        final p = parseSlotMinutes(sched.slots[i].time);
        if (p != null) return p;
      }
      return DaySchedule.officialBounds(i);
    }

    final current = sched.slots[idx];
    int initialSpan = 1;
    if (current.subject.trim().isNotEmpty &&
        idx + 1 < sched.slots.length &&
        sched.slots[idx + 1].subject.trim().toLowerCase() ==
            current.subject.trim().toLowerCase()) {
      initialSpan = 2;
    }

    int startMin = boundsOf(idx).$1;
    int endMin = boundsOf(idx + initialSpan - 1).$2;
    if (endMin <= startMin) endMin = startMin + 60;

    final subjCtrl = TextEditingController(text: current.subject);

    int findStartSlot(int sMin) {
      for (int i = 0; i < max(sched.slots.length, 8); i++) {
        if ((boundsOf(i).$1 - sMin).abs() <= 10) return i;
      }
      return idx;
    }

    int calcSpan(int sMin, int eMin) {
      if (eMin <= sMin) return 1;
      final sIdx = findStartSlot(sMin);
      int count = 0;
      for (int k = 0; k < 2; k++) {
        final b = boundsOf(sIdx + k);
        final overlap = min(eMin, b.$2) - max(sMin, b.$1);
        if (overlap >= 20) {
          count++;
        } else if (b.$1 >= eMin) {
          break;
        }
      }
      return count.clamp(1, 2);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: s.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) {
          final sIdx = findStartSlot(startMin);
          final span = calcSpan(startMin, endMin);
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(ctx).viewInsets.bottom + 22),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sheetHandle(s),
                  const SizedBox(height: 14),
                  Text(
                    '${_dayNames[weekday]} · ${idx + 1}ª ora',
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: s.txt),
                  ),
                  const SizedBox(height: 3),
                  Text('Inserisci la materia e l\'orario della lezione',
                      style: TextStyle(fontSize: 12.5, color: s.muted)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: subjCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: fieldDeco('Materia', icon: CupertinoIcons.book),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(CupertinoIcons.clock, size: 15),
                          label: Text('Dalle ${fmtMin(startMin)}'),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: ctx,
                              initialTime:
                                  TimeOfDay(hour: startMin ~/ 60, minute: startMin % 60),
                            );
                            if (picked != null) {
                              setM(() {
                                startMin = picked.hour * 60 + picked.minute;
                                final ns = findStartSlot(startMin);
                                if (endMin <= startMin) endMin = boundsOf(ns).$2;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(CupertinoIcons.clock_fill, size: 15),
                          label: Text('Alle ${fmtMin(endMin)}'),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: ctx,
                              initialTime: TimeOfDay(hour: endMin ~/ 60, minute: endMin % 60),
                            );
                            if (picked != null) {
                              final cand = picked.hour * 60 + picked.minute;
                              if (cand > startMin) setM(() => endMin = cand);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [1, 2].map((h) {
                      final active = span == h;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _pill(
                          s: s,
                          label: h == 1 ? '1 ora' : '2 ore',
                          selected: active,
                          accent: VibePalette.primary,
                          onTap: () => setM(() {
                            startMin = boundsOf(sIdx).$1;
                            endMin = boundsOf(sIdx + h - 1).$2;
                          }),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final next = [...sched.slots];
                          next[idx] = LessonSlot(time: DaySchedule.defaultSlotTime(idx));
                          setState(() => _timetable[weekday] = DaySchedule(slots: next));
                          await _saveTimetable();
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: VibePalette.verificaRed,
                          side: BorderSide(color: alphaCol(VibePalette.verificaRed, 0.4)),
                        ),
                        icon: const Icon(CupertinoIcons.clear_circled, size: 15),
                        label: const Text('Svuota'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            final subj = subjCtrl.text.trim();
                            final work = [...sched.slots];

                            for (int k = 0; k < span; k++) {
                              final target = sIdx + k;
                              final official = DaySchedule.defaultSlotTime(target);
                              final b = DaySchedule.officialBounds(target);
                              final customSingle = span == 1 &&
                                  ((startMin - b.$1).abs() > 5 || (endMin - b.$2).abs() > 5);
                              final slotVal = LessonSlot(
                                subject: subj,
                                time: customSingle
                                    ? '${fmtMin(startMin)} - ${fmtMin(endMin)}'
                                    : official,
                              );
                              while (work.length <= target) {
                                work.add(
                                    LessonSlot(time: DaySchedule.defaultSlotTime(work.length)));
                              }
                              work[target] = slotVal;
                            }

                            if (sIdx == idx &&
                                span < initialSpan &&
                                (idx + 1) < work.length) {
                              work[idx + 1] =
                                  LessonSlot(time: DaySchedule.defaultSlotTime(idx + 1));
                            }

                            setState(() => _timetable[weekday] = DaySchedule(slots: work));
                            await _saveTimetable();
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          child: const Text('Salva lezione'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 3: VOTI & MEDIE
  // --------------------------------------------------------------------------

  double _avg(List<SchoolGrade> list) {
    if (list.isEmpty) return 0;
    if (!_weightedAvg) return list.fold<double>(0, (a, g) => a + g.value) / list.length;
    final valid = list.where((g) => g.weight > 0).toList();
    if (valid.isEmpty) return 0;
    final wSum = valid.fold<double>(0, (a, g) => a + g.value * g.weight);
    final wTot = valid.fold<double>(0, (a, g) => a + g.weight);
    return wTot == 0 ? 0 : wSum / wTot;
  }

  Color _gradeCol(double v) => v >= 6.0
      ? VibePalette.okGreen
      : (v >= 5.5 ? VibePalette.interrogazioneAmber : VibePalette.verificaRed);

  Widget _buildGradesTab(VibeSkin s) {
    final grouped = <String, List<SchoolGrade>>{};
    for (final g in _grades) {
      grouped.putIfAbsent(g.subject, () => []).add(g);
    }
    final subjects = grouped.keys.toList()..sort();
    final totalAvg = _avg(_grades);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(VibeMetrics.pagePad, 4, VibeMetrics.pagePad, 120),
      children: [
        _gradeHero(s, totalAvg, subjects.length),
        const SizedBox(height: 12),
        if (_grades.isNotEmpty) ...[
          _distributionCard(s),
          const SizedBox(height: 12),
        ],
        if (subjects.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: s.panel(24),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: alphaCol(VibePalette.primary, 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(CupertinoIcons.chart_bar_alt_fill,
                      size: 24, color: VibePalette.primary),
                ),
                const SizedBox(height: 14),
                Text('Nessun voto presente',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800, color: s.txt)),
                const SizedBox(height: 6),
                Text(
                  'Sincronizza Argo nelle impostazioni oppure premi + per registrare un voto.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: s.muted),
                ),
              ],
            ),
          )
        else ...[
          _sectionLabel(s, 'Materie', CupertinoIcons.book),
          ...subjects.map((subject) => _subjectCard(s, subject, grouped[subject]!)),
        ],
      ],
    );
  }

  Widget _gradeHero(VibeSkin s, double totalAvg, int subjectCount) {
    final col = _grades.isEmpty ? VibePalette.primary : _gradeCol(totalAvg);
    final progress = _grades.isEmpty ? 0.0 : (totalAvg / 10).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            alphaCol(VibePalette.primary, s.dark ? 0.26 : 0.14),
            s.card,
          ],
        ),
        border: Border.all(color: s.border),
        boxShadow: s.cardShadow,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            height: 90,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => CustomPaint(
                painter: _RingPainter(
                  progress: value,
                  stroke: 9,
                  track: alphaCol(s.muted, 0.18),
                  colors: [col, alphaCol(col, 0.55)],
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _grades.isEmpty ? '--' : totalAvg.toStringAsFixed(2),
                        style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                            height: 1.05,
                            color: s.txt),
                      ),
                      Text('/ 10',
                          style: TextStyle(
                              fontSize: 9.5, fontWeight: FontWeight.w700, color: s.faint)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MEDIA GENERALE',
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: s.faint)),
                const SizedBox(height: 3),
                Text(
                  _weightedAvg ? 'Ponderata' : 'Aritmetica',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: s.txt),
                ),
                const SizedBox(height: 3),
                Text(
                  _grades.isEmpty
                      ? 'Aggiungi il primo voto'
                      : '${_grades.length} voti · $subjectCount materie',
                  style: TextStyle(fontSize: 11.5, color: s.muted),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _miniToggle(
                      s,
                      label: 'Ponderata',
                      active: _weightedAvg,
                      onTap: () => setState(() => _weightedAvg = true),
                    ),
                    _miniToggle(
                      s,
                      label: 'Aritmetica',
                      active: !_weightedAvg,
                      onTap: () => setState(() => _weightedAvg = false),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniToggle(VibeSkin s,
      {required String label, required bool active, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: VibeMetrics.fast,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: active ? alphaCol(VibePalette.primary, 0.18) : s.cardAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active ? alphaCol(VibePalette.primary, 0.5) : s.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: active ? const Color(0xFF818CF8) : s.muted,
          ),
        ),
      ),
    );
  }

  Widget _distributionCard(VibeSkin s) {
    final buckets = <String, int>{
      'Insufficienti': _grades.where((g) => g.value < 6).length,
      'Sufficienti': _grades.where((g) => g.value >= 6 && g.value < 7.5).length,
      'Buoni': _grades.where((g) => g.value >= 7.5 && g.value < 8.5).length,
      'Ottimi': _grades.where((g) => g.value >= 8.5).length,
    };
    final colors = {
      'Insufficienti': VibePalette.verificaRed,
      'Sufficienti': VibePalette.interrogazioneAmber,
      'Buoni': VibePalette.capBlue,
      'Ottimi': VibePalette.okGreen,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: s.panel(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Distribuzione',
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800, color: s.txt)),
              const Spacer(),
              Text('${_grades.length} voti',
                  style: TextStyle(fontSize: 11, color: s.faint)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  for (final e in buckets.entries)
                    if (e.value > 0)
                      Expanded(
                        flex: e.value,
                        child: Container(
                          margin: const EdgeInsets.only(right: 2),
                          color: colors[e.key],
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: buckets.entries
                .map((e) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: colors[e.key], shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 5),
                        Text('${e.key} ${e.value}',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: s.muted)),
                      ],
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _subjectCard(VibeSkin s, String subject, List<SchoolGrade> list) {
    final m = _avg(list);
    final col = _gradeCol(m);
    final target = m < 6.0 ? 6.0 : 8.0;
    final needed =
        target * (list.length + 1) - list.fold<double>(0, (a, b) => a + b.value);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: s.panel(20),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          iconColor: s.muted,
          collapsedIconColor: s.faint,
          leading: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: alphaCol(col, 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: alphaCol(col, 0.3)),
            ),
            child: Text(
              m.toStringAsFixed(1),
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.6, color: col),
            ),
          ),
          title: Text(
            subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: s.txt),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 3),
              Text(
                needed > 0 && needed <= 10
                    ? '${list.length} ${list.length == 1 ? 'voto' : 'voti'} · '
                        'per l\'${target.toInt()} serve ${needed.toStringAsFixed(1)}'
                    : '${list.length} ${list.length == 1 ? 'voto' : 'voti'} · media solida',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: s.muted),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (m / target).clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: alphaCol(s.muted, 0.18),
                  valueColor: AlwaysStoppedAnimation(col),
                ),
              ),
            ],
          ),
          children: [
            for (final g in list) ...[
              Container(
                margin: const EdgeInsets.only(top: 7),
                padding: const EdgeInsets.fromLTRB(10, 9, 4, 9),
                decoration: BoxDecoration(
                  color: s.cardAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: s.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: alphaCol(_gradeCol(g.value), 0.14),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text(
                        g.value.toStringAsFixed(1),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: _gradeCol(g.value)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            g.description.isEmpty ? 'Prova ${g.type}' : g.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: s.txt),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${g.type} · peso ${(g.weight * 100).round()}% · '
                            '${DateFormat('dd/MM/yy').format(g.date)}'
                            '${g.fromArgo ? ' · ARGO' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, color: s.faint),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Elimina voto',
                      icon: Icon(CupertinoIcons.trash, size: 15, color: s.faint),
                      onPressed: () async {
                        setState(() => _grades.removeWhere((x) => x.id == g.id));
                        await _saveGrades();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // MODALI
  // --------------------------------------------------------------------------

  Widget _sheetHandle(VibeSkin s) => Center(
        child: Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: alphaCol(s.muted, 0.35),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  void _showEventModal({DateTime? baseDate, SchoolEvent? existing}) {
    final isEdit = existing != null;
    final s = VibeSkin(widget.isDark);
    final subjCtrl = TextEditingController(text: existing?.subject ?? '');
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    var cat = existing?.category ?? EventCategory.verifica;
    final startDay = baseDate ?? DateTime.now();
    var dt = existing?.dateTime ?? DateTime(startDay.year, startDay.month, startDay.day, 8, 15);
    var remMode = existing?.reminderMode ?? EventReminderMode.defaultBoth;
    DateTime customRem = existing?.customReminderAt ??
        DateTime(dt.year, dt.month, dt.day, 17, 0).subtract(const Duration(days: 1));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: s.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(ctx).viewInsets.bottom + 22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(s),
                const SizedBox(height: 14),
                Text(
                  isEdit ? 'Modifica impegno' : 'Nuovo impegno',
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: s.txt),
                ),
                const SizedBox(height: 3),
                Text(
                  isEdit
                      ? 'Aggiorna i dettagli e le notifiche collegate'
                      : 'Verifica, interrogazione o qualsiasi scadenza',
                  style: TextStyle(fontSize: 12.5, color: s.muted),
                ),
                const SizedBox(height: 16),
                _sectionLabel(s, 'Tipo', CupertinoIcons.tag),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: EventCategory.values
                      .map((c) => _pill(
                            s: s,
                            label: c.label,
                            selected: cat == c,
                            accent: c.color,
                            onTap: () => setM(() => cat = c),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: subjCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: fieldDeco('Materia', icon: CupertinoIcons.book),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: titleCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 1,
                  maxLines: 3,
                  decoration: fieldDeco('Argomento / titolo'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(CupertinoIcons.calendar, size: 15),
                        label: Text(DateFormat('dd/MM/yyyy').format(dt)),
                        onPressed: () async {
                          final p = await showDatePicker(
                              context: ctx,
                              initialDate: dt,
                              firstDate: DateTime(2023),
                              lastDate: DateTime(2030));
                          if (p != null) {
                            setM(() {
                              dt = DateTime(p.year, p.month, p.day, dt.hour, dt.minute);
                              if (!isEdit && remMode != EventReminderMode.custom) {
                                customRem = DateTime(p.year, p.month, p.day, 17, 0)
                                    .subtract(const Duration(days: 1));
                              }
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(CupertinoIcons.clock, size: 15),
                        label: Text(DateFormat('HH:mm').format(dt)),
                        onPressed: () async {
                          final t = await showTimePicker(
                              context: ctx, initialTime: TimeOfDay.fromDateTime(dt));
                          if (t != null) {
                            setM(() => dt = DateTime(dt.year, dt.month, dt.day, t.hour, t.minute));
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<EventReminderMode>(
                  value: remMode,
                  isExpanded: true,
                  decoration: fieldDeco('Quando ricevere la notifica',
                      icon: CupertinoIcons.bell),
                  items: EventReminderMode.values
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text(m.label,
                                style: TextStyle(fontSize: 13, color: s.txt),
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setM(() => remMode = v);
                  },
                ),
                if (remMode == EventReminderMode.custom) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(CupertinoIcons.bell_circle, size: 15),
                          label: Text(DateFormat('dd/MM/yyyy').format(customRem)),
                          onPressed: () async {
                            final p = await showDatePicker(
                              context: ctx,
                              initialDate: customRem,
                              firstDate: DateTime(2023),
                              lastDate: DateTime(2030),
                            );
                            if (p != null) {
                              setM(() => customRem = DateTime(
                                  p.year, p.month, p.day, customRem.hour, customRem.minute));
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(CupertinoIcons.time, size: 15),
                          label: Text(DateFormat('HH:mm').format(customRem)),
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: ctx,
                              initialTime: TimeOfDay.fromDateTime(customRem),
                            );
                            if (t != null) {
                              setM(() => customRem = DateTime(customRem.year,
                                  customRem.month, customRem.day, t.hour, t.minute));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    if (isEdit) ...[
                      OutlinedButton.icon(
                        onPressed: () async {
                          await _deleteEvent(existing);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: VibePalette.verificaRed,
                          side: BorderSide(color: alphaCol(VibePalette.verificaRed, 0.4)),
                        ),
                        icon: const Icon(CupertinoIcons.trash, size: 15),
                        label: const Text('Elimina'),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          final subj =
                              subjCtrl.text.trim().isEmpty ? 'Materia' : subjCtrl.text.trim();
                          final t = titleCtrl.text.trim().isEmpty
                              ? '${cat.label} di $subj'
                              : titleCtrl.text.trim();
                          setState(() {
                            if (isEdit) {
                              final idx = _events.indexWhere((x) => x.id == existing.id);
                              if (idx != -1) {
                                _events[idx] = existing.copyWith(
                                  title: t,
                                  subject: subj,
                                  dateTime: dt,
                                  category: cat,
                                  editedByUser: true,
                                  reminderMode: remMode,
                                  customReminderAt:
                                      remMode == EventReminderMode.custom ? customRem : null,
                                );
                              }
                            } else {
                              _events.add(SchoolEvent(
                                id: 'm_${DateTime.now().millisecondsSinceEpoch}',
                                title: t,
                                subject: subj,
                                dateTime: dt,
                                category: cat,
                                reminderMode: remMode,
                                customReminderAt:
                                    remMode == EventReminderMode.custom ? customRem : null,
                              ));
                            }
                            _selectedDay = dt;
                            _focusedDay = dt;
                          });
                          await _saveEvents();
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: Text(isEdit ? 'Salva modifiche' : 'Salva impegno'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddGradeModal() {
    final s = VibeSkin(widget.isDark);
    final subjCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    double val = 7.0;
    double weight = 1.0;
    String type = 'Scritto';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: s.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(ctx).viewInsets.bottom + 22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(s),
                const SizedBox(height: 14),
                Text('Nuovo voto',
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: s.txt)),
                const SizedBox(height: 3),
                Text('Registra una valutazione e aggiorna la media',
                    style: TextStyle(fontSize: 12.5, color: s.muted)),
                const SizedBox(height: 16),
                TextField(
                  controller: subjCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: fieldDeco('Materia', icon: CupertinoIcons.book),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  decoration: BoxDecoration(
                    color: s.cardAlt,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: s.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text('Voto',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: s.muted)),
                          const Spacer(),
                          Text(
                            val.toStringAsFixed(2),
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.8,
                                color: _gradeCol(val)),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(ctx).copyWith(
                          trackHeight: 5,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                        ),
                        child: Slider(
                            value: val,
                            min: 1,
                            max: 10,
                            divisions: 36,
                            label: val.toStringAsFixed(2),
                            onChanged: (v) => setM(() => val = v)),
                      ),
                      Row(
                        children: [
                          Text('Peso',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: s.muted)),
                          const Spacer(),
                          Text(
                            '${(weight * 100).round()}%',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: s.txt),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(ctx).copyWith(
                          trackHeight: 5,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                        ),
                        child: Slider(
                            value: weight,
                            min: 0.25,
                            max: 1.0,
                            divisions: 3,
                            label: '${(weight * 100).round()}%',
                            onChanged: (v) => setM(() => weight = v)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  children: ['Scritto', 'Orale', 'Pratico']
                      .map((t) => _pill(
                            s: s,
                            label: t,
                            selected: type == t,
                            accent: VibePalette.primary,
                            onTap: () => setM(() => type = t),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: fieldDeco('Argomento (opzionale)'),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      setState(() {
                        _grades.add(SchoolGrade(
                          id: 'g_${DateTime.now().millisecondsSinceEpoch}',
                          subject: subjCtrl.text.trim().isEmpty
                              ? 'Materia'
                              : subjCtrl.text.trim(),
                          value: val,
                          weight: weight,
                          type: type,
                          description: descCtrl.text.trim(),
                          date: DateTime.now(),
                        ));
                      });
                      await _saveGrades();
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Registra voto'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// TAB 4: IMPOSTAZIONI (NOTIFICHE + SINCRONIZZAZIONE ARGO)
// ============================================================================

class _SettingsTab extends StatefulWidget {
  final bool isDark;
  final Color cardColor, borderColor;
  final ArgoCredentials creds;
  final bool syncing, notifyOn, morningNotifyOn;
  final String? lastError;
  final Future<void> Function(String s, String u, String p) onSync;
  final Future<void> Function(String s, String u, String p) onDemo;
  final ValueChanged<bool> onToggleNotify;
  final ValueChanged<bool> onToggleMorningNotify;
  final VoidCallback onReset;

  const _SettingsTab({
    required this.isDark,
    required this.cardColor,
    required this.borderColor,
    required this.creds,
    required this.syncing,
    required this.lastError,
    required this.notifyOn,
    required this.morningNotifyOn,
    required this.onSync,
    required this.onDemo,
    required this.onToggleNotify,
    required this.onToggleMorningNotify,
    required this.onReset,
  });

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  late final _schoolCtrl = TextEditingController(text: widget.creds.schoolCode);
  late final _userCtrl = TextEditingController(text: widget.creds.username);
  late final _passCtrl = TextEditingController(text: widget.creds.password);
  bool _obscure = true;

  @override
  void dispose() {
    _schoolCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Widget _label(VibeSkin s, String text, IconData icon) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 14, color: VibePalette.primary),
            const SizedBox(width: 6),
            Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: s.faint,
              ),
            ),
          ],
        ),
      );

  Widget _switchRow(
    VibeSkin s, {
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: alphaCol(accent, 0.13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700, color: s.txt)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(fontSize: 11, height: 1.3, color: s.faint)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = VibeSkin(widget.isDark);
    final lastSync = widget.creds.lastSync;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(VibeMetrics.pagePad, 4, VibeMetrics.pagePad, 110),
      children: [
        Text('Impostazioni',
            style: TextStyle(
                fontSize: 19.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: s.txt)),
        const SizedBox(height: 2),
        Text('Notifiche, registro e dati sul dispositivo',
            style: TextStyle(fontSize: 11.5, color: s.faint)),
        const SizedBox(height: 18),

        _label(s, 'Notifiche', CupertinoIcons.bell),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          decoration: s.panel(24),
          child: Column(
            children: [
              _switchRow(
                s,
                icon: CupertinoIcons.bell_fill,
                accent: VibePalette.capBlue,
                title: 'Notifiche impegni ed eventi',
                subtitle: 'Ricevi i promemoria impostati sui tuoi impegni',
                value: widget.notifyOn,
                onChanged: widget.onToggleNotify,
              ),
              Divider(color: s.hairline, height: 1),
              _switchRow(
                s,
                icon: CupertinoIcons.sun_max_fill,
                accent: VibePalette.interrogazioneAmber,
                title: 'Orario ogni mattina alle 07:20',
                subtitle: 'Un promemoria per controllare le lezioni del giorno',
                value: widget.morningNotifyOn,
                onChanged: widget.onToggleMorningNotify,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => NotificationService.instance.sendTestNotification(),
                  icon: const Icon(CupertinoIcons.paperplane, size: 16),
                  label: const Text('Invia notifica di prova'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        _label(s, 'Registro Argo', CupertinoIcons.cloud_download),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: s.panel(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [VibePalette.capBlue, VibePalette.primary]),
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: [
                        BoxShadow(
                            color: alphaCol(VibePalette.capBlue, 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 6)),
                      ],
                    ),
                    child: const Icon(CupertinoIcons.cloud_download_fill,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('DidUP Famiglia',
                            style: TextStyle(
                                fontSize: 14.5, fontWeight: FontWeight.w800, color: s.txt)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: lastSync != null
                                    ? VibePalette.okGreen
                                    : VibePalette.interrogazioneAmber,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                lastSync != null
                                    ? 'Sincronizzato ${DateFormat('dd/MM · HH:mm').format(lastSync)}'
                                    : 'Non ancora sincronizzato',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: s.faint),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (widget.lastError != null && widget.lastError!.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: alphaCol(VibePalette.verificaRed, 0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: alphaCol(VibePalette.verificaRed, 0.35)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: VibePalette.verificaRed, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SelectableText(
                          widget.lastError!,
                          style: TextStyle(
                              fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w600, color: s.txt),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _schoolCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: fieldDeco('Codice scuola (es. SG12345)',
                    icon: CupertinoIcons.building_2_fill),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _userCtrl,
                autocorrect: false,
                decoration:
                    fieldDeco('Nome utente Argo', icon: CupertinoIcons.person_fill),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                decoration: fieldDeco(
                  'Password',
                  icon: CupertinoIcons.lock_fill,
                  suffix: IconButton(
                    icon: Icon(_obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                        size: 19, color: s.muted),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: widget.syncing
                      ? null
                      : () {
                          if (_schoolCtrl.text.trim().isEmpty ||
                              _userCtrl.text.trim().isEmpty ||
                              _passCtrl.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Inserisci Codice Scuola, Nome utente e Password.')),
                            );
                            return;
                          }
                          widget.onSync(_schoolCtrl.text, _userCtrl.text, _passCtrl.text);
                        },
                  icon: widget.syncing
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(CupertinoIcons.arrow_2_circlepath, size: 17),
                  label: Text(widget.syncing ? 'Sincronizzazione…' : 'Sincronizza Argo'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: widget.syncing
                      ? null
                      : () =>
                          widget.onDemo(_schoolCtrl.text, _userCtrl.text, _passCtrl.text),
                  icon: const Icon(CupertinoIcons.sparkles, size: 15),
                  label: const Text('Carica dati demo studente'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        _label(s, 'Dati sul dispositivo', CupertinoIcons.archivebox),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: s.panel(24),
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: alphaCol(VibePalette.verificaRed, 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(CupertinoIcons.trash,
                      size: 17, color: VibePalette.verificaRed),
                ),
                title: Text('Cancella eventi e voti',
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700, color: s.txt)),
                subtitle: Text('L\'orario scolastico viene mantenuto',
                    style: TextStyle(fontSize: 11, color: s.faint)),
                trailing: Icon(CupertinoIcons.chevron_right, size: 15, color: s.faint),
                onTap: widget.onReset,
              ),
              Divider(color: s.hairline, height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: alphaCol(VibePalette.okGreen, 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(CupertinoIcons.lock_shield,
                      size: 17, color: VibePalette.okGreen),
                ),
                title: Text('Offline e privato',
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700, color: s.txt)),
                subtitle: Text('I dati restano solo su questo dispositivo',
                    style: TextStyle(fontSize: 11, color: s.faint)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: Column(
            children: [
              Text('Calendario Scuola',
                  style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700, color: s.faint)),
              const SizedBox(height: 2),
              Text('Versione 1.0.0',
                  style: TextStyle(fontSize: 10, color: alphaCol(s.faint, 0.8))),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// PAINTER
// ============================================================================

class _RingPainter extends CustomPainter {
  final double progress;
  final double stroke;
  final Color track;
  final List<Color> colors;

  const _RingPainter({
    required this.progress,
    required this.stroke,
    required this.track,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - stroke) / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = track,
    );

    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      -pi / 2,
      2 * pi * p,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: colors,
          startAngle: -pi / 2,
          endAngle: 3 * pi / 2,
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.stroke != stroke || old.track != track;
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedRRectPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 11) {
        canvas.drawPath(metric.extractPath(d, min(d + 6, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

// === FINE FILE CALENDARIO SCUOLA ===
