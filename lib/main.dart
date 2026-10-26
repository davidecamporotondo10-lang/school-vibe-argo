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

// ============================================================================
// TEMA & PALETTE "VIBE-CODED" (LIGHT & DARK NATIVO)
// ============================================================================

Color alphaCol(Color c, double opacity) =>
    c.withAlpha((opacity.clamp(0.0, 1.0) * 255).round());

class VibePalette {
  static const Color primary = Color(0xFF635BFF);
  static const Color primaryGlow = Color(0xFF8B5CF6);

  // Badge colorati: Rosso Verifiche, Giallo/Arancione Interrogazioni, Blu/Verde Compiti
  static const Color verificaRed = Color(0xFFFF4757);
  static const Color interrogazioneAmber = Color(0xFFFFA502);
  static const Color compitoBlueGreen = Color(0xFF00C2A8);
  static const Color altroPurple = Color(0xFFA855F7);

  // Dark Mode (ispirato agli screen Studyflow)
  static const Color darkBg = Color(0xFF080C16);
  static const Color darkCard = Color(0xFF111728);
  static const Color darkCardAlt = Color(0xFF161E33);
  static const Color darkBorder = Color(0xFF1F2A44);

  // Light Mode
  static const Color lightBg = Color(0xFFF3F6FC);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightCardAlt = Color(0xFFEEF2FA);
  static const Color lightBorder = Color(0xFFDCE3F0);

  static ThemeData darkTheme() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: primary,
          secondary: primaryGlow,
          surface: darkCard,
          error: verificaRed,
        ),
        scaffoldBackgroundColor: darkBg,
        cardColor: darkCard,
        dividerColor: darkBorder,
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: darkCardAlt,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );

  static ThemeData lightTheme() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: primary,
          secondary: primaryGlow,
          surface: lightCard,
          error: verificaRed,
        ),
        scaffoldBackgroundColor: lightBg,
        cardColor: lightCard,
        dividerColor: lightBorder,
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF0F172A),
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
}

// ============================================================================
// MODELLI DATI (EVENTI, VOTI, CREDENZIALI ARGO)
// ============================================================================

enum EventCategory { verifica, interrogazione, compito, altro }

extension EventCategoryX on EventCategory {
  String get label => const {
        EventCategory.verifica: 'Verifica',
        EventCategory.interrogazione: 'Interrogazione',
        EventCategory.compito: 'Compito',
        EventCategory.altro: 'Altro',
      }[this]!;

  String get chipEmoji => const {
        EventCategory.verifica: '📝',
        EventCategory.interrogazione: '🎤',
        EventCategory.compito: '📚',
        EventCategory.altro: '✨',
      }[this]!;

  String get badgeDot => const {
        EventCategory.verifica: '🔴',
        EventCategory.interrogazione: '🟡',
        EventCategory.compito: '🔵',
        EventCategory.altro: '🟣',
      }[this]!;

  Color get color => const {
        EventCategory.verifica: VibePalette.verificaRed,
        EventCategory.interrogazione: VibePalette.interrogazioneAmber,
        EventCategory.compito: VibePalette.compitoBlueGreen,
        EventCategory.altro: VibePalette.altroPurple,
      }[this]!;

  bool get isHighPriorityDefault =>
      this == EventCategory.verifica || this == EventCategory.interrogazione;
}

class SchoolEvent {
  final String id;
  final String title;
  final String subject;
  final String notes;
  final DateTime dateTime;
  final EventCategory category;
  final bool highPriority;
  final bool completed;
  final bool fromArgo;

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
  });

  SchoolEvent copyWith({bool? completed}) => SchoolEvent(
        id: id,
        title: title,
        subject: subject,
        notes: notes,
        dateTime: dateTime,
        category: category,
        highPriority: highPriority,
        completed: completed ?? this.completed,
        fromArgo: fromArgo,
      );

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
      };

  factory SchoolEvent.fromJson(Map<String, dynamic> j) {
    final cat = EventCategory.values.firstWhere(
      (e) => e.name == (j['category'] ?? 'compito'),
      orElse: () => EventCategory.compito,
    );
    return SchoolEvent(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      subject: j['subject'] as String? ?? 'Materia',
      notes: j['notes'] as String? ?? '',
      dateTime: DateTime.tryParse(j['dateTime'] as String? ?? '') ?? DateTime.now(),
      category: cat,
      highPriority: j['highPriority'] as bool? ?? cat.isHighPriorityDefault,
      completed: j['completed'] as bool? ?? false,
      fromArgo: j['fromArgo'] as bool? ?? false,
    );
  }
}

class SchoolGrade {
  final String id;
  final String subject;
  final double value;
  final double weight;
  final String type; // Scritto, Orale, Pratico
  final String description;
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
        id: j['id'] as String,
        subject: j['subject'] as String? ?? 'Materia',
        value: (j['value'] as num?)?.toDouble() ?? 6.0,
        weight: (j['weight'] as num?)?.toDouble() ?? 1.0,
        type: j['type'] as String? ?? 'Scritto',
        description: j['description'] as String? ?? '',
        date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
        fromArgo: j['fromArgo'] as bool? ?? false,
      );
}

class ArgoCredentials {
  final String schoolCode;
  final String username;
  final String password;
  final String studentName;
  final DateTime? lastSync;

  const ArgoCredentials({
    this.schoolCode = '',
    this.username = '',
    this.password = '',
    this.studentName = '',
    this.lastSync,
  });
}

// ============================================================================
// ARCHIVIAZIONE LOCALE OFFLINE (SHARED PREFERENCES)
// ============================================================================

class StorageService {
  static const _kEvents = 'sv_events_v1';
  static const _kGrades = 'sv_grades_v1';
  static const _kDark = 'sv_dark_v1';
  static const _kNotify = 'sv_notify_v1';
  static const _kSchool = 'sv_argo_school';
  static const _kUser = 'sv_argo_user';
  static const _kPass = 'sv_argo_pass';
  static const _kStudent = 'sv_argo_student';
  static const _kSync = 'sv_argo_sync';

  final SharedPreferences _p;
  StorageService._(this._p);

  static Future<StorageService> init() async =>
      StorageService._(await SharedPreferences.getInstance());

  bool loadDarkMode() => _p.getBool(_kDark) ?? true;
  Future<void> saveDarkMode(bool v) => _p.setBool(_kDark, v);

  bool loadNotifyEnabled() => _p.getBool(_kNotify) ?? true;
  Future<void> saveNotifyEnabled(bool v) => _p.setBool(_kNotify, v);

  List<SchoolEvent> loadEvents() {
    final raw = _p.getString(_kEvents);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => SchoolEvent.fromJson(e as Map<String, dynamic>))
          .toList();
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

  ArgoCredentials loadArgo() {
    final s = _p.getString(_kSync);
    return ArgoCredentials(
      schoolCode: _p.getString(_kSchool) ?? '',
      username: _p.getString(_kUser) ?? '',
      password: _p.getString(_kPass) ?? '',
      studentName: _p.getString(_kStudent) ?? '',
      lastSync: s != null ? DateTime.tryParse(s) : null,
    );
  }

  Future<void> saveArgo(ArgoCredentials c) async {
    await _p.setString(_kSchool, c.schoolCode.trim().toUpperCase());
    await _p.setString(_kUser, c.username.trim());
    await _p.setString(_kPass, c.password);
    await _p.setString(_kStudent, c.studentName);
    if (c.lastSync != null) {
      await _p.setString(_kSync, c.lastSync!.toIso8601String());
    }
  }

  Future<void> clearAll() async {
    for (final k in [_kEvents, _kGrades, _kStudent, _kSync]) {
      await _p.remove(k);
    }
  }
}

// ============================================================================
// NOTIFICHE PUSH LOCALI (GIORNO PRIMA 17:00 + MATTINA STESSA 07:15)
// ============================================================================

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Europe/Rome'));
    } catch (_) {}
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    try {
      await _plugin.initialize(initSettings);
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {}
  }

  NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails(
          'school_vibe_channel',
          'Promemoria Verifiche & Scadenze',
          channelDescription: 'Avvisi automatici per verifiche, interrogazioni e compiti',
          importance: Importance.max,
          priority: Priority.high,
        ),
      );

  Future<void> sendTestNotification() async {
    if (!_ready) await init();
    await _plugin.show(
      999001,
      '✨ School Vibe · Notifiche Attive!',
      'Ti avviseremo il giorno prima (17:00) e la mattina stessa (07:15) delle tue prove.',
      _details(),
    );
  }

  Future<void> syncNotifications(List<SchoolEvent> events, {required bool enabled}) async {
    if (!_ready) await init();
    try {
      await _plugin.cancelAll();
    } catch (_) {}
    if (!enabled) return;

    final now = DateTime.now();
    for (final ev in events) {
      if (ev.completed) continue;
      if (ev.category.isHighPriorityDefault || ev.highPriority) {
        final baseDay = DateTime(ev.dateTime.year, ev.dateTime.month, ev.dateTime.day);
        final dayBefore = baseDay.subtract(const Duration(days: 1)).add(const Duration(hours: 17));
        final morningOf = baseDay.add(const Duration(hours: 7, minutes: 15));
        final baseId = (ev.id.hashCode.abs() % 800000) + 100;

        if (dayBefore.isAfter(now)) {
          await _schedule(
            baseId,
            '${ev.category.badgeDot} Domani: ${ev.category.label} di ${ev.subject}',
            '${ev.title} — Ultimo ripasso pomeridiano, spacca tutto! 💪',
            dayBefore,
          );
        }
        if (morningOf.isAfter(now)) {
          await _schedule(
            baseId + 1,
            '🔥 Oggi hai ${ev.category.label} di ${ev.subject}!',
            '${ev.title} — Respira profondo, sei pronto! 🍀',
            morningOf,
          );
        }
      }
    }
  }

  Future<void> _schedule(int id, String title, String body, DateTime when) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        _details(),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {}
  }
}

// ============================================================================
// INTEGRAZIONE REGISTRO ELETTRONICO ARGO (DidUP OAuth2 PKCE + ScuolaNext REST)
// ============================================================================

class ArgoSyncResult {
  final List<SchoolEvent> events;
  final List<SchoolGrade> grades;
  final String studentName;
  const ArgoSyncResult({required this.events, required this.grades, required this.studentName});
}

class ArgoApiService {
  static const _clientId = '72fd6dea-d0ab-4bb9-8eaa-3ac24c84886c';
  static const _redirectUri = 'it.argosoft.didup.famiglia.new://login-callback';
  static const _scuolaNextBase = 'https://www.portaleargo.it/famiglia/api/rest';

  static Future<ArgoSyncResult> sync({
    required String schoolCode,
    required String username,
    required String password,
  }) async {
    final code = schoolCode.trim().toUpperCase();
    final user = username.trim();
    try {
      return await _syncDidUp(code, user, password);
    } catch (e) {
      try {
        return await _syncScuolaNext(code, user, password);
      } catch (_) {
        throw Exception(
          'Accesso Argo non riuscito ($code). Controlla Codice Scuola, Utente e Password oppure prova i Dati Demo.',
        );
      }
    }
  }

  static Future<ArgoSyncResult> _syncDidUp(String school, String user, String pass) async {
    final verifier = _rndStr(43);
    final challenge = base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
    final authUri = Uri.parse(
      'https://auth.portaleargo.it/oauth2/auth'
      '?redirect_uri=${Uri.encodeComponent(_redirectUri)}'
      '&client_id=$_clientId&response_type=code&prompt=login'
      '&state=${_rndStr(22)}&nonce=${_rndStr(22)}'
      '&scope=${Uri.encodeComponent('openid offline profile user.roles argo')}'
      '&code_challenge=$challenge&code_challenge_method=S256',
    );

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final jar = <String, String>{};

    Future<HttpClientResponse> step(String method, Uri uri, [Map<String, String>? form]) async {
      final req = await client.openUrl(method, uri);
      req.followRedirects = false;
      if (jar.isNotEmpty) {
        req.headers.set(HttpHeaders.cookieHeader, jar.entries.map((e) => '${e.key}=${e.value}').join('; '));
      }
      if (form != null) {
        req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
        req.write(form.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&'));
      }
      final res = await req.close();
      for (final c in res.cookies) {
        jar[c.name] = c.value;
      }
      await res.drain<void>();
      return res;
    }

    try {
      var res = await step('GET', authUri);
      var loc = res.headers.value(HttpHeaders.locationHeader);
      for (int i = 0; i < 4 && loc != null && !loc.contains('login_challenge='); i++) {
        res = await step('GET', authUri.resolve(loc));
        loc = res.headers.value(HttpHeaders.locationHeader);
      }
      final loginChallenge = loc != null ? Uri.parse(loc).queryParameters['login_challenge'] : null;
      if (loginChallenge == null) throw 'Challenge SSO mancante';

      res = await step('POST', Uri.parse('https://www.portaleargo.it/auth/sso/login'), {
        'challenge': loginChallenge,
        'client_id': _clientId,
        'famiglia_customer_code': school,
        'login': 'true',
        'username': user,
        'password': pass,
      });
      loc = res.headers.value(HttpHeaders.locationHeader);
      for (int i = 0; i < 6 && loc != null && !loc.startsWith('it.argosoft.didup.famiglia.new://'); i++) {
        res = await step('GET', Uri.parse(loc));
        loc = res.headers.value(HttpHeaders.locationHeader);
      }
      final authCode = loc != null ? Uri.parse(loc).queryParameters['code'] : null;
      if (authCode == null) throw 'Credenziali errate';

      final tokRes = await http.post(
        Uri.parse('https://auth.portaleargo.it/oauth2/token'),
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: {
          'code': authCode,
          'grant_type': 'authorization_code',
          'redirect_uri': _redirectUri,
          'code_verifier': verifier,
          'client_id': _clientId,
        },
      );
      final tokJson = jsonDecode(tokRes.body) as Map<String, dynamic>;
      final bearer = tokJson['access_token'] as String;
      final expStr = DateFormat('yyyy-MM-dd HH:mm:ss.SSS')
          .format(DateTime.now().add(Duration(seconds: (tokJson['expires_in'] as num?)?.toInt() ?? 3600)));

      Map<String, String> hdr([String? xToken]) => {
            'accept': 'application/json',
            'content-type': 'application/json',
            'argo-client-version': '1.27.0',
            'authorization': 'Bearer $bearer',
            'x-date-exp-auth': expStr,
            if (xToken != null) 'x-auth-token': xToken,
            if (xToken != null) 'x-cod-min': school,
          };

      final loginRes = await http.post(
        Uri.parse('https://www.portaleargo.it/appfamiglia/api/rest/login'),
        headers: hdr(),
        body: jsonEncode({'lista-opzioni-notifiche': '{}', 'lista-x-auth-token': '[]', 'clientID': _rndStr(64)}),
      );
      final loginData = (jsonDecode(loginRes.body)['data'] as List).first as Map<String, dynamic>;
      final xToken = loginData['token'] as String;
      final opzioni = {
        for (final o in (loginData['opzioni'] as List? ?? []))
          if (o is Map<String, dynamic>) '${o['chiave']}': o['valore'],
      };

      final profRes = await http.get(
        Uri.parse('https://www.portaleargo.it/appfamiglia/api/rest/profilo'),
        headers: hdr(xToken),
      );
      final prof = jsonDecode(profRes.body)['data'] as Map<String, dynamic>;
      final studentName = (prof['alunno']?['nominativo'] as String?) ?? user;
      final startYear = (prof['anno']?['dataInizio'] as String?) ?? '${DateTime.now().year - 1}-09-01 00:00:00.000';

      final dashRes = await http.post(
        Uri.parse('https://www.portaleargo.it/appfamiglia/api/rest/dashboard/dashboard'),
        headers: hdr(xToken),
        body: jsonEncode({'dataultimoaggiornamento': startYear, 'opzioni': jsonEncode(opzioni)}),
      );
      final dash = ((jsonDecode(dashRes.body)['data']['dati']) as List).first as Map<String, dynamic>;

      final events = <SchoolEvent>[];
      final grades = <SchoolGrade>[];

      for (final raw in (dash['promemoria'] as List? ?? [])) {
        final m = raw as Map<String, dynamic>;
        final txt = (m['desAnnotazioni'] as String? ?? '').trim();
        if (m['operazione'] == 'D' || txt.isEmpty) continue;
        final d = DateTime.tryParse(m['datGiorno'] as String? ?? '') ?? DateTime.now();
        final cat = classifyText(txt, EventCategory.verifica);
        events.add(SchoolEvent(
          id: 'argo_p_${m['pk'] ?? txt.hashCode}',
          title: txt,
          subject: (m['docente'] as String? ?? 'Promemoria').trim(),
          notes: 'Promemoria Registro Argo',
          dateTime: DateTime(d.year, d.month, d.day, 8, 15),
          category: cat,
          highPriority: cat.isHighPriorityDefault,
          fromArgo: true,
        ));
      }

      for (final raw in (dash['registro'] as List? ?? [])) {
        final m = raw as Map<String, dynamic>;
        if (m['operazione'] == 'D') continue;
        final subj = _cleanSubj(m['materia'] as String? ?? 'Materia');
        for (final c in (m['compiti'] as List? ?? [])) {
          final cm = c as Map<String, dynamic>;
          final txt = (cm['compito'] as String? ?? '').trim();
          if (txt.isEmpty) continue;
          final d = DateTime.tryParse(cm['dataConsegna'] as String? ?? m['datGiorno'] as String? ?? '') ?? DateTime.now();
          final cat = classifyText(txt, EventCategory.compito);
          events.add(SchoolEvent(
            id: 'argo_c_${subj}_${d.toIso8601String()}_${txt.hashCode}',
            title: txt,
            subject: subj,
            notes: '${m['docente'] ?? ''}',
            dateTime: DateTime(d.year, d.month, d.day, 8, 0),
            category: cat,
            highPriority: cat.isHighPriorityDefault,
            fromArgo: true,
          ));
        }
      }

      for (final raw in (dash['voti'] as List? ?? [])) {
        final m = raw as Map<String, dynamic>;
        final val = (m['valore'] as num?)?.toDouble();
        if (m['operazione'] == 'D' || val == null || val <= 0) continue;
        final rawT = (m['codVotoPratico'] as String? ?? 'S').toUpperCase();
        grades.add(SchoolGrade(
          id: 'argo_v_${m['pk'] ?? m.hashCode}',
          subject: _cleanSubj(m['desMateria'] as String? ?? 'Materia'),
          value: val,
          weight: (m['faMenoMedia'] as String? ?? 'S') == 'N' ? 0.0 : 1.0,
          type: (rawT == 'N' || rawT == 'O') ? 'Orale' : (rawT == 'P' ? 'Pratico' : 'Scritto'),
          description: (m['descrizioneProva'] as String? ?? m['desCommento'] as String? ?? '').trim(),
          date: DateTime.tryParse(m['datGiorno'] as String? ?? '') ?? DateTime.now(),
          fromArgo: true,
        ));
      }
      return ArgoSyncResult(events: events, grades: grades, studentName: studentName);
    } finally {
      client.close(force: true);
    }
  }

  static Future<ArgoSyncResult> _syncScuolaNext(String school, String user, String pass) async {
    const baseHdr = {
      'x-version': '2.1.0',
      'x-key-app': 'ax6542sdru3217t4eesd9',
      'x-produttore-software': 'ARGO Software s.r.l. - Ragusa',
      'x-app-code': 'APF',
      'X-Requested-With': 'XMLHttpRequest',
    };
    final lRes = await http.get(
      Uri.parse('$_scuolaNextBase/login?_dc=${DateTime.now().millisecondsSinceEpoch}'),
      headers: {...baseHdr, 'x-cod-min': school, 'x-user-id': user, 'x-pwd': pass},
    );
    final token = (jsonDecode(lRes.body) as Map<String, dynamic>)['token'] as String;
    final sRes = await http.get(
      Uri.parse('$_scuolaNextBase/schede?_dc=${DateTime.now().millisecondsSinceEpoch}'),
      headers: {...baseHdr, 'x-auth-token': token, 'x-cod-min': school},
    );
    final scheda = (jsonDecode(sRes.body) as List).first as Map<String, dynamic>;
    final hdr = {
      ...baseHdr,
      'x-auth-token': token,
      'x-cod-min': school,
      'x-prg-scheda': '${scheda['prgScheda']}',
      'x-prg-scuola': '${scheda['prgScuola']}',
      'x-prg-alunno': '${scheda['prgAlunno']}',
      'x-max-return-record': '100',
    };

    final compRes = await http.get(Uri.parse('$_scuolaNextBase/compiti?page=1&start=0&limit=80'), headers: hdr);
    final promRes = await http.get(Uri.parse('$_scuolaNextBase/promemoria?page=1&start=0&limit=80'), headers: hdr);
    final votiRes = await http.get(Uri.parse('$_scuolaNextBase/votigiornalieri?page=1&start=0&limit=100'), headers: hdr);

    final events = <SchoolEvent>[];
    final grades = <SchoolGrade>[];

    for (final raw in (jsonDecode(compRes.body)['dati'] as List? ?? [])) {
      final m = raw as Map<String, dynamic>;
      final txt = (m['desCompiti'] as String? ?? '').trim();
      if (txt.isEmpty) continue;
      final d = DateTime.tryParse('${m['datCompiti'] ?? m['datGiorno'] ?? ''}') ?? DateTime.now();
      final cat = classifyText(txt, EventCategory.compito);
      events.add(SchoolEvent(
        id: 'sn_c_${txt.hashCode}_${d.millisecondsSinceEpoch}',
        title: txt,
        subject: _cleanSubj(m['desMateria'] as String? ?? 'Materia'),
        dateTime: DateTime(d.year, d.month, d.day, 8, 0),
        category: cat,
        highPriority: cat.isHighPriorityDefault,
        fromArgo: true,
      ));
    }
    for (final raw in (jsonDecode(promRes.body)['dati'] as List? ?? [])) {
      final m = raw as Map<String, dynamic>;
      final txt = (m['desAnnotazioni'] as String? ?? '').trim();
      if (txt.isEmpty) continue;
      final d = DateTime.tryParse('${m['datGiorno'] ?? ''}') ?? DateTime.now();
      final cat = classifyText(txt, EventCategory.verifica);
      events.add(SchoolEvent(
        id: 'sn_p_${txt.hashCode}_${d.millisecondsSinceEpoch}',
        title: txt,
        subject: '${m['desMittente'] ?? 'Docente'}',
        dateTime: DateTime(d.year, d.month, d.day, 8, 15),
        category: cat,
        highPriority: cat.isHighPriorityDefault,
        fromArgo: true,
      ));
    }
    for (final raw in (jsonDecode(votiRes.body)['dati'] as List? ?? [])) {
      final m = raw as Map<String, dynamic>;
      final val = double.tryParse('${m['decValore']}');
      if (val == null || val <= 0) continue;
      grades.add(SchoolGrade(
        id: 'sn_v_${m.hashCode}',
        subject: _cleanSubj(m['desMateria'] as String? ?? 'Materia'),
        value: val,
        type: m['codVotoPratico'] == 'N' ? 'Orale' : 'Scritto',
        description: '${m['desProva'] ?? m['desCommento'] ?? ''}',
        date: DateTime.tryParse('${m['datGiorno'] ?? ''}') ?? DateTime.now(),
        fromArgo: true,
      ));
    }
    return ArgoSyncResult(events: events, grades: grades, studentName: user);
  }

  static EventCategory classifyText(String text, EventCategory fallback) {
    final l = text.toLowerCase();
    if (l.contains('verifica') || l.contains('compito in classe') || l.contains('simulazione') || l.contains('prova scritta')) {
      return EventCategory.verifica;
    }
    if (l.contains('interrogazion') || l.contains('colloquio') || l.contains('orale') || l.contains('esposizione')) {
      return EventCategory.interrogazione;
    }
    return fallback;
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
    DateTime d(int addDays, int h) => DateTime(now.year, now.month, now.day + addDays, h, 15);
    return ArgoSyncResult(
      studentName: 'Studente Demo · 4ª Scientifico',
      events: [
        SchoolEvent(
          id: 'demo_1',
          title: 'Verifica scritta su limiti, continuità e asintoti',
          subject: 'Matematica',
          notes: 'Cap. 12-13 + esercizi guida sul quaderno.',
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
          id: 'demo_3',
          title: 'Circuiti RC e leggi di Kirchhoff pag. 214 n. 15-19',
          subject: 'Fisica',
          dateTime: d(1, 8),
          category: EventCategory.compito,
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
        SchoolGrade(id: 'dg1', subject: 'Matematica', value: 7.5, type: 'Scritto', description: 'Esponenziali e logaritmi', date: now.subtract(const Duration(days: 16)), fromArgo: true),
        SchoolGrade(id: 'dg2', subject: 'Matematica', value: 8.0, type: 'Orale', description: 'Studio di funzione', date: now.subtract(const Duration(days: 5)), fromArgo: true),
        SchoolGrade(id: 'dg3', subject: 'Italiano', value: 7.0, type: 'Scritto', description: 'Tema argomentativo', date: now.subtract(const Duration(days: 12)), fromArgo: true),
        SchoolGrade(id: 'dg4', subject: 'Fisica', value: 5.5, type: 'Scritto', description: 'Teorema di Gauss', date: now.subtract(const Duration(days: 10)), fromArgo: true),
        SchoolGrade(id: 'dg5', subject: 'Inglese', value: 8.5, type: 'Orale', description: 'Victorian Age speaking', date: now.subtract(const Duration(days: 7)), fromArgo: true),
        SchoolGrade(id: 'dg6', subject: 'Informatica', value: 9.0, type: 'Pratico', description: 'Database ER Biblioteca', date: now.subtract(const Duration(days: 3)), fromArgo: true),
      ],
    );
  }
}

// ============================================================================
// ROOT APP & HOME SHELL A 3 SCHERMATE
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
      title: 'school-vibe-argo',
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

  const HomeShell({super.key, required this.storage, required this.isDark, required this.onToggleTheme});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _vibeQuotes = [
    '🎉 Il futuro te ringrazierà per lo studio di oggi 🙏',
    '🚀 Un passo alla volta: spaccherai anche questa settimana!',
    '🧠 Costanza > perfezione. Anche 30 minuti oggi fanno la svolta!',
    '🌟 Ogni pagina ripassata oggi è ansia in meno domani!',
  ];
  static const _chillEmptyQuotes = [
    'Agenda vuota, mente leggera. Che pace! 🧘',
    'Zero scadenze in vista: goditi il meritato relax! 🌴',
    'Tutto tranquillo qui! Ricarica le batterie 🎧',
    'Nessun impegno segnato: giornata libera! ✨',
  ];

  int _tab = 0;
  late List<SchoolEvent> _events = widget.storage.loadEvents();
  late List<SchoolGrade> _grades = widget.storage.loadGrades();
  late ArgoCredentials _argo = widget.storage.loadArgo();
  late bool _notifyOn = widget.storage.loadNotifyEnabled();

  bool _isListView = false;
  EventCategory? _catFilter;
  CalendarFormat _calFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  int _quoteIdx = Random().nextInt(_vibeQuotes.length);
  int _emptyIdx = Random().nextInt(_chillEmptyQuotes.length);
  bool _syncing = false;
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

  List<SchoolEvent> _eventsForDay(DateTime day) => _events
      .where((e) => isSameDay(e.dateTime, day) && (_catFilter == null || e.category == _catFilter))
      .toList();

  List<SchoolEvent> get _upcomingFiltered {
    final startToday = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    return _events
        .where((e) => (!e.dateTime.isBefore(startToday) || !e.completed) && (_catFilter == null || e.category == _catFilter))
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  int get _next7DaysCount {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 7, hours: 23, minutes: 59));
    return _events.where((e) => !e.completed && !e.dateTime.isBefore(start) && !e.dateTime.isAfter(end)).length;
  }

  int get _todoTotal => _events.where((e) => !e.completed).length;
  int get _highPrioTotal =>
      _events.where((e) => !e.completed && (e.highPriority || e.category.isHighPriorityDefault)).length;

  Future<void> _runArgoSync(String school, String user, String pass, {bool demo = false}) async {
    setState(() => _syncing = true);
    try {
      final res = demo
          ? ArgoApiService.demoData()
          : await ArgoApiService.sync(schoolCode: school, username: user, password: pass);
      final creds = ArgoCredentials(
        schoolCode: demo && school.isEmpty ? 'SG00000' : school,
        username: demo && user.isEmpty ? 'studente.demo' : user,
        password: pass,
        studentName: res.studentName,
        lastSync: DateTime.now(),
      );
      setState(() {
        _events = [..._events.where((e) => !e.fromArgo), ...res.events];
        _grades = [..._grades.where((g) => !g.fromArgo), ...res.grades];
        _argo = creds;
      });
      await widget.storage.saveArgo(creds);
      await _saveEvents();
      await _saveGrades();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Sincronizzati ${res.events.length} impegni e ${res.grades.length} voti!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ $e')));
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
                  _buildGradesTab(d, card, border),
                  _ArgoSettingsTab(
                    isDark: d,
                    cardColor: card,
                    borderColor: border,
                    creds: _argo,
                    syncing: _syncing,
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
                      await NotificationService.instance.syncNotifications([], enabled: false);
                      setState(() {
                        _events = [];
                        _grades = [];
                        _argo = const ArgoCredentials();
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _tab == 2
          ? null
          : Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [VibePalette.primary, VibePalette.primaryGlow]),
                boxShadow: [BoxShadow(color: alphaCol(VibePalette.primary, 0.45), blurRadius: 18, offset: const Offset(0, 6))],
              ),
              child: FloatingActionButton(
                elevation: 0,
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                onPressed: () => _tab == 0 ? _showAddEventModal(_selectedDay) : _showAddGradeModal(),
                child: const Icon(CupertinoIcons.add, size: 28),
              ),
            ),
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
              icon: Icon(CupertinoIcons.chart_bar_square),
              selectedIcon: Icon(CupertinoIcons.chart_bar_square_fill, color: VibePalette.primary),
              label: 'Voti & Medie',
            ),
            NavigationDestination(
              icon: Icon(CupertinoIcons.cloud_download),
              selectedIcon: Icon(CupertinoIcons.cloud_download_fill, color: VibePalette.primary),
              label: 'Argo & Sync',
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
              borderRadius: BorderRadius.circular(15),
              gradient: const LinearGradient(colors: [VibePalette.primary, VibePalette.primaryGlow]),
              boxShadow: [BoxShadow(color: alphaCol(VibePalette.primary, 0.42), blurRadius: 14, offset: const Offset(0, 4))],
            ),
            child: const Icon(CupertinoIcons.sparkles, color: Colors.white, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('School Vibe', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: txt)),
                    if (_argo.lastSync != null) ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: alphaCol(VibePalette.compitoBlueGreen, 0.16),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Text('ARGO', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: VibePalette.compitoBlueGreen)),
                      ),
                    ],
                  ],
                ),
                Text(
                  _argo.studentName.isNotEmpty ? _argo.studentName : 'il tuo calendario scolastico',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: muted),
                ),
              ],
            ),
          ),
          _iconCircleBtn(_notifyOn ? CupertinoIcons.bell : CupertinoIcons.bell_slash, d, border, _showNotificationSheet),
          const SizedBox(width: 9),
          _iconCircleBtn(d ? CupertinoIcons.moon_stars : CupertinoIcons.sun_max, d, border, widget.onToggleTheme),
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
          child: Icon(icon, size: 19, color: d ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B)),
        ),
      );

  // --------------------------------------------------------------------------
  // SCHERMATA 1: DASHBOARD CALENDARIO & SCADENZE (ISPIRATA AGLI SCREENSHOT)
  // --------------------------------------------------------------------------

  Widget _buildDashboardTab(bool d, Color card, Color border) {
    final txt = d ? Colors.white : const Color(0xFF0F172A);
    final muted = d ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final rawMonth = DateFormat('MMMM yyyy', 'it_IT').format(_focusedDay);
    final monthTitle = rawMonth[0].toUpperCase() + rawMonth.substring(1);
    final rawDay = DateFormat('EEEE d MMMM', 'it_IT').format(_selectedDay);
    final dayTitle = rawDay.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
    final dayEvents = _eventsForDay(_selectedDay);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Row(
          children: [
            Expanded(child: _kpiBox(CupertinoIcons.calendar_today, const [Color(0xFF635BFF), Color(0xFF8B5CF6)], _next7DaysCount, 'Prossimi 7 giorni', card, border, txt, muted)),
            const SizedBox(width: 10),
            Expanded(child: _kpiBox(CupertinoIcons.checkmark_rectangle, const [Color(0xFF00B894), Color(0xFF00CEC9)], _todoTotal, 'Da fare in totale', card, border, txt, muted)),
            const SizedBox(width: 10),
            Expanded(child: _kpiBox(CupertinoIcons.flame_fill, const [Color(0xFFFF5E3A), Color(0xFFFF2A68)], _highPrioTotal, 'Alta priorità', card, border, txt, muted)),
          ],
        ),
        const SizedBox(height: 15),
        GestureDetector(
          onTap: () => setState(() => _quoteIdx = (_quoteIdx + 1) % _vibeQuotes.length),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: Align(
              key: ValueKey(_quoteIdx),
              alignment: Alignment.centerLeft,
              child: Text(
                _vibeQuotes[_quoteIdx],
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: d ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 15),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(28), border: Border.all(color: border)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _segBtn(!_isListView, CupertinoIcons.calendar, 'Calendario', muted, () => setState(() => _isListView = false)),
                _segBtn(_isListView, CupertinoIcons.list_bullet, 'Lista', muted, () => setState(() => _isListView = true)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _filterChip('🌈 Tutti', _catFilter == null, VibePalette.primary, d, card, border, () => setState(() => _catFilter = null)),
            for (final c in EventCategory.values)
              _filterChip('${c.chipEmoji} ${c.label}', _catFilter == c, c.color, d, card, border, () => setState(() => _catFilter = c)),
          ],
        ),
        const SizedBox(height: 16),
        if (!_isListView) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24), border: Border.all(color: border)),
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 6),
                    Expanded(child: Text(monthTitle, style: TextStyle(fontSize: 18.5, fontWeight: FontWeight.w800, color: txt))),
                    InkWell(
                      onTap: () => setState(() => _calFormat = _calFormat == CalendarFormat.month ? CalendarFormat.week : CalendarFormat.month),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: alphaCol(VibePalette.primary, 0.14), borderRadius: BorderRadius.circular(10)),
                        child: Text(_calFormat == CalendarFormat.month ? 'Mese' : 'Sett.', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: VibePalette.primary)),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _focusedDay = DateTime.now();
                        _selectedDay = DateTime.now();
                      }),
                      child: const Text('Oggi', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF818CF8))),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(CupertinoIcons.chevron_left, size: 17, color: muted),
                      onPressed: () => setState(() => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1, 1)),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(CupertinoIcons.chevron_right, size: 17, color: muted),
                      onPressed: () => setState(() => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 1)),
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
                    dowTextFormatter: (dt, loc) => DateFormat.E(loc).format(dt).replaceAll('.', '').toUpperCase(),
                    weekdayStyle: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: muted),
                    weekendStyle: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: muted),
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
                      gradient: const LinearGradient(colors: [VibePalette.primary, VibePalette.primaryGlow]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: alphaCol(VibePalette.primary, 0.4), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    selectedTextStyle: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  calendarBuilders: CalendarBuilders(
                    markerBuilder: (_, __, evs) => evs.isEmpty
                        ? const SizedBox.shrink()
                        : Positioned(
                            bottom: 4,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: evs.take(4).map((e) => Container(
                                    width: 6,
                                    height: 6,
                                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                    decoration: BoxDecoration(color: e.category.color, shape: BoxShape.circle),
                                  )).toList(),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Divider(color: border, height: 1),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: EventCategory.values
                      .map((c) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 9, height: 9, decoration: BoxDecoration(color: c.color, shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Text(c.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: muted)),
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
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24), border: Border.all(color: border)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(dayTitle, style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800, color: txt))),
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _showAddEventModal(_selectedDay),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                        decoration: BoxDecoration(
                          color: alphaCol(VibePalette.primary, 0.16),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: alphaCol(VibePalette.primary, 0.4)),
                        ),
                        child: const Text('+ Aggiungi', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF818CF8))),
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
                      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 18),
                      decoration: BoxDecoration(
                        color: d ? alphaCol(VibePalette.darkCardAlt, 0.45) : VibePalette.lightCardAlt,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          const Text('🌴', style: TextStyle(fontSize: 42)),
                          const SizedBox(height: 10),
                          Text(_chillEmptyQuotes[_emptyIdx], textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: muted)),
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

  Widget _kpiBox(IconData icon, List<Color> grad, int val, String label, Color card, Color border, Color txt, Color muted) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(22), border: Border.all(color: border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: LinearGradient(colors: grad)),
              child: Icon(icon, color: Colors.white, size: 19),
            ),
            const SizedBox(height: 12),
            Text('$val', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: txt)),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: muted)),
          ],
        ),
      );

  Widget _segBtn(bool active, IconData icon, String label, Color muted, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: active ? const LinearGradient(colors: [VibePalette.primary, VibePalette.primaryGlow]) : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: 15, color: active ? Colors.white : muted),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: active ? Colors.white : muted)),
            ],
          ),
        ),
      );

  Widget _filterChip(String text, bool sel, Color accent, bool d, Color card, Color border, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
              color: sel ? (d ? Colors.white : accent) : (d ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
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
                  '⏳ CONTO ALLA ROVESCIA · ${nextEv.category.label.toUpperCase()}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white70),
                ),
                const SizedBox(height: 6),
                Text('${nextEv.subject} — ${nextEv.title}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
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
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24), border: Border.all(color: border)),
          child: list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 26),
                  child: Column(
                    children: [
                      const Text('🎉', style: TextStyle(fontSize: 40)),
                      const SizedBox(height: 8),
                      Text('Nessuna scadenza in programma! Rilassati o sincronizza Argo.', textAlign: TextAlign.center, style: TextStyle(color: muted)),
                    ],
                  ),
                )
              : Column(children: list.map((e) => _eventCardTile(e, d, border, txt, muted)).toList()),
        ),
      ],
    );
  }

  Widget _cdBox(String val, String unit) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(color: alphaCol(Colors.black, 0.24), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text(val, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
            Text(unit, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white70)),
          ],
        ),
      );

  String _countdownText(DateTime dt) {
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return isSameDay(dt, DateTime.now()) ? 'Oggi' : 'Scaduto';
    if (diff.inDays >= 1) return 'Tra ${diff.inDays}g ${diff.inHours % 24}h';
    if (diff.inHours >= 1) return 'Tra ${diff.inHours}h ${diff.inMinutes % 60}m';
    return 'Tra ${max(1, diff.inMinutes)}m';
  }

  Widget _eventCardTile(SchoolEvent ev, bool d, Color border, Color txt, Color muted) {
    final c = ev.category.color;
    return Container(
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
                color: ev.completed ? VibePalette.compitoBlueGreen : alphaCol(c, 0.15),
                border: Border.all(color: ev.completed ? VibePalette.compitoBlueGreen : c, width: 2),
              ),
              child: ev.completed ? const Icon(Icons.check, size: 15, color: Colors.white) : null,
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
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: alphaCol(c, 0.18), borderRadius: BorderRadius.circular(7)),
                      child: Text('${ev.category.badgeDot} ${ev.category.label}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: alphaCol(VibePalette.primary, 0.16), borderRadius: BorderRadius.circular(7)),
                      child: Text(ev.subject, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF818CF8))),
                    ),
                    if (!ev.completed)
                      Text('⏱ ${_countdownText(ev.dateTime)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: txt)),
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
                if (ev.notes.isNotEmpty) Text(ev.notes, style: TextStyle(fontSize: 12, color: muted)),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('EEE d MMM · HH:mm', 'it_IT').format(ev.dateTime)}${ev.fromArgo ? ' · Sincronizzato da Argo' : ''}',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(CupertinoIcons.trash, size: 17, color: muted),
            onPressed: () async {
              setState(() => _events.removeWhere((x) => x.id == ev.id));
              await _saveEvents();
            },
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // SCHERMATA 2: VOTI & CALCOLO MEDIE (PONDERATA / ARITMETICA)
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

  Color _gradeCol(double v) =>
      v >= 6.0 ? VibePalette.compitoBlueGreen : (v >= 5.5 ? VibePalette.interrogazioneAmber : VibePalette.verificaRed);

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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24), border: Border.all(color: border)),
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
                        valueColor: AlwaysStoppedAnimation(_grades.isEmpty ? VibePalette.primary : _gradeCol(totalAvg)),
                      ),
                    ),
                    Text(_grades.isEmpty ? '--' : totalAvg.toStringAsFixed(2), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: txt)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_weightedAvg ? 'Media Generale Ponderata' : 'Media Generale Aritmetica', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: txt)),
                    const SizedBox(height: 4),
                    Text('${_grades.length} voti in ${subjects.length} materie', style: TextStyle(fontSize: 12.5, color: muted)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(label: const Text('Ponderata'), selected: _weightedAvg, onSelected: (_) => setState(() => _weightedAvg = true)),
                        ChoiceChip(label: const Text('Aritmetica'), selected: !_weightedAvg, onSelected: (_) => setState(() => _weightedAvg = false)),
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
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24), border: Border.all(color: border)),
            child: Column(
              children: [
                const Text('📊', style: TextStyle(fontSize: 42)),
                const SizedBox(height: 10),
                Text('Nessun voto presente', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: txt)),
                const SizedBox(height: 6),
                Text('Sincronizza Argo nella scheda "Argo & Sync" o premi + per inserire un voto.', textAlign: TextAlign.center, style: TextStyle(color: muted)),
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
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(20), border: Border.all(color: border)),
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                leading: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: alphaCol(col, 0.16), borderRadius: BorderRadius.circular(13)),
                  child: Text(m.toStringAsFixed(1), style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: col)),
                ),
                title: Text(s, style: TextStyle(fontWeight: FontWeight.w800, color: txt)),
                subtitle: Text(
                  needed > 0 && needed <= 10 ? '${list.length} voti · Per il ${target.toInt()} serve ${needed.toStringAsFixed(1)}' : '${list.length} voti · Ottima media! 🔥',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                children: list.map((g) {
                  final gc = _gradeCol(g.value);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: alphaCol(gc, 0.18),
                      child: Text(g.value.toStringAsFixed(1), style: TextStyle(fontWeight: FontWeight.w800, color: gc, fontSize: 13)),
                    ),
                    title: Text(g.description.isEmpty ? 'Prova ${g.type}' : g.description, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: txt)),
                    subtitle: Text('${g.type} · Peso ${(g.weight * 100).round()}% · ${DateFormat('dd/MM/yyyy').format(g.date)}${g.fromArgo ? ' · ARGO' : ''}', style: TextStyle(fontSize: 11.5, color: muted)),
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
  // MODALI INSERIMENTO EVENTI, VOTI E TEST NOTIFICHE
  // --------------------------------------------------------------------------

  void _showNotificationSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: widget.isDark ? VibePalette.darkCard : VibePalette.lightCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🔔 Promemoria Automatici', style: TextStyle(fontSize: 18.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Ricevi notifiche push locali il giorno prima (17:00) e la mattina stessa (07:15) di ogni Verifica o Interrogazione.'),
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

  void _showAddEventModal(DateTime baseDate) {
    final subjCtrl = TextEditingController(text: 'Matematica');
    final titleCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    var cat = EventCategory.verifica;
    var dt = DateTime(baseDate.year, baseDate.month, baseDate.day, 8, 15);
    var prio = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.isDark ? VibePalette.darkCard : VibePalette.lightCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('✨ Nuovo Impegno', style: TextStyle(fontSize: 18.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: EventCategory.values
                      .map((c) => ChoiceChip(
                            label: Text('${c.badgeDot} ${c.label}'),
                            selected: cat == c,
                            onSelected: (_) => setM(() {
                              cat = c;
                              prio = c.isHighPriorityDefault;
                            }),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 10),
                TextField(controller: subjCtrl, decoration: const InputDecoration(labelText: 'Materia', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Argomento / Titolo', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Note (opzionale)', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(CupertinoIcons.calendar, size: 16),
                        label: Text(DateFormat('dd/MM/yyyy').format(dt)),
                        onPressed: () async {
                          final p = await showDatePicker(context: ctx, initialDate: dt, firstDate: DateTime(2023), lastDate: DateTime(2030));
                          if (p != null) setM(() => dt = DateTime(p.year, p.month, p.day, dt.hour, dt.minute));
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(CupertinoIcons.clock, size: 16),
                        label: Text(DateFormat('HH:mm').format(dt)),
                        onPressed: () async {
                          final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(dt));
                          if (t != null) setM(() => dt = DateTime(dt.year, dt.month, dt.day, t.hour, t.minute));
                        },
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('🔥 Alta priorità & Promemoria push'),
                  value: prio,
                  onChanged: (v) => setM(() => prio = v),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final s = subjCtrl.text.trim().isEmpty ? 'Materia' : subjCtrl.text.trim();
                      final t = titleCtrl.text.trim().isEmpty ? '${cat.label} di $s' : titleCtrl.text.trim();
                      setState(() {
                        _events.add(SchoolEvent(
                          id: 'm_${DateTime.now().millisecondsSinceEpoch}',
                          title: t,
                          subject: s,
                          notes: notesCtrl.text.trim(),
                          dateTime: dt,
                          category: cat,
                          highPriority: prio,
                        ));
                        _selectedDay = dt;
                        _focusedDay = dt;
                      });
                      await _saveEvents();
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Salva Impegno'),
                  ),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🎯 Nuovo Voto', style: TextStyle(fontSize: 18.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                TextField(controller: subjCtrl, decoration: const InputDecoration(labelText: 'Materia', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                Text('Voto: ${val.toStringAsFixed(2)}  ·  Peso: ${(weight * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800)),
                Slider(value: val, min: 1, max: 10, divisions: 36, onChanged: (v) => setM(() => val = v)),
                Slider(value: weight, min: 0.25, max: 1.0, divisions: 3, onChanged: (v) => setM(() => weight = v)),
                Wrap(
                  spacing: 8,
                  children: ['Scritto', 'Orale', 'Pratico']
                      .map((t) => ChoiceChip(label: Text(t), selected: type == t, onSelected: (_) => setM(() => type = t)))
                      .toList(),
                ),
                const SizedBox(height: 10),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Argomento (opzionale)', border: OutlineInputBorder())),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      setState(() {
                        _grades.add(SchoolGrade(
                          id: 'g_${DateTime.now().millisecondsSinceEpoch}',
                          subject: subjCtrl.text.trim().isEmpty ? 'Materia' : subjCtrl.text.trim(),
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
// SCHERMATA 3: LOGIN REGISTRO ARGO & IMPOSTAZIONI
// ============================================================================

class _ArgoSettingsTab extends StatefulWidget {
  final bool isDark;
  final Color cardColor;
  final Color borderColor;
  final ArgoCredentials creds;
  final bool syncing;
  final bool notifyOn;
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: widget.cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: widget.borderColor)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('☁️ Login Registro Elettronico Argo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: txt)),
              const SizedBox(height: 4),
              Text(
                widget.creds.lastSync != null
                    ? 'Ultima sincronizzazione: ${DateFormat('dd/MM/yyyy HH:mm').format(widget.creds.lastSync!)}'
                    : 'Sincronizza compiti, verifiche e voti con DidUP / ScuolaNext',
                style: TextStyle(fontSize: 12.5, color: muted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _schoolCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Codice Scuola (es. SG12345)',
                  prefixIcon: Icon(CupertinoIcons.building_2_fill),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _userCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nome Utente Argo',
                  prefixIcon: Icon(CupertinoIcons.person_fill),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(CupertinoIcons.lock_fill),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
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
                          if (_schoolCtrl.text.trim().isEmpty || _userCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Inserisci Codice Scuola, Nome utente e Password.')),
                            );
                            return;
                          }
                          widget.onSync(_schoolCtrl.text, _userCtrl.text, _passCtrl.text);
                        },
                  icon: widget.syncing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(CupertinoIcons.arrow_2_circlepath),
                  label: Text(widget.syncing ? 'Sincronizzazione...' : 'Sincronizza Registro Argo'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.syncing ? null : () => widget.onDemo(_schoolCtrl.text, _userCtrl.text, _passCtrl.text),
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
          decoration: BoxDecoration(color: widget.cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: widget.borderColor)),
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Promemoria automatici (17:00 e 07:15)'),
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
                title: const Text('Cancella dati salvati offline'),
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
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 11) {
        canvas.drawPath(metric.extractPath(d, min(d + 6, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) => old.color != color || old.radius != radius;
}
