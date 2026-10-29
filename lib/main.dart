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
  final reg = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*[-–/]\s*(\d{1,2})(?::(\d{2}))?');
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
// MODELLI DATI (EVENTI SENZA EMOJI NELLE CATEGORIE, PROMEMORIA CUSTOM, ORARIO LUN-VEN)
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

  int startMinutes(int fallbackHour) =>
      parseSlotMinutes(time)?.$1 ?? (fallbackHour * 60);

  int endMinutes(int fallbackHour) =>
      parseSlotMinutes(time)?.$2 ?? ((fallbackHour + 1) * 60);

  bool isAfter1300(bool inAfternoonList) {
    if (inAfternoonList) return true;
    final parsed = parseSlotMinutes(time);
    return parsed != null && parsed.$1 >= 13 * 60;
  }

  LessonSlot copyWith({String? subject, String? time, String? room}) => LessonSlot(
        subject: subject ?? this.subject,
        time: time ?? this.time,
        room: room ?? this.room,
      );

  Map<String, dynamic> toJson() => {'subject': subject, 'time': time, 'room': room};

  factory LessonSlot.fromJson(Map<String, dynamic> j) => LessonSlot(
        subject: '${j['subject'] ?? ''}',
        time: '${j['time'] ?? ''}',
        room: '${j['room'] ?? ''}',
      );
}

class DaySchedule {
  final List<LessonSlot> morning;
  final List<LessonSlot> afternoon;

  const DaySchedule({required this.morning, required this.afternoon});

  static String defaultMorningTime(int idx) =>
      '${(8 + idx).toString().padLeft(2, '0')}:00 - ${(9 + idx).toString().padLeft(2, '0')}:00';

  static String defaultAfternoonTime(int idx) =>
      '${(14 + idx).toString().padLeft(2, '0')}:00 - ${(15 + idx).toString().padLeft(2, '0')}:00';

  factory DaySchedule.initial() => DaySchedule(
        morning: List.generate(5, (i) => LessonSlot(time: defaultMorningTime(i))),
        afternoon: const [],
      );

  Map<String, dynamic> toJson() => {
        'morning': morning.map((e) => e.toJson()).toList(),
        'afternoon': afternoon.map((e) => e.toJson()).toList(),
      };

  factory DaySchedule.fromJson(Map<String, dynamic> j) {
    final m = (j['morning'] as List?)
        ?.map((x) => LessonSlot.fromJson(x as Map<String, dynamic>))
        .toList();
    final a = (j['afternoon'] as List?)
        ?.map((x) => LessonSlot.fromJson(x as Map<String, dynamic>))
        .toList();
    return DaySchedule(
      morning: m ?? DaySchedule.initial().morning,
      afternoon: a ?? const [],
    );
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
  static const _kTimetable = 'sv_timetable_v1';
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

  // Solo Lunedì (1) – Venerdì (5): Sabato rimosso
  Map<int, DaySchedule> loadTimetable() {
    final raw = _p.getString(_kTimetable);
    final out = {for (int d = 1; d <= 5; d++) d: DaySchedule.initial()};
    if (raw == null || raw.isEmpty) return out;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (int d = 1; d <= 5; d++) {
        final v = map['$d'];
        if (v is Map<String, dynamic>) out[d] = DaySchedule.fromJson(v);
      }
    } catch (_) {}
    return out;
  }

  Future<void> saveTimetable(Map<int, DaySchedule> map) => _p.setString(
        _kTimetable,
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
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {}
  }

  NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails(
          'calendario_scuola_channel',
          'Orario & Promemoria Scolastici',
          channelDescription: 'Notifica orario alle 07:20 e promemoria impegni personalizzati',
          importance: Importance.max,
          priority: Priority.high,
        ),
      );

  Future<void> sendTestNotification() async {
    if (!_ready) await init();
    await _plugin.show(
      999001,
      'Calendario Scuola · Notifiche attive',
      'Riceverai il promemoria dell\'orario ogni mattina alle 07:20 e gli avvisi dei tuoi impegni.',
      _details(),
    );
  }

  Future<void> syncNotifications(List<SchoolEvent> events, {required bool enabled}) async {
    if (!_ready) await init();
    try {
      await _plugin.cancelAll();
    } catch (_) {}
    if (!enabled) return;

    // 1) Notifica ricorrente ogni mattina alle 07:20 per controllare l'orario sull'app
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

    // 2) Notifiche personalizzate per ciascun evento
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
// INTEGRAZIONE REGISTRO ELETTRONICO ARGO (DidUP 1.30.2+ OAuth2 PKCE + CONSENSO)
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

  static String? _extractHtmlRedirectOrFormRedirect(String html, Uri baseUri) {
    final meta = RegExp(
      r'http-equiv=["\x27]?refresh["\x27]?[^>]*content=["\x27][^"\x27]*url=([^"\x27>\s;]+)',
      caseSensitive: false,
    ).firstMatch(html);
    if (meta != null) return meta.group(1);

    final jsLoc = RegExp(
      r'(?:window\.)?location(?:\.href)?\s*=\s*["\x27]([^"\x27]+)["\x27]',
      caseSensitive: false,
    ).firstMatch(html);
    if (jsLoc != null) {
      final candidate = jsLoc.group(1) ?? '';
      if (candidate.contains('oauth2') ||
          candidate.contains('consent') ||
          candidate.startsWith('it.argosoft.')) {
        return candidate;
      }
    }
    return null;
  }

  static (Uri, String)? _extractHtmlFormPost(String html, Uri currentUri) {
    final formMatch = RegExp(
      r'<form\b([^>]*)>([\s\S]*?)</form>',
      caseSensitive: false,
    ).firstMatch(html);
    if (formMatch == null) return null;

    final formAttrs = formMatch.group(1) ?? '';
    final formInner = formMatch.group(2) ?? '';
    final actionMatch =
        RegExp(r'action=["\x27]([^"\x27]*)["\x27]', caseSensitive: false).firstMatch(formAttrs);
    final rawAction = _unescapeHtml(actionMatch?.group(1) ?? '');
    final actionUri = rawAction.isEmpty ? currentUri : currentUri.resolve(rawAction);

    final fields = <String, List<String>>{};
    final inputReg = RegExp(r'<input\b([^>]*)/?>', caseSensitive: false);
    for (final m in inputReg.allMatches(formInner)) {
      final a = m.group(1) ?? '';
      final name = _attrVal(a, 'name');
      if (name == null || name.isEmpty) continue;
      final type = (_attrVal(a, 'type') ?? 'text').toLowerCase();
      final val = _unescapeHtml(_attrVal(a, 'value') ?? '');
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
        // Nei form OAuth di consenso le scope checkbox vanno accettate
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
      final val = _unescapeHtml(_attrVal(a, 'value') ?? '');
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

    if (fields.isEmpty && currentUri.queryParameters['consent_challenge'] != null) {
      fields['challenge'] = [currentUri.queryParameters['consent_challenge']!];
      fields['submit'] = ['accept'];
    }
    if (fields.isEmpty) return null;

    final encoded = <String>[
      for (final e in fields.entries)
        for (final v in e.value)
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(v)}',
    ].join('&');
    return (actionUri, encoded);
  }

  static String? _attrVal(String attrs, String attrName) {
    final m = RegExp(
      '$attrName\\s*=\\s*["\\x27]([^"\\x27]*)["\\x27]',
      caseSensitive: false,
    ).firstMatch(attrs);
    return m?.group(1);
  }

  static String _unescapeHtml(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&#38;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

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
      final loc1 = r1.location;
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

      for (int hop = 0; hop < 10; hop++) {
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
        String? loc = step.location;

        // Gestione avanzata pagina di consenso / redirect HTML su portaleargo.it
        if (loc == null) {
          loc = _extractHtmlRedirectOrFormRedirect(step.body, targetUri);
        }
        if (loc == null) {
          final formPost = _extractHtmlFormPost(step.body, targetUri);
          if (formPost != null) {
            final postRes = await passo(
              'POST',
              formPost.$1,
              formBody: formPost.$2,
              sendHostCookies: true,
            );
            currentBase = formPost.$1;
            loc = postRes.location ?? _extractHtmlRedirectOrFormRedirect(postRes.body, formPost.$1);
            step = postRes;
          } else {
            currentBase = targetUri;
          }
        } else {
          currentBase = targetUri;
        }

        // Fallback senza cookie se il nodo SSO non si aspettava cookie sullo step intermedio
        if (loc == null && targetUri.host.contains('portaleargo.it')) {
          final retryNoCookie = await passo('GET', targetUri, sendHostCookies: false);
          if (retryNoCookie.location != null) {
            currentBase = targetUri;
            loc = retryNoCookie.location;
          }
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

    // Solo promemoria/verifiche/interrogazioni (nessun compito)
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
        highPriority: cat.isHighPriorityDefault,
        reminderMode:
            cat.isHighPriorityDefault ? EventReminderMode.defaultBoth : EventReminderMode.dayBefore17,
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
          notes: 'Cap. 12-13 + formulario.',
          dateTime: d(2, 8),
          category: EventCategory.verifica,
          highPriority: true,
          fromArgo: true,
        ),
        SchoolEvent(
          id: 'demo_2',
          title: 'Interrogazione programmata su Leopardi e Romanticismo',
          subject: 'Italiano',
          notes: 'Canti + Operette Morali.',
          dateTime: d(4, 9),
          category: EventCategory.interrogazione,
          highPriority: true,
          fromArgo: true,
        ),
        SchoolEvent(
          id: 'demo_4',
          title: 'Verifica di laboratorio SQL (JOIN & GROUP BY)',
          subject: 'Informatica',
          dateTime: d(6, 11),
          category: EventCategory.verifica,
          highPriority: true,
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
// APP ROOT & HOME SHELL (4 SEZIONI: CALENDARIO, ORARIO, VOTI, ARGO)
// ============================================================================

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

class _HomeShellState extends State<HomeShell> {
  static const _chillEmptyQuotes = [
    'Agenda vuota, mente leggera.',
    'Zero scadenze in vista per questo giorno.',
    'Tutto tranquillo qui: nessun impegno segnato.',
    'Giornata libera da verifiche e interrogazioni.',
  ];

  // Solo Lunedì – Venerdì (Sabato rimosso)
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

  @override
  void initState() {
    super.initState();
    NotificationService.instance.syncNotifications(_events, enabled: _notifyOn);
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _saveEvents() async {
    _events.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    await widget.storage.saveEvents(_events);
    await NotificationService.instance.syncNotifications(_events, enabled: _notifyOn);
  }

  Future<void> _saveGrades() async {
    _grades.sort((a, b) => b.date.compareTo(a.date));
    await widget.storage.saveGrades(_grades);
  }

  Future<void> _saveTimetable() => widget.storage.saveTimetable(_timetable);

  List<String> get _knownSubjects {
    final s = <String>{
      for (final g in _grades)
        if (g.subject.trim().isNotEmpty) g.subject.trim(),
      for (final e in _events)
        if (e.subject.trim().isNotEmpty && e.subject != 'Promemoria') e.subject.trim(),
      for (final d in _timetable.values) ...[
        for (final m in d.morning)
          if (m.subject.trim().isNotEmpty) m.subject.trim(),
        for (final a in d.afternoon)
          if (a.subject.trim().isNotEmpty) a.subject.trim(),
      ],
      'Matematica',
      'Italiano',
      'Inglese',
      'Storia',
      'Fisica',
      'Scienze',
      'Informatica',
      'Filosofia',
      'Arte',
      'Scienze motorie',
    };
    return s.toList()..sort();
  }

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
  int get _highPrioTotal =>
      _events.where((e) => !e.completed && (e.highPriority || e.category.isHighPriorityDefault)).length;

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Sincronizzati ${mergedArgo.length} impegni e ${res.grades.length} voti.')),
        );
      }
    } catch (e) {
      final cleanErr = e.toString().replaceFirst('Exception: ', '');
      setState(() => _lastSyncError = cleanErr);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(cleanErr)));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.isDark;
    final card = d ? VibePalette.darkCard : VibePalette.lightCard;
    final border = d ? VibePalette.darkBorder : VibePalette.lightBorder;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(d, border),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _buildDashboardTab(d, card, border),
                  _buildTimetableTab(d, card, border),
                  _buildGradesTab(d, card, border),
                  _ArgoSettingsTab(
                    isDark: d,
                    cardColor: card,
                    borderColor: border,
                    creds: _argo,
                    syncing: _syncing,
                    lastError: _lastSyncError,
                    notifyOn: _notifyOn,
                    onSync: (s, u, p) => _runArgoSync(s, u, p),
                    onDemo: (s, u, p) => _runArgoSync(s, u, p, demo: true),
                    onToggleNotify: (v) async {
                      setState(() => _notifyOn = v);
                      await widget.storage.saveNotifyEnabled(v);
                      await NotificationService.instance.syncNotifications(_events, enabled: v);
                    },
                    onReset: () async {
                      await widget.storage.clearAll();
                      await NotificationService.instance.syncNotifications([], enabled: _notifyOn);
                      setState(() {
                        _events = [];
                        _grades = [];
                        _deletedArgoIds = {};
                        _argo = const ArgoCredentials();
                        _lastSyncError = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: (_tab == 0 || _tab == 2)
          ? Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient:
                    const LinearGradient(colors: [VibePalette.primary, VibePalette.primaryGlow]),
                boxShadow: [
                  BoxShadow(
                      color: alphaCol(VibePalette.primary, 0.45),
                      blurRadius: 18,
                      offset: const Offset(0, 6)),
                ],
              ),
              child: FloatingActionButton(
                elevation: 0,
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                onPressed: () =>
                    _tab == 0 ? _showEventModal(baseDate: _selectedDay) : _showAddGradeModal(),
                child: const Icon(CupertinoIcons.add, size: 28),
              ),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: card, border: Border(top: BorderSide(color: border))),
        child: NavigationBar(
          height: 66,
          backgroundColor: Colors.transparent,
          indicatorColor: alphaCol(VibePalette.primary, 0.2),
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(CupertinoIcons.calendar),
              selectedIcon: Icon(CupertinoIcons.calendar, color: VibePalette.primary),
              label: 'Calendario',
            ),
            NavigationDestination(
              icon: Icon(CupertinoIcons.clock),
              selectedIcon: Icon(CupertinoIcons.clock_fill, color: VibePalette.primary),
              label: 'Orario',
            ),
            NavigationDestination(
              icon: Icon(CupertinoIcons.chart_bar_square),
              selectedIcon: Icon(CupertinoIcons.chart_bar_square_fill, color: VibePalette.primary),
              label: 'Voti',
            ),
            NavigationDestination(
              icon: Icon(CupertinoIcons.cloud_download),
              selectedIcon: Icon(CupertinoIcons.cloud_download_fill, color: VibePalette.primary),
              label: 'Argo',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool d, Color border) {
    final txt = d ? Colors.white : const Color(0xFF0F172A);
    final muted = d ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: alphaCol(VibePalette.capBlue, 0.35)),
              boxShadow: [
                BoxShadow(
                    color: alphaCol(VibePalette.capBlue, 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: const Icon(Icons.school_rounded, color: VibePalette.capBlue, size: 27),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text('Calendario Scuola',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: txt)),
                    ),
                    if (_argo.lastSync != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: alphaCol(VibePalette.okGreen, 0.16),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Text('ARGO',
                            style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                color: VibePalette.okGreen)),
                      ),
                    ],
                  ],
                ),
                Text(
                  _argo.studentName.isNotEmpty
                      ? _argo.studentName
                      : 'verifiche, orario e registro',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: muted),
                ),
              ],
            ),
          ),
          _iconCircleBtn(_notifyOn ? CupertinoIcons.bell : CupertinoIcons.bell_slash, d, border,
              _showNotificationSheet),
          const SizedBox(width: 9),
          _iconCircleBtn(d ? CupertinoIcons.moon_stars : CupertinoIcons.sun_max, d, border,
              widget.onToggleTheme),
        ],
      ),
    );
  }

  Widget _iconCircleBtn(IconData icon, bool d, Color border, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: d ? VibePalette.darkCardAlt : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: border),
          ),
          child:
              Icon(icon, size: 19, color: d ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B)),
        ),
      );

  // --------------------------------------------------------------------------
  // TAB 1: CALENDARIO & SCADENZE (CATEGORIE SENZA EMOJI)
  // --------------------------------------------------------------------------

  Widget _buildDashboardTab(bool d, Color card, Color border) {
    final txt = d ? Colors.white : const Color(0xFF0F172A);
    final muted = d ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final rawMonth = DateFormat('MMMM yyyy', 'it_IT').format(_focusedDay);
    final monthTitle = rawMonth[0].toUpperCase() + rawMonth.substring(1);
    final rawDay = DateFormat('EEEE d MMMM', 'it_IT').format(_selectedDay);
    final dayTitle =
        rawDay.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
    final dayEvents = _eventsForDay(_selectedDay);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Row(
          children: [
            Expanded(
                child: _kpiBox(
                    CupertinoIcons.calendar_today,
                    const [Color(0xFF635BFF), Color(0xFF8B5CF6)],
                    _next7DaysCount,
                    'Prossimi 7 giorni',
                    card,
                    border,
                    txt,
                    muted)),
            const SizedBox(width: 10),
            Expanded(
                child: _kpiBox(
                    CupertinoIcons.checkmark_rectangle,
                    const [Color(0xFF00B894), Color(0xFF00CEC9)],
                    _todoTotal,
                    'Da fare in totale',
                    card,
                    border,
                    txt,
                    muted)),
            const SizedBox(width: 10),
            Expanded(
                child: _kpiBox(
                    CupertinoIcons.flame_fill,
                    const [Color(0xFFFF5E3A), Color(0xFFFF2A68)],
                    _highPrioTotal,
                    'Alta priorità',
                    card,
                    border,
                    txt,
                    muted)),
          ],
        ),
        const SizedBox(height: 15),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: cardDeco(card, border, 28),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _segBtn(!_isListView, CupertinoIcons.calendar, 'Calendario', muted,
                    () => setState(() => _isListView = false)),
                _segBtn(_isListView, CupertinoIcons.list_bullet, 'Lista', muted,
                    () => setState(() => _isListView = true)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _filterChip('Tutti', _catFilter == null, VibePalette.primary, d, card, border,
                () => setState(() => _catFilter = null)),
            for (final c in EventCategory.values)
              _filterChip(c.label, _catFilter == c, c.color, d, card, border,
                  () => setState(() => _catFilter = c)),
          ],
        ),
        const SizedBox(height: 16),
        if (!_isListView) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            decoration: cardDeco(card, border),
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(monthTitle,
                            style:
                                TextStyle(fontSize: 18.5, fontWeight: FontWeight.w800, color: txt))),
                    InkWell(
                      onTap: () => setState(() => _calFormat = _calFormat == CalendarFormat.month
                          ? CalendarFormat.week
                          : CalendarFormat.month),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                            color: alphaCol(VibePalette.primary, 0.14),
                            borderRadius: BorderRadius.circular(10)),
                        child: Text(_calFormat == CalendarFormat.month ? 'Mese' : 'Sett.',
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: VibePalette.primary)),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _focusedDay = DateTime.now();
                        _selectedDay = DateTime.now();
                      }),
                      child: const Text('Oggi',
                          style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF818CF8))),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(CupertinoIcons.chevron_left, size: 17, color: muted),
                      onPressed: () => setState(
                          () => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1, 1)),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(CupertinoIcons.chevron_right, size: 17, color: muted),
                      onPressed: () => setState(
                          () => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 1)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
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
                  onDaySelected: (sel, foc) => setState(() {
                    _selectedDay = sel;
                    _focusedDay = foc;
                    _emptyIdx = (_emptyIdx + 1) % _chillEmptyQuotes.length;
                  }),
                  onPageChanged: (foc) => setState(() => _focusedDay = foc),
                  daysOfWeekHeight: 28,
                  rowHeight: 48,
                  daysOfWeekStyle: DaysOfWeekStyle(
                    dowTextFormatter: (dt, loc) =>
                        DateFormat.E(loc).format(dt).replaceAll('.', '').toUpperCase(),
                    weekdayStyle:
                        TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: muted),
                    weekendStyle:
                        TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: muted),
                  ),
                  calendarStyle: CalendarStyle(
                    defaultTextStyle: TextStyle(fontWeight: FontWeight.w700, color: txt),
                    weekendTextStyle: TextStyle(fontWeight: FontWeight.w700, color: txt),
                    outsideTextStyle: TextStyle(color: alphaCol(muted, 0.36)),
                    todayDecoration: BoxDecoration(
                      color: alphaCol(VibePalette.primary, 0.2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: VibePalette.primary, width: 1.4),
                    ),
                    todayTextStyle: TextStyle(fontWeight: FontWeight.w800, color: txt),
                    selectedDecoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [VibePalette.primary, VibePalette.primaryGlow]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color: alphaCol(VibePalette.primary, 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    selectedTextStyle:
                        const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  calendarBuilders: CalendarBuilders(
                    markerBuilder: (_, __, evs) => evs.isEmpty
                        ? const SizedBox.shrink()
                        : Positioned(
                            bottom: 4,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: evs
                                  .take(4)
                                  .map((e) => Container(
                                        width: 6,
                                        height: 6,
                                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                        decoration: BoxDecoration(
                                            color: e.category.color, shape: BoxShape.circle),
                                      ))
                                  .toList(),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Divider(color: border, height: 1),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  children: EventCategory.values
                      .map((c) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                  width: 9,
                                  height: 9,
                                  decoration:
                                      BoxDecoration(color: c.color, shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Text(c.label,
                                  style: TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w600, color: muted)),
                            ],
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: cardDeco(card, border),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(dayTitle,
                            style:
                                TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800, color: txt))),
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _showEventModal(baseDate: _selectedDay),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                        decoration: BoxDecoration(
                          color: alphaCol(VibePalette.primary, 0.16),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: alphaCol(VibePalette.primary, 0.4)),
                        ),
                        child: const Text('+ Aggiungi',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF818CF8))),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (dayEvents.isEmpty)
                  CustomPaint(
                    painter: _DashedRRectPainter(color: border, radius: 20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18),
                      decoration: BoxDecoration(
                        color:
                            d ? alphaCol(VibePalette.darkCardAlt, 0.45) : VibePalette.lightCardAlt,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          Icon(CupertinoIcons.calendar_badge_minus, size: 32, color: muted),
                          const SizedBox(height: 10),
                          Text(_chillEmptyQuotes[_emptyIdx],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600, color: muted)),
                        ],
                      ),
                    ),
                  )
                else
                  ...dayEvents.map((e) => _eventCardTile(e, d, border, txt, muted)),
              ],
            ),
          ),
        ] else
          _buildListWithCountdown(d, card, border, txt, muted),
      ],
    );
  }

  Widget _kpiBox(IconData icon, List<Color> grad, int val, String label, Color card, Color border,
          Color txt, Color muted) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: cardDeco(card, border, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12), gradient: LinearGradient(colors: grad)),
              child: Icon(icon, color: Colors.white, size: 19),
            ),
            const SizedBox(height: 12),
            Text('$val', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: txt)),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: muted)),
          ],
        ),
      );

  Widget _segBtn(bool active, IconData icon, String label, Color muted, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: active
                ? const LinearGradient(colors: [VibePalette.primary, VibePalette.primaryGlow])
                : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: 15, color: active ? Colors.white : muted),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: active ? Colors.white : muted)),
            ],
          ),
        ),
      );

  Widget _filterChip(String text, bool sel, Color accent, bool d, Color card, Color border,
          VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: sel ? alphaCol(accent, 0.2) : card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: sel ? accent : border, width: sel ? 1.4 : 1.0),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
              color: sel
                  ? (d ? Colors.white : accent)
                  : (d ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
            ),
          ),
        ),
      );

  Widget _buildListWithCountdown(bool d, Color card, Color border, Color txt, Color muted) {
    final list = _upcomingFiltered;
    final nextEv = list.where((e) => !e.completed).firstOrNull;
    final diff = nextEv?.dateTime.difference(DateTime.now()) ?? Duration.zero;

    return Column(
      children: [
        if (nextEv != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(colors: [nextEv.category.color, VibePalette.primary]),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CONTO ALLA ROVESCIA · ${nextEv.category.label.toUpperCase()}',
                  style:
                      const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white70),
                ),
                const SizedBox(height: 6),
                Text('${nextEv.subject} — ${nextEv.title}',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _cdBox('${max(0, diff.inDays)}', 'GIORNI'),
                    const SizedBox(width: 8),
                    _cdBox('${max(0, diff.inHours % 24)}', 'ORE'),
                    const SizedBox(width: 8),
                    _cdBox('${max(0, diff.inMinutes % 60)}', 'MIN'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: cardDeco(card, border),
          child: list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 26),
                  child: Text('Nessuna verifica o interrogazione in programma.',
                      textAlign: TextAlign.center, style: TextStyle(color: muted)),
                )
              : Column(children: list.map((e) => _eventCardTile(e, d, border, txt, muted)).toList()),
        ),
      ],
    );
  }

  Widget _cdBox(String val, String unit) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
            color: alphaCol(Colors.black, 0.24), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text(val,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
            Text(unit,
                style: const TextStyle(
                    fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white70)),
          ],
        ),
      );

  String _countdownText(DateTime dt) {
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return isSameDay(dt, DateTime.now()) ? 'Oggi' : 'Passato';
    if (diff.inDays >= 1) return 'Tra ${diff.inDays}g ${diff.inHours % 24}h';
    if (diff.inHours >= 1) return 'Tra ${diff.inHours}h ${diff.inMinutes % 60}m';
    return 'Tra ${max(1, diff.inMinutes)}m';
  }

  Widget _eventCardTile(SchoolEvent ev, bool d, Color border, Color txt, Color muted) {
    final c = ev.category.color;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _showEventModal(existing: ev),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: d ? VibePalette.darkCardAlt : VibePalette.lightCardAlt,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ev.completed ? border : alphaCol(c, 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () async {
                final i = _events.indexWhere((x) => x.id == ev.id);
                if (i != -1) {
                  setState(() => _events[i] = _events[i].copyWith(completed: !ev.completed));
                  await _saveEvents();
                }
              },
              child: Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ev.completed ? VibePalette.okGreen : alphaCol(c, 0.15),
                  border: Border.all(color: ev.completed ? VibePalette.okGreen : c, width: 2),
                ),
                child:
                    ev.completed ? const Icon(Icons.check, size: 15, color: Colors.white) : null,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: alphaCol(c, 0.18), borderRadius: BorderRadius.circular(7)),
                        child: Text(ev.category.label,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: alphaCol(VibePalette.primary, 0.16),
                            borderRadius: BorderRadius.circular(7)),
                        child: Text(ev.subject,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF818CF8))),
                      ),
                      if (!ev.completed)
                        Text(_countdownText(ev.dateTime),
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: txt)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ev.title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: ev.completed ? muted : txt,
                      decoration: ev.completed ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (ev.notes.isNotEmpty)
                    Text(ev.notes, style: TextStyle(fontSize: 12, color: muted)),
                  const SizedBox(height: 4),
                  Text(
                    '${DateFormat('EEE d MMM · HH:mm', 'it_IT').format(ev.dateTime)}'
                    ' · ${ev.reminderSummary()}'
                    '${ev.fromArgo ? (ev.editedByUser ? ' · Argo (modificato)' : ' · Argo') : ''}',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Modifica',
              icon: const Icon(CupertinoIcons.pencil, size: 18, color: Color(0xFF818CF8)),
              onPressed: () => _showEventModal(existing: ev),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Elimina',
              icon: Icon(CupertinoIcons.trash, size: 17, color: muted),
              onPressed: () => _deleteEvent(ev),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 2: ORARIO SCOLASTICO (LUN-VEN, MULTI-SLOT, SPAZIO 36PX DOPO LE 13:00)
  // --------------------------------------------------------------------------

  Widget _buildTimetableTab(bool d, Color card, Color border) {
    final txt = d ? Colors.white : const Color(0xFF0F172A);
    final muted = d ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final sched = _timetable[_ttDay] ?? DaySchedule.initial();
    final todayWd = DateTime.now().weekday;
    final totalHours = sched.morning.length + sched.afternoon.length;

    // Lista unificata degli slot della giornata con stacco leggero (36 px) dopo le 13:00
    final dayRows = <Widget>[];
    bool gapAddedAfter13 = false;
    bool hasAnySlotBefore13 = false;

    for (int i = 0; i < sched.morning.length; i++) {
      final slot = sched.morning[i];
      final post13 = slot.isAfter1300(false);
      if (post13 && hasAnySlotBefore13 && !gapAddedAfter13) {
        dayRows.add(const SizedBox(height: 28)); // +8px margine inferiore = 36px totali (30-40px)
        gapAddedAfter13 = true;
      }
      if (!post13) hasAnySlotBefore13 = true;
      dayRows.add(_lessonRow(
        indexLabel: '${i + 1}ª',
        slot: slot,
        isAfternoon: false,
        d: d,
        border: border,
        txt: txt,
        muted: muted,
        onTap: () => _editLessonSlotModal(_ttDay, false, i),
      ));
    }

    for (int i = 0; i < sched.afternoon.length; i++) {
      if ((hasAnySlotBefore13 || sched.morning.isNotEmpty) && !gapAddedAfter13) {
        dayRows.add(const SizedBox(height: 28)); // +8px margine inferiore = 36px totali (30-40px)
        gapAddedAfter13 = true;
      }
      final slot = sched.afternoon[i];
      dayRows.add(_lessonRow(
        indexLabel: '${sched.morning.length + i + 1}ª',
        slot: slot,
        isAfternoon: true,
        d: d,
        border: border,
        txt: txt,
        muted: muted,
        onTap: () => _editLessonSlotModal(_ttDay, true, i),
        onRemove: () async {
          final next = [...sched.afternoon]..removeAt(i);
          setState(
              () => _timetable[_ttDay] = DaySchedule(morning: sched.morning, afternoon: next));
          await _saveTimetable();
        },
      ));
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Orario Scolastico',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: txt)),
            ),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: cardDeco(card, border, 22),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _segBtn(!_ttWeekOverview, CupertinoIcons.calendar_today, 'Giorno', muted,
                      () => setState(() => _ttWeekOverview = false)),
                  _segBtn(_ttWeekOverview, CupertinoIcons.square_grid_2x2, 'Settimana', muted,
                      () => setState(() => _ttWeekOverview = true)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_ttWeekOverview)
          _buildWeekOverview(d, card, border, txt, muted)
        else ...[
          Row(
            children: [
              for (int wd = 1; wd <= 5; wd++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: wd < 5 ? 8 : 0),
                    child: GestureDetector(
                      onTap: () => setState(() => _ttDay = wd),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          gradient: _ttDay == wd
                              ? const LinearGradient(
                                  colors: [VibePalette.primary, VibePalette.primaryGlow])
                              : null,
                          color: _ttDay == wd ? null : card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: _ttDay == wd
                                  ? VibePalette.primary
                                  : (todayWd == wd ? VibePalette.capBlue : border)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _dayShort[wd]!,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: _ttDay == wd ? Colors.white : txt,
                              ),
                            ),
                            if ((_timetable[wd]?.afternoon.isNotEmpty ?? false))
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '+${_timetable[wd]!.afternoon.length}',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: _ttDay == wd
                                        ? Colors.white70
                                        : VibePalette.interrogazioneAmber,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // UNICA CARD GIORNALIERA CONTINUA (SENZA DIVISIONE NETTA MATTINA / POMERIGGIO)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: cardDeco(card, border),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_dayNames[_ttDay]} ($totalHours ore)',
                        style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: txt),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Togli ora entro le 13:00',
                      onPressed: sched.morning.isEmpty
                          ? null
                          : () async {
                              final next = [...sched.morning]..removeLast();
                              setState(() => _timetable[_ttDay] =
                                  DaySchedule(morning: next, afternoon: sched.afternoon));
                              await _saveTimetable();
                            },
                      icon: Icon(CupertinoIcons.minus_circle, color: muted, size: 21),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Aggiungi ora mattina',
                      onPressed: sched.morning.length >= 7
                          ? null
                          : () async {
                              final next = [
                                ...sched.morning,
                                LessonSlot(time: DaySchedule.defaultMorningTime(sched.morning.length)),
                              ];
                              setState(() => _timetable[_ttDay] =
                                  DaySchedule(morning: next, afternoon: sched.afternoon));
                              await _saveTimetable();
                            },
                      icon: const Icon(CupertinoIcons.plus_circle_fill,
                          color: VibePalette.primary, size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (dayRows.isEmpty)
                  Text('Nessuna ora impostata. Premi + per aggiungere ore.',
                      style: TextStyle(fontSize: 13, color: muted))
                else
                  ...dayRows,
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () async {
                          final newIdx = sched.afternoon.length;
                          final next = [
                            ...sched.afternoon,
                            LessonSlot(time: DaySchedule.defaultAfternoonTime(newIdx)),
                          ];
                          setState(() => _timetable[_ttDay] =
                              DaySchedule(morning: sched.morning, afternoon: next));
                          await _saveTimetable();
                          if (mounted) _editLessonSlotModal(_ttDay, true, newIdx);
                        },
                        icon: const Icon(CupertinoIcons.plus_circle_fill, size: 17),
                        label: const Text('Ora dopo le 13:00'),
                      ),
                    ),
                    if (sched.afternoon.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final next = [...sched.afternoon]..removeLast();
                          setState(() => _timetable[_ttDay] =
                              DaySchedule(morning: sched.morning, afternoon: next));
                          await _saveTimetable();
                        },
                        icon: const Icon(CupertinoIcons.minus_circle,
                            size: 16, color: VibePalette.verificaRed),
                        label: const Text('Togli',
                            style: TextStyle(color: VibePalette.verificaRed)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _lessonRow({
    required String indexLabel,
    required LessonSlot slot,
    required bool isAfternoon,
    required bool d,
    required Color border,
    required Color txt,
    required Color muted,
    required VoidCallback onTap,
    VoidCallback? onRemove,
  }) {
    final hasSubj = slot.subject.trim().isNotEmpty;
    final col = hasSubj
        ? subjectAccent(slot.subject)
        : (isAfternoon ? VibePalette.interrogazioneAmber : muted);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: d ? VibePalette.darkCardAlt : VibePalette.lightCardAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: hasSubj ? alphaCol(col, 0.45) : border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: alphaCol(col, 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(indexLabel,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: col)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasSubj ? slot.subject : 'Tocca per inserire materia',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: hasSubj ? FontWeight.w800 : FontWeight.w500,
                        fontStyle: hasSubj ? FontStyle.normal : FontStyle.italic,
                        color: hasSubj ? txt : muted,
                      ),
                    ),
                    if (slot.time.isNotEmpty || slot.room.isNotEmpty)
                      Text(
                        [if (slot.time.isNotEmpty) slot.time, if (slot.room.isNotEmpty) slot.room]
                            .join('  ·  '),
                        style: TextStyle(fontSize: 11.5, color: muted),
                      ),
                  ],
                ),
              ),
              const Icon(CupertinoIcons.pencil, size: 17, color: Color(0xFF818CF8)),
              if (onRemove != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Rimuovi ora',
                  onPressed: onRemove,
                  icon: const Icon(CupertinoIcons.minus_circle_fill,
                      size: 19, color: VibePalette.verificaRed),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeekOverview(bool d, Color card, Color border, Color txt, Color muted) {
    return Column(
      children: [
        for (int wd = 1; wd <= 5; wd++)
          Builder(builder: (_) {
            final s = _timetable[wd] ?? DaySchedule.initial();
            final all = [...s.morning, ...s.afternoon];
            final filled = all.where((x) => x.subject.trim().isNotEmpty).toList();
            return GestureDetector(
              onTap: () => setState(() {
                _ttDay = wd;
                _ttWeekOverview = false;
              }),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: cardDeco(card, border, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(_dayNames[wd]!,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: txt)),
                        ),
                        const Text('Modifica ›',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: VibePalette.capBlue)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (filled.isEmpty)
                      Text('Nessuna materia inserita', style: TextStyle(fontSize: 12.5, color: muted))
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (int i = 0; i < all.length; i++)
                            if (all[i].subject.trim().isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: alphaCol(subjectAccent(all[i].subject), 0.16),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Text(
                                  '${i + 1}ª ${all[i].subject}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: subjectAccent(all[i].subject),
                                  ),
                                ),
                              ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  void _editLessonSlotModal(int weekday, bool isAfternoon, int idx) {
    final sched = _timetable[weekday] ?? DaySchedule.initial();
    final list = isAfternoon ? sched.afternoon : sched.morning;
    if (idx < 0 || idx >= list.length) return;

    final current = list[idx];
    final fallbackStartH = isAfternoon ? (14 + idx) : (8 + idx);
    int startMin = current.startMinutes(fallbackStartH);
    int endMin = current.endMinutes(fallbackStartH);

    // Rileva se questa materia occupa già più slot consecutivi a partire da idx
    int initialSpan = 1;
    if (current.subject.trim().isNotEmpty) {
      while (idx + initialSpan < list.length &&
          list[idx + initialSpan].subject.trim().toLowerCase() ==
              current.subject.trim().toLowerCase()) {
        final nextEnd = list[idx + initialSpan].endMinutes(fallbackStartH + initialSpan);
        if (nextEnd > endMin) endMin = nextEnd;
        initialSpan++;
      }
    }
    if (endMin <= startMin) endMin = startMin + 60;

    final subjCtrl = TextEditingController(text: current.subject);
    final roomCtrl = TextEditingController(text: current.room);
    final suggestions = _knownSubjects;

    int calcSpan(int sMin, int eMin) {
      if (eMin <= sMin) return 1;
      return ((eMin - sMin) / 55.0).round().clamp(1, 6);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.isDark ? VibePalette.darkCard : VibePalette.lightCard,
      shape:
          const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) {
          final span = calcSpan(startMin, endMin);
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 22),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_dayNames[weekday]} · ${isAfternoon ? "${sched.morning.length + idx + 1}ª ora" : "${idx + 1}ª ora"}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: subjCtrl,
                    decoration: fieldDeco('Materia (es. Matematica)', icon: CupertinoIcons.book),
                  ),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: suggestions.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (_, i) {
                          final s = suggestions[i];
                          return ActionChip(
                            label: Text(s, style: const TextStyle(fontSize: 12)),
                            onPressed: () => setM(() => subjCtrl.text = s),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(CupertinoIcons.clock, size: 16),
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
                                if (endMin <= startMin) endMin = startMin + 60;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(CupertinoIcons.clock_fill, size: 16),
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
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [1, 2, 3].map((h) {
                      final active = span == h;
                      return ChoiceChip(
                        label: Text(h == 1 ? '1 ora (1 slot)' : '$h ore ($h slot)'),
                        selected: active,
                        onSelected: (_) => setM(() => endMin = startMin + h * 60),
                      );
                    }).toList(),
                  ),
                  if (span > 1) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Occuperà automaticamente $span slot consecutivi (${fmtMin(startMin)} - ${fmtMin(endMin)}).',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF818CF8),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: roomCtrl,
                    decoration: fieldDeco('Aula / Laboratorio (opzionale)',
                        icon: CupertinoIcons.location),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          if (isAfternoon) {
                            final next = [...sched.afternoon]..removeAt(idx);
                            setState(() => _timetable[weekday] =
                                DaySchedule(morning: sched.morning, afternoon: next));
                          } else {
                            final next = [...sched.morning];
                            next[idx] = LessonSlot(time: DaySchedule.defaultMorningTime(idx));
                            setState(() => _timetable[weekday] =
                                DaySchedule(morning: next, afternoon: sched.afternoon));
                          }
                          await _saveTimetable();
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        icon: Icon(
                          isAfternoon ? CupertinoIcons.trash : CupertinoIcons.clear_circled,
                          size: 16,
                          color: VibePalette.verificaRed,
                        ),
                        label: Text(
                          isAfternoon ? 'Rimuovi' : 'Svuota',
                          style: const TextStyle(color: VibePalette.verificaRed),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            final subj = subjCtrl.text.trim();
                            final room = roomCtrl.text.trim();
                            final work = [...list];

                            // Se l'utente ha scelto un orario d'inizio corrispondente a un altro slot esistente, parte da quello
                            int startIdx = idx;
                            for (int i = 0; i < work.length; i++) {
                              final fb = isAfternoon ? (14 + i) : (8 + i);
                              if (work[i].startMinutes(fb) == startMin) {
                                startIdx = i;
                                break;
                              }
                            }

                            final stepMin = max(30, (endMin - startMin) ~/ span);
                            for (int k = 0; k < span; k++) {
                              final sM = startMin + k * stepMin;
                              final eM = (k == span - 1) ? endMin : (startMin + (k + 1) * stepMin);
                              final sliceTime = '${fmtMin(sM)} - ${fmtMin(eM)}';
                              final target = startIdx + k;
                              final slotVal = LessonSlot(
                                subject: subj,
                                time: sliceTime,
                                room: room,
                              );
                              if (target < work.length) {
                                work[target] = slotVal;
                              } else {
                                work.add(slotVal);
                              }
                            }

                            // Se prima occupava più slot e ora è stato ridotto (es. da 2 a 1 ora), libera lo slot in eccesso
                            if (startIdx == idx && span < initialSpan) {
                              for (int k = span; k < initialSpan && (idx + k) < work.length; k++) {
                                final fb = isAfternoon ? (14 + idx + k) : (8 + idx + k);
                                work[idx + k] =
                                    LessonSlot(time: '${fmtMin(fb * 60)} - ${fmtMin((fb + 1) * 60)}');
                              }
                            }

                            setState(() {
                              _timetable[weekday] = isAfternoon
                                  ? DaySchedule(morning: sched.morning, afternoon: work)
                                  : DaySchedule(morning: work, afternoon: sched.afternoon);
                            });
                            await _saveTimetable();
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          child: Text(span > 1 ? 'Salva ($span slot)' : 'Salva Ora'),
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
  // TAB 3: VOTI & MEDIE (PONDERATA / ARITMETICA)
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

  Widget _buildGradesTab(bool d, Color card, Color border) {
    final txt = d ? Colors.white : const Color(0xFF0F172A);
    final muted = d ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final grouped = <String, List<SchoolGrade>>{};
    for (final g in _grades) {
      grouped.putIfAbsent(g.subject, () => []).add(g);
    }
    final subjects = grouped.keys.toList()..sort();
    final totalAvg = _avg(_grades);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: cardDeco(card, border),
          child: Row(
            children: [
              SizedBox(
                width: 82,
                height: 82,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 78,
                      height: 78,
                      child: CircularProgressIndicator(
                        value: (_grades.isEmpty ? 0.0 : totalAvg / 10.0).clamp(0.0, 1.0),
                        strokeWidth: 8,
                        backgroundColor: alphaCol(muted, 0.18),
                        valueColor: AlwaysStoppedAnimation(
                            _grades.isEmpty ? VibePalette.primary : _gradeCol(totalAvg)),
                      ),
                    ),
                    Text(_grades.isEmpty ? '--' : totalAvg.toStringAsFixed(2),
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: txt)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_weightedAvg ? 'Media Generale Ponderata' : 'Media Generale Aritmetica',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: txt)),
                    const SizedBox(height: 4),
                    Text('${_grades.length} voti in ${subjects.length} materie',
                        style: TextStyle(fontSize: 12.5, color: muted)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                            label: const Text('Ponderata'),
                            selected: _weightedAvg,
                            onSelected: (_) => setState(() => _weightedAvg = true)),
                        ChoiceChip(
                            label: const Text('Aritmetica'),
                            selected: !_weightedAvg,
                            onSelected: (_) => setState(() => _weightedAvg = false)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (subjects.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: cardDeco(card, border),
            child: Column(
              children: [
                Icon(CupertinoIcons.chart_bar_alt_fill, size: 38, color: muted),
                const SizedBox(height: 10),
                Text('Nessun voto presente',
                    style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: txt)),
                const SizedBox(height: 6),
                Text('Sincronizza Argo nella scheda "Argo" o premi + per inserire un voto.',
                    textAlign: TextAlign.center, style: TextStyle(color: muted)),
              ],
            ),
          )
        else
          ...subjects.map((s) {
            final list = grouped[s]!;
            final m = _avg(list);
            final col = _gradeCol(m);
            final target = m < 6.0 ? 6.0 : 8.0;
            final needed = target * (list.length + 1) - list.fold<double>(0, (a, b) => a + b.value);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: cardDeco(card, border, 20),
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                leading: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: alphaCol(col, 0.16), borderRadius: BorderRadius.circular(13)),
                  child: Text(m.toStringAsFixed(1),
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: col)),
                ),
                title: Text(s, style: TextStyle(fontWeight: FontWeight.w800, color: txt)),
                subtitle: Text(
                  needed > 0 && needed <= 10
                      ? '${list.length} voti · Per il ${target.toInt()} serve ${needed.toStringAsFixed(1)}'
                      : '${list.length} voti · Media solida',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                children: list.map((g) {
                  final gc = _gradeCol(g.value);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: alphaCol(gc, 0.18),
                      child: Text(g.value.toStringAsFixed(1),
                          style: TextStyle(fontWeight: FontWeight.w800, color: gc, fontSize: 13)),
                    ),
                    title: Text(g.description.isEmpty ? 'Prova ${g.type}' : g.description,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: txt)),
                    subtitle: Text(
                      '${g.type} · Peso ${(g.weight * 100).round()}% · ${DateFormat('dd/MM/yyyy').format(g.date)}${g.fromArgo ? ' · ARGO' : ''}',
                      style: TextStyle(fontSize: 11.5, color: muted),
                    ),
                    trailing: IconButton(
                      icon: Icon(CupertinoIcons.trash, size: 17, color: muted),
                      onPressed: () async {
                        setState(() => _grades.removeWhere((x) => x.id == g.id));
                        await _saveGrades();
                      },
                    ),
                  );
                }).toList(),
              ),
            );
          }),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // MODALI NOTIFICHE, CREA / MODIFICA EVENTO (CON PROMEMORIA CUSTOM) E NUOVO VOTO
  // --------------------------------------------------------------------------

  void _showNotificationSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: widget.isDark ? VibePalette.darkCard : VibePalette.lightCard,
      shape:
          const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notifiche & Orario Mattutino',
                style: TextStyle(fontSize: 18.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text(
              'Ogni mattina alle 07:20 ricevi una notifica per controllare l\'orario del giorno sull\'app. '
              'Inoltre ogni singolo impegno ha il proprio orario di notifica personalizzabile.',
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await NotificationService.instance.sendTestNotification();
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                icon: const Icon(CupertinoIcons.bell_fill, size: 18),
                label: const Text('Invia Notifica di Prova'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEventModal({DateTime? baseDate, SchoolEvent? existing}) {
    final isEdit = existing != null;
    final subjCtrl = TextEditingController(text: existing?.subject ?? 'Matematica');
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    var cat = existing?.category ?? EventCategory.verifica;
    final startDay = baseDate ?? DateTime.now();
    var dt = existing?.dateTime ?? DateTime(startDay.year, startDay.month, startDay.day, 8, 15);
    var prio = existing?.highPriority ?? true;
    var remMode = existing?.reminderMode ?? EventReminderMode.defaultBoth;
    DateTime customRem = existing?.customReminderAt ??
        DateTime(dt.year, dt.month, dt.day, 17, 0).subtract(const Duration(days: 1));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.isDark ? VibePalette.darkCard : VibePalette.lightCard,
      shape:
          const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit ? 'Modifica Impegno' : 'Nuovo Impegno',
                  style: const TextStyle(fontSize: 18.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: EventCategory.values
                      .map((c) => ChoiceChip(
                            label: Text(c.label),
                            selected: cat == c,
                            onSelected: (_) => setM(() {
                              cat = c;
                              prio = c.isHighPriorityDefault;
                            }),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 10),
                TextField(controller: subjCtrl, decoration: fieldDeco('Materia')),
                const SizedBox(height: 10),
                TextField(controller: titleCtrl, decoration: fieldDeco('Argomento / Titolo')),
                const SizedBox(height: 10),
                TextField(controller: notesCtrl, decoration: fieldDeco('Note (opzionale)')),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(CupertinoIcons.calendar, size: 16),
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
                        icon: const Icon(CupertinoIcons.clock, size: 16),
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
                const SizedBox(height: 12),

                // SEZIONE PERSONALIZZAZIONE NOTIFICA PER QUESTO EVENTO
                DropdownButtonFormField<EventReminderMode>(
                  value: remMode,
                  isExpanded: true,
                  decoration: fieldDeco(
                    'Quando ricevere la notifica',
                    icon: CupertinoIcons.bell,
                  ),
                  items: EventReminderMode.values
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text(m.label, overflow: TextOverflow.ellipsis),
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
                          icon: const Icon(CupertinoIcons.bell_circle, size: 16),
                          label: Text('Giorno: ${DateFormat('dd/MM/yyyy').format(customRem)}'),
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
                          icon: const Icon(CupertinoIcons.time, size: 16),
                          label: Text('Ora: ${DateFormat('HH:mm').format(customRem)}'),
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: ctx,
                              initialTime: TimeOfDay.fromDateTime(customRem),
                            );
                            if (t != null) {
                              setM(() => customRem = DateTime(
                                  customRem.year, customRem.month, customRem.day, t.hour, t.minute));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Segna come alta priorità'),
                  value: prio,
                  onChanged: (v) => setM(() => prio = v),
                ),
                Row(
                  children: [
                    if (isEdit) ...[
                      OutlinedButton.icon(
                        onPressed: () async {
                          await _deleteEvent(existing);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        icon: const Icon(CupertinoIcons.trash,
                            size: 16, color: VibePalette.verificaRed),
                        label:
                            const Text('Elimina', style: TextStyle(color: VibePalette.verificaRed)),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          final s =
                              subjCtrl.text.trim().isEmpty ? 'Materia' : subjCtrl.text.trim();
                          final t = titleCtrl.text.trim().isEmpty
                              ? '${cat.label} di $s'
                              : titleCtrl.text.trim();
                          setState(() {
                            if (isEdit) {
                              final idx = _events.indexWhere((x) => x.id == existing.id);
                              if (idx != -1) {
                                _events[idx] = existing.copyWith(
                                  title: t,
                                  subject: s,
                                  notes: notesCtrl.text.trim(),
                                  dateTime: dt,
                                  category: cat,
                                  highPriority: prio,
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
                                subject: s,
                                notes: notesCtrl.text.trim(),
                                dateTime: dt,
                                category: cat,
                                highPriority: prio,
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
                        child: Text(isEdit ? 'Salva Modifiche' : 'Salva Impegno'),
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
    final subjCtrl = TextEditingController(text: 'Matematica');
    final descCtrl = TextEditingController();
    double val = 7.0;
    double weight = 1.0;
    String type = 'Scritto';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.isDark ? VibePalette.darkCard : VibePalette.lightCard,
      shape:
          const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nuovo Voto',
                    style: TextStyle(fontSize: 18.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                TextField(controller: subjCtrl, decoration: fieldDeco('Materia')),
                const SizedBox(height: 10),
                Text('Voto: ${val.toStringAsFixed(2)}  ·  Peso: ${(weight * 100).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                Slider(
                    value: val,
                    min: 1,
                    max: 10,
                    divisions: 36,
                    onChanged: (v) => setM(() => val = v)),
                Slider(
                    value: weight,
                    min: 0.25,
                    max: 1.0,
                    divisions: 3,
                    onChanged: (v) => setM(() => weight = v)),
                Wrap(
                  spacing: 8,
                  children: ['Scritto', 'Orale', 'Pratico']
                      .map((t) => ChoiceChip(
                          label: Text(t), selected: type == t, onSelected: (_) => setM(() => type = t)))
                      .toList(),
                ),
                const SizedBox(height: 10),
                TextField(controller: descCtrl, decoration: fieldDeco('Argomento (opzionale)')),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      setState(() {
                        _grades.add(SchoolGrade(
                          id: 'g_${DateTime.now().millisecondsSinceEpoch}',
                          subject:
                              subjCtrl.text.trim().isEmpty ? 'Materia' : subjCtrl.text.trim(),
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
                    child: const Text('Registra Voto'),
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
// TAB 4: LOGIN REGISTRO ARGO & IMPOSTAZIONI
// ============================================================================

class _ArgoSettingsTab extends StatefulWidget {
  final bool isDark;
  final Color cardColor, borderColor;
  final ArgoCredentials creds;
  final bool syncing, notifyOn;
  final String? lastError;
  final Future<void> Function(String s, String u, String p) onSync;
  final Future<void> Function(String s, String u, String p) onDemo;
  final ValueChanged<bool> onToggleNotify;
  final VoidCallback onReset;

  const _ArgoSettingsTab({
    required this.isDark,
    required this.cardColor,
    required this.borderColor,
    required this.creds,
    required this.syncing,
    required this.lastError,
    required this.notifyOn,
    required this.onSync,
    required this.onDemo,
    required this.onToggleNotify,
    required this.onReset,
  });

  @override
  State<_ArgoSettingsTab> createState() => _ArgoSettingsTabState();
}

class _ArgoSettingsTabState extends State<_ArgoSettingsTab> {
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

  @override
  Widget build(BuildContext context) {
    final txt = widget.isDark ? Colors.white : const Color(0xFF0F172A);
    final muted = widget.isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: cardDeco(widget.cardColor, widget.borderColor),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Login Registro Elettronico Argo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: txt)),
              const SizedBox(height: 4),
              Text(
                widget.creds.lastSync != null
                    ? 'Ultima sincronizzazione: ${DateFormat('dd/MM/yyyy HH:mm').format(widget.creds.lastSync!)}'
                    : 'Sincronizza verifiche, interrogazioni e voti da DidUP Famiglia',
                style: TextStyle(fontSize: 12.5, color: muted),
              ),
              if (widget.lastError != null && widget.lastError!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: alphaCol(VibePalette.verificaRed, 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: alphaCol(VibePalette.verificaRed, 0.5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: VibePalette.verificaRed, size: 19),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SelectableText(
                          widget.lastError!,
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: txt),
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
                decoration:
                    fieldDeco('Codice Scuola (es. SG12345)', icon: CupertinoIcons.building_2_fill),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _userCtrl,
                autocorrect: false,
                decoration: fieldDeco('Nome Utente Argo', icon: CupertinoIcons.person_fill),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                decoration: fieldDeco(
                  'Password',
                  icon: CupertinoIcons.lock_fill,
                  suffix: IconButton(
                    icon: Icon(_obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash),
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
                                  content:
                                      Text('Inserisci Codice Scuola, Nome utente e Password.')),
                            );
                            return;
                          }
                          widget.onSync(_schoolCtrl.text, _userCtrl.text, _passCtrl.text);
                        },
                  icon: widget.syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(CupertinoIcons.arrow_2_circlepath),
                  label: Text(widget.syncing ? 'Sincronizzazione...' : 'Sincronizza Registro Argo'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.syncing
                      ? null
                      : () => widget.onDemo(_schoolCtrl.text, _userCtrl.text, _passCtrl.text),
                  icon: const Icon(CupertinoIcons.sparkles, size: 17),
                  label: const Text('Carica Dati Demo Studenti (Test Rapido)'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: cardDeco(widget.cardColor, widget.borderColor),
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Notifiche attive (Orario 07:20 + Impegni)'),
                subtitle: const Text('Avviso orario ogni mattina alle 07:20 e promemoria eventi'),
                value: widget.notifyOn,
                onChanged: widget.onToggleNotify,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(CupertinoIcons.bell_circle, color: VibePalette.primary),
                title: const Text('Invia notifica di prova'),
                onTap: () => NotificationService.instance.sendTestNotification(),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(CupertinoIcons.trash_circle, color: VibePalette.verificaRed),
                title: const Text('Cancella eventi e voti salvati offline'),
                subtitle: const Text('Il tuo orario scolastico viene mantenuto'),
                onTap: widget.onReset,
              ),
            ],
          ),
        ),
      ],
    );
  }
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