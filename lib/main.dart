import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
      prefixIcon: icon != null ? Icon(icon) : null,
      suffixIcon: suffix,
      border: const OutlineInputBorder(),
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
  return palette[s.hashCode.abs() % palette.length];
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

  static ThemeData _base(Brightness b, Color bg, Color card, Color border, Color snackBg) =>
      ThemeData(
        useMaterial3: true,
        brightness: b,
        colorScheme: ColorScheme(
          brightness: b,
          primary: primary,
          onPrimary: Colors.white,
          secondary: primaryGlow,
          onSecondary: Colors.white,
          error: verificaRed,
          onError: Colors.white,
          surface: card,
          onSurface: b == Brightness.dark ? Colors.white : const Color(0xFF0F172A),
        ),
        scaffoldBackgroundColor: bg,
        cardColor: card,
        dividerColor: border,
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: snackBg,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );

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

  bool get isHighPriorityDefault =>
      this == EventCategory.verifica || this == EventCategory.interrogazione;
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

  static EventReminderMode fromKey(String? raw, {required bool fallbackActive}) {
    for (final m in EventReminderMode.values) {
      if (m.key == raw) return m;
    }
    return fallbackActive ? EventReminderMode.defaultBoth : EventReminderMode.none;
  }
}

class SchoolEvent {
  final String id, title, subject, notes;
  final DateTime dateTime;
  final EventCategory category;
  final bool highPriority, completed, fromArgo, editedByUser;
  final EventReminderMode reminderMode;
  final DateTime? customReminderAt;

  const SchoolEvent({
    required this.id,
    required this.title,
    required this.subject,
    this.notes = '',
    required this.dateTime,
    required this.category,
    this.highPriority = false,
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
    bool? highPriority,
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
        highPriority: highPriority ?? this.highPriority,
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
        'highPriority': highPriority,
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
    final prio = j['highPriority'] as bool? ?? cat.isHighPriorityDefault;
    final rem = EventReminderModeX.fromKey(
      j['reminderMode'] as String?,
      fallbackActive: prio || cat.isHighPriorityDefault,
    );
    final customRaw = j['customReminderAt'] as String?;
    return SchoolEvent(
      id: '${j['id'] ?? ''}',
      title: '${j['title'] ?? ''}',
      subject: '${j['subject'] ?? 'Materia'}',
      notes: '${j['notes'] ?? ''}',
      dateTime: DateTime.tryParse('${j['dateTime'] ?? ''}') ?? DateTime.now(),
      category: cat,
      highPriority: prio,
      completed: j['completed'] as bool? ?? false,
      fromArgo: j['fromArgo'] as bool? ?? false,
      editedByUser: j['editedByUser'] as bool? ?? false,
      reminderMode: rem,
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
        'subject': subject,
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
  final String subject, time, room;
  const LessonSlot({this.subject = '', this.time = '', this.room = ''});

  // Ore pomeridiane: dalle 13:45 in poi (es. 14:30 - 15:30, 15:30 - 16:30)
  bool isAfternoon(int slotIndex) {
    final parsed = parseSlotMinutes(time);
    if (parsed != null) return parsed.$1 >= (13 * 60 + 45);
    return slotIndex >= 6;
  }

  LessonSlot copyWith({String? subject, String? time, String? room}) => LessonSlot(
        subject: subject ?? this.subject,
        time: time ?? this.time,
        room: room ?? this.room,
      );

  Map<String, dynamic> toJson() => {'subject': subject, 'time': time, 'room': room};

  factory LessonSlot.fromJson(Map<String, dynamic> j, int idx) {
    final rawTime = '${j['time'] ?? ''}'.trim();
    return LessonSlot(
      subject: '${j['subject'] ?? ''}',
      time: rawTime.isNotEmpty ? rawTime : DaySchedule.defaultSlotTime(idx),
      room: '${j['room'] ?? ''}',
    );
  }
}

class DaySchedule {
  // Scansione oraria ufficiale della scuola:
  // 6 ore mattutine fino alle 13:45 + ore pomeridiane 14:30-15:30 e 15:30-16:30
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

  // Migrazione automatica di eventuali materie salvate nella versione precedente
  factory DaySchedule.migrateLegacy(Map<String, dynamic> legacy) {
    final m = (legacy['morning'] as List?) ?? const [];
    final a = (legacy['afternoon'] as List?) ?? const [];
    final migrated = List.generate(6, (i) {
      if (i < m.length && m[i] is Map<String, dynamic>) {
        final item = m[i] as Map<String, dynamic>;
        return LessonSlot(
          subject: '${item['subject'] ?? ''}',
          time: defaultSlotTime(i),
          room: '${item['room'] ?? ''}',
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
          room: '${item['room'] ?? ''}',
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
// STORAGE OFFLINE & NOTIFICHE (07:20 GIORNALIERA + PERSONALIZZATE PER EVENTO)
// ============================================================================

class StorageService {
  static const _kEvents = 'sv_events_v1';
  static const _kGrades = 'sv_grades_v1';
  static const _kTimetableV2 = 'sv_timetable_v2';
  static const _kTimetableLegacy = 'sv_timetable_v1';
  static const _kDeletedArgo = 'sv_deleted_argo_v1';
  static const _kDark = 'sv_dark_v1';
  static const _kNotify = 'sv_notify_v1';
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
    await _p.setString(_kStudent