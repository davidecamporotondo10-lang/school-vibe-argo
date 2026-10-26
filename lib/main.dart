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

  // Dark Mode
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
      (e) => e.name == '${j['category'] ?? 'compito'}',
      orElse: () => EventCategory.compito,
    );
    return SchoolEvent(
      id: '${j['id'] ?? ''}',
      title: '${j['title'] ?? ''}',
      subject: '${j['subject'] ?? 'Materia'}',
      notes: '${j['notes'] ?? ''}',
      dateTime: DateTime.tryParse('${j['dateTime'] ?? ''}') ?? DateTime.now(),
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
// INTEGRAZIONE REGISTRO ELETTRONICO ARGO (DidUP 1.30.2+ OAuth2 PKCE + ScuolaNext)
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
  static const _defaultAppVersion = '1.30.2';
  static const _dataInizioDefault = '2000-01-01 00:00:00.000';
  static const _scuolaNextBase = 'https://www.portaleargo.it/famiglia/api/rest';

  static String _fmtArgoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}:'
      '${d.second.toString().padLeft(2, '0')}.'
      '${d.millisecond.toString().padLeft(3, '0')}';

  /// Recupera automaticamente l'ultima versione pubblicata di didUP Famiglia
  /// sullo Store per evitare errori HTTP 410 quando Argo aggiorna l'app.
  static Future<String> _resolveClientVersion() async {
    try {
      final res = await http
          .get(Uri.parse('https://itunes.apple.com/lookup?bundleId=it.argosoft.didup.famiglia.new&country=it'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final results = (data['results'] as List?) ?? [];
        if (results.isNotEmpty) {
          final storeVer = '${(results.first as Map<String, dynamic>)['version'] ?? ''}'.trim();
          if (storeVer.isNotEmpty && _compareSemver(storeVer, _defaultAppVersion) >= 0) {
            return storeVer;
          }
        }
      }
    } catch (_) {}
    return _defaultAppVersion;
  }

  static int _compareSemver(String a, String b) {
    final pa = a.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    final pb = b.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  static void _collectCookies(HttpClientResponse res, List<String> cookies) {
    final rawList = res.headers[HttpHeaders.setCookieHeader];
    if (rawList == null) return;
    for (final header in rawList) {
      final pair = header.split(';').first.trim();
      if (pair.isNotEmpty) {
        cookies.add(pair);
      }
    }
  }

  static List<Map<String, dynamic>> _applyArgoOps(List<dynamic>? rawList) {
    if (rawList == null) return [];
    final deleted = <String>{};
    for (final item in rawList) {
      if (item is Map<String, dynamic> && item['operazione'] == 'D' && item['pk'] != null) {
        deleted.add('${item['pk']}');
      }
    }
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

  static Future<ArgoSyncResult> sync({
    required String schoolCode,
    required String username,
    required String password,
  }) async {
    final code = schoolCode.trim().toUpperCase();
    final user = username.trim();
    try {
      return await _syncDidUp(code, user, password);
    } catch (didUpErr) {
      try {
        return await _syncScuolaNext(code, user, password);
      } catch (_) {
        throw Exception('$didUpErr');
      }
    }
  }

  static Future<ArgoSyncResult> _syncDidUp(String school, String user, String pass) async {
    final appVersion = await _resolveClientVersion();
    final verifier = _rndStr(43);
    final challenge = base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
    final authUri = Uri.parse(
      'https://auth.portaleargo.it/oauth2/auth'
      '?redirect_uri=${Uri.encodeComponent(_redirectUri)}'
      '&client_id=$_clientId'
      '&response_type=code'
      '&prompt=login'
      '&state=${_rndStr(22)}'
      '&nonce=${_rndStr(22)}'
      '&scope=${Uri.encodeComponent('openid offline profile user.roles argo')}'
      '&code_challenge=$challenge'
      '&code_challenge_method=S256',
    );

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 25);
    final cookies = <String>[];

    Future<HttpClientResponse> passo(
      String method,
      Uri uri, {
      String? formBody,
      List<String>? sendCookies,
    }) async {
      final req = await client.openUrl(method, uri);
      req.followRedirects = false;
      if (sendCookies != null && sendCookies.isNotEmpty) {
        req.headers.set(HttpHeaders.cookieHeader, sendCookies.join('; '));
      }
      if (formBody != null) {
        final bodyBytes = utf8.encode(formBody);
        req.headers.set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
        req.contentLength = bodyBytes.length;
        req.add(bodyBytes);
      }
      final res = await req.close().timeout(const Duration(seconds: 25));
      await res.drain<void>();
      return res;
    }

    try {
      // 1) GET iniziale su auth.portaleargo.it -> raccoglie cookie OAuth + login_challenge
      final r0 = await passo('GET', authUri);
      _collectCookies(r0, cookies);
      final loc0 = r0.headers.value(HttpHeaders.locationHeader);
      if (loc0 == null) {
        throw 'Impossibile iniziare il login OAuth Argo (HTTP ${r0.statusCode}).';
      }
      final challengeParam = authUri.resolve(loc0).queryParameters['login_challenge'];
      if (challengeParam == null || challengeParam.isEmpty) {
        throw 'Parametro login_challenge non restituito da Argo.';
      }

      // 2) POST credenziali su www.portaleargo.it/auth/sso/login (senza cookie, con prefill=false)
      final ssoUri = Uri.parse('https://www.portaleargo.it/auth/sso/login');
      final formBody = [
        'challenge=${Uri.encodeQueryComponent(challengeParam)}',
        'client_id=${Uri.encodeQueryComponent(_clientId)}',
        'prefill=false',
        'famiglia_customer_code=${Uri.encodeQueryComponent(school)}',
        'username=${Uri.encodeQueryComponent(user)}',
        'password=${Uri.encodeQueryComponent(pass)}',
        'login=true',
      ].join('&');

      final r1 = await passo('POST', ssoUri, formBody: formBody);
      final loc1 = r1.headers.value(HttpHeaders.locationHeader);
      if (loc1 == null || loc1.contains('/auth/sso/login')) {
        throw 'Credenziali errate: controlla Codice Scuola ($school), Nome Utente e Password.';
      }

      // 3) Catena di 3 redirect OAuth con invio cookie solo verso auth.portaleargo.it
      final url1 = ssoUri.resolve(loc1);
      final r2 = await passo('GET', url1, sendCookies: cookies);
      _collectCookies(r2, cookies);
      final loc2 = r2.headers.value(HttpHeaders.locationHeader);
      if (loc2 == null) {
        throw 'Login SSO interrotto: verifica credenziali o eventuale cambio password richiesto sul sito Argo.';
      }

      String callbackUrl;
      if (loc2.startsWith('it.argosoft.didup.famiglia.new://')) {
        callbackUrl = loc2;
      } else {
        final url2 = url1.resolve(loc2);
        final r3 = await passo('GET', url2);
        final loc3 = r3.headers.value(HttpHeaders.locationHeader);
        if (loc3 == null) {
          throw 'Catena OAuth interrotta durante il consenso Argo.';
        }
        if (loc3.startsWith('it.argosoft.didup.famiglia.new://')) {
          callbackUrl = loc3;
        } else {
          final url3 = url2.resolve(loc3);
          final r4 = await passo('GET', url3, sendCookies: cookies);
          final loc4 = r4.headers.value(HttpHeaders.locationHeader);
          if (loc4 == null) {
            throw 'Redirect finale OAuth mancante da Argo.';
          }
          callbackUrl = loc4;
        }
      }

      final authCode = Uri.parse(callbackUrl).queryParameters['code'];
      if (authCode == null || authCode.isEmpty) {
        final err = Uri.parse(callbackUrl).queryParameters['error_description'] ??
            Uri.parse(callbackUrl).queryParameters['error'] ??
            'codice autorizzazione assente';
        throw 'Autorizzazione Argo rifiutata ($err).';
      }

      // 4) Scambio code -> Bearer access_token
      final tokRes = await http
          .post(
            Uri.parse('https://auth.portaleargo.it/oauth2/token'),
            headers: {'content-type': 'application/x-www-form-urlencoded'},
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
        throw 'Token OAuth non ottenuto: ${tokJson['error_description'] ?? tokJson['error'] ?? tokRes.statusCode}';
      }
      final bearer = '${tokJson['access_token']}';
      final expDate = DateTime.now().add(Duration(seconds: (tokJson['expires_in'] as num?)?.toInt() ?? 3600));
      final expStr = _fmtArgoDate(expDate);

      Map<String, String> didupHeaders([String? xToken, String? codMin]) => {
            'accept': 'application/json',
            'argo-client-version': appVersion,
            'content-type': 'application/json; charset=utf-8',
            'authorization': 'Bearer $bearer',
            'x-date-exp-auth': expStr,
            if (xToken != null) 'x-auth-token': xToken,
            if (codMin != null) 'x-cod-min': codMin,
          };

      // 5) POST login sull'API AppFamiglia DidUP
      final loginRes = await http
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

      if (loginRes.statusCode == 410) {
        throw 'Versione protocollo DidUP ($appVersion) rifiutata dal server Argo (HTTP 410).';
      }
      final loginRoot = jsonDecode(loginRes.body) as Map<String, dynamic>;
      if (loginRoot['success'] == false) {
        throw '${loginRoot['msg'] ?? 'Login applicativo Argo non riuscito'}';
      }
      final profiliList = ((loginRoot['data'] as List?) ?? []).whereType<Map<String, dynamic>>().toList();
      if (profiliList.isEmpty) {
        throw 'Nessun profilo alunno attivo trovato su questo account Argo.';
      }

      // Seleziona il profilo attivo corrispondente al Codice Scuola
      final activeProfiles = profiliList.where((p) => p['profiloDisabilitato'] != true).toList();
      final candidates = activeProfiles.isNotEmpty ? activeProfiles : profiliList;
      final loginData = candidates.firstWhere(
        (p) => '${p['codMin'] ?? ''}'.toUpperCase() == school,
        orElse: () => candidates.first,
      );

      final xToken = '${loginData['token'] ?? ''}';
      final actualCodMin = '${loginData['codMin'] ?? school}';
      final opzioniMap = <String, dynamic>{
        for (final o in (loginData['opzioni'] as List? ?? []))
          if (o is Map<String, dynamic> && o['chiave'] != null) '${o['chiave']}': o['valore'],
      };

      // 6) Nome studente da GET profilo
      String studentName = user;
      try {
        final profRes = await http
            .get(
              Uri.parse('https://www.portaleargo.it/appfamiglia/api/rest/profilo'),
              headers: didupHeaders(xToken, actualCodMin),
            )
            .timeout(const Duration(seconds: 15));
        final profData = (jsonDecode(profRes.body) as Map<String, dynamic>)['data'];
        if (profData is Map<String, dynamic>) {
          final alunno = profData['alunno'];
          if (alunno is Map<String, dynamic>) {
            final nom = '${alunno['nominativo'] ?? ''}'.trim();
            if (nom.isNotEmpty) studentName = nom;
          }
        }
      } catch (_) {}

      // 7) POST dashboard/dashboard (con data 2000-01-01 per ricevere tutti i dati dell'anno)
      final dashRes = await http
          .post(
            Uri.parse('https://www.portaleargo.it/appfamiglia/api/rest/dashboard/dashboard'),
            headers: didupHeaders(xToken, actualCodMin),
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
        return ArgoSyncResult(events: [], grades: [], studentName: studentName);
      }
      final dash = datiList.first as Map<String, dynamic>;

      // Associazione docente -> materia per arricchire i promemoria
      final matByPk = <String, String>{};
      for (final m in (dash['listaMaterie'] as List? ?? [])) {
        if (m is Map<String, dynamic> && m['pk'] != null) {
          matByPk['${m['pk']}'] = _cleanSubj('${m['materia'] ?? ''}');
        }
      }
      final docMateria = <String, String>{};
      for (final d in (dash['listaDocentiClasse'] as List? ?? [])) {
        if (d is Map<String, dynamic> && d['pk'] != null) {
          final ml = (d['materie'] as List?) ?? [];
          if (ml.isNotEmpty) {
            final k = '${ml.first}';
            docMateria['${d['pk']}'] = matByPk[k] ?? _cleanSubj(k);
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
        final subj = docMateria['${m['pkDocente'] ?? ''}'] ??
            (docName.isNotEmpty ? docName : 'Promemoria');
        final cat = classifyText(txt, EventCategory.verifica);
        events.add(SchoolEvent(
          id: 'argo_p_${m['pk'] ?? txt.hashCode}',
          title: txt,
          subject: subj,
          notes: docName.isNotEmpty ? 'Docente: $docName' : 'Promemoria Argo',
          dateTime: DateTime(d.year, d.month, d.day, 8, 15),
          category: cat,
          highPriority: cat.isHighPriorityDefault,
          fromArgo: true,
        ));
      }

      for (final m in _applyArgoOps(dash['registro'] as List?)) {
        final subj = _cleanSubj('${m['materia'] ?? 'Materia'}');
        final docName = '${m['docente'] ?? ''}'.trim();
        for (final c in (m['compiti'] as List? ?? [])) {
          if (c is! Map<String, dynamic>) continue;
          final txt = '${c['compito'] ?? ''}'.trim();
          if (txt.isEmpty) continue;
          final dueRaw = '${c['dataConsegna'] ?? ''}'.trim();
          final fallbackDay = '${m['datGiorno'] ?? ''}'.trim();
          final d = DateTime.tryParse(dueRaw.isNotEmpty ? dueRaw : fallbackDay) ?? DateTime.now();
          final cat = classifyText(txt, EventCategory.compito);
          events.add(SchoolEvent(
            id: 'argo_c_${subj}_${d.toIso8601String()}_${txt.hashCode}',
            title: txt,
            subject: subj,
            notes: docName,
            dateTime: DateTime(d.year, d.month, d.day, 8, 0),
            category: cat,
            highPriority: cat.isHighPriorityDefault,
            fromArgo: true,
          ));
        }
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
    final lRes = await http
        .get(
          Uri.parse('$_scuolaNextBase/login?_dc=${DateTime.now().millisecondsSinceEpoch}'),
          headers: {...baseHdr, 'x-cod-min': school, 'x-user-id': user, 'x-pwd': pass},
        )
        .timeout(const Duration(seconds: 15));
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
      final txt = '${m['desCompiti'] ?? ''}'.trim();
      if (txt.isEmpty) continue;
      final d = DateTime.tryParse('${m['datCompiti'] ?? m['datGiorno'] ?? ''}') ?? DateTime.now();
      final cat = classifyText(txt, EventCategory.compito);
      events.add(SchoolEvent(
        id: 'sn_c_${txt.hashCode}_${d.millisecondsSinceEpoch}',
        title: txt,
        subject: _cleanSubj('${m['desMateria'] ?? 'Materia'}'),
        dateTime: DateTime(d.year, d.month, d.day, 8, 0),
        category: cat,
        highPriority: cat.isHighPriorityDefault,
        fromArgo: true,
      ));
    }
    for (final raw in (jsonDecode(promRes.body)['dati'] as List? ?? [])) {
      final m = raw as Map<String, dynamic>;
      final txt = '${m['desAnnotazioni'] ?? ''}'.trim();
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
        subject: _cleanSubj('${m['desMateria'] ?? 'Materia'}'),
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
    if (l.contains('verifica') ||
        l.contains('compito in classe') ||
        l.contains('simulazione') ||
        l.contains('prova scritta')) {
      return EventCategory.verifica;
    }
    if (l.contains('interrogazion') ||
        l.contains('colloquio') ||
        l.contains('orale') ||
        l.contains('esposizione')) {
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
    setState(() {
      _syncing = true;
      _lastSyncError = null;
    });
    try {
      final res = demo
          ? ArgoApiService.demoData()
          : await ArgoApiService.sync(schoolCode: school, username: user, password: pass);
      final creds = ArgoCredentials(
        schoolCode: demo && school.isEmpty ? 'SG00000' : school.trim().toUpperCase(),
        username: demo && user.isEmpty ? 'studente.demo' : user.trim(),
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
      final cleanErr = e.toString().replaceFirst('Exception: ', '');
      setState(() => _lastSyncError = cleanErr);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ $cleanErr')));
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
                      await NotificationService.instance.syncNotifications([], enabled: false);
                      setState(() {
                        _events = [];
                        _grades = [];
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
  // SCHERMATA 1: DASHBOARD CALENDARIO & SCADENZE (SCROLL VERTICALE FLUIDO!)
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
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
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
                  // Sblocca lo scroll verticale quando si passa il dito sopra al calendario!
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
            onTap: () async 
