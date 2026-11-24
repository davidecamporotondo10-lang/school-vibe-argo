"""Source-level regression checks; run with python3 -m unittest discover -s tests.
These do not replace Flutter analysis or Android device tests.
"""
import hashlib
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'lib/main.dart').read_text()


def section(start, end):
    offset = SOURCE.index(start)
    return SOURCE[offset:SOURCE.index(end, offset)]


def normalize_api_decoders(text):
    text = text.replace("ArgoResponseParser.decode(res, 'Rinnovo sessione');", 'jsonDecode(res.body) as Map<String, dynamic>;')
    text = text.replace("ArgoResponseParser.decode(tokRes, 'Token OAuth');", 'jsonDecode(tokRes.body) as Map<String, dynamic>;')
    text = text.replace("ArgoResponseParser.decode(loginRes, 'Login applicativo');", 'jsonDecode(loginRes.body) as Map<String, dynamic>;')
    text = text.replace("(ArgoResponseParser.decode(pRes, 'Profilo')['data'] as Map?)?['alunno']", "((jsonDecode(pRes.body) as Map<String, dynamic>)['data'] as Map?)?['alunno']")
    text = text.replace("ArgoResponseParser.decode(dashRes, 'Dashboard registro');", 'jsonDecode(dashRes.body) as Map<String, dynamic>;')
    return text


class RequestedChanges(unittest.TestCase):
    def test_argo_sync_unchanged_from_complete_upstream(self):
        for start, end, digest in [
            ('class ArgoSyncResult {', 'class SchoolVibeApp extends',
             '937d47356f61702cad3753c817a12bd99f1529e3f6a40afd01ff0edc587a78fd'),
        ]:
            self.assertEqual(hashlib.sha256(normalize_api_decoders(section(start, end)).encode()).hexdigest(), digest)

    def test_sync_transport_call_unchanged(self):
        call = section('      final res = demo', '      final creds = ArgoCredentials(')
        self.assertIn('savedRefreshToken: sameAccount ? _argo.refreshToken :', call)
        self.assertEqual(hashlib.sha256(call.encode()).hexdigest(),
                         '6c0bd3462c22f3a6d53fc9fc06c044cb0625d2ff6304c63303989c512be9a0aa')

    def test_daily_sync_is_silent_and_guarded(self):
        daily = section('  Future<void> _syncArgoIfDue()', '  Future<void> _exportTimetable()')
        self.assertIn('silent: true', daily)
        self.assertIn("prefs.getString(_dailySyncKey) == today", daily)
        self.assertIn('_checkingDailySync', daily)
        self.assertIn('AppLifecycleState.resumed', SOURCE)
        sync = section('  Future<void> _runArgoSync(', '  @override\n  Widget build(BuildContext context)')
        self.assertIn('if (mounted && !silent)', sync)

    def test_backup_is_versioned_and_confirmed(self):
        backup = section('  Future<void> _exportTimetable()', '  Future<void> _saveEvents()')
        self.assertIn("'format': 'school-vibe-timetable'", backup)
        self.assertIn('confirmed != true', backup)
        self.assertIn('bytes.length > 1024 * 1024', backup)
        self.assertNotIn('password', backup)
        self.assertIn('Backup orario', SOURCE)

    def test_android_import_does_not_filter_out_generic_json_files(self):
        importer = section('  Future<void> _importTimetable()', '  Future<void> _saveEvents()')
        picker = importer[:importer.index('if (picked == null')]
        self.assertIn('type: FileType.any', picker)
        self.assertIn('allowMultiple: false', picker)
        self.assertIn('withData: true', picker)
        self.assertNotIn('allowedExtensions', picker)
        # Accepting any MIME type must not bypass the backup schema checks.
        self.assertIn("decoded['format'] != 'school-vibe-timetable'", importer)
        self.assertIn("decoded['version'] != 1", importer)
        self.assertIn('days.length != 5', importer)
        self.assertIn('confirmed != true', importer)
        self.assertLess(importer.index('confirmed != true'), importer.index('saveTimetable(imported)'))

    def test_lesson_editor_simplified(self):
        editor = section('  void _editLessonSlotModal(', '  Widget _buildGradesTab(')
        for removed in ['suggestions', 'roomCtrl', 'Occuperà', '[1, 2, 3]', '($span slot)']:
            self.assertNotIn(removed, editor)
        self.assertIn('children: [1, 2].map', editor)
        self.assertIn('return count.clamp(1, 2)', editor)
        self.assertIn("'${_dayNames[weekday]} · ${idx + 1}ª ora'", editor)

    def test_event_editor_no_defaults_notes_or_priority(self):
        editor = section('  void _showEventModal(', '  void _showAddGradeModal(')
        self.assertIn("existing?.subject ?? ''", editor)
        self.assertNotIn('notesCtrl', editor)
        self.assertNotIn('highPriority:', editor)
        self.assertNotIn('Alta priorità', SOURCE)
        self.assertNotIn('Segna come alta priorità', SOURCE)

    def test_settings_contains_both_sections(self):
        self.assertIn("label: 'Impostazioni'", SOURCE)
        settings = section('class _SettingsTabState', 'class _DashedRRectPainter')
        self.assertIn("Text('Sincronizzazione Argo'", settings)
        self.assertIn("Text('Notifiche'", settings)
        self.assertIn('onChanged: widget.onToggleNotify', settings)

    def test_notification_icon_is_transparent_vector_and_packaged(self):
        icon = ROOT / 'resources/android/drawable/ic_stat_school.xml'
        tree = ET.parse(icon)
        ns = '{http://schemas.android.com/apk/res/android}'
        self.assertEqual(tree.getroot().find('path').attrib[ns + 'fillColor'], '#FFFFFFFF')
        self.assertIn("icon: 'ic_stat_school'", SOURCE)
        workflow = (ROOT / '.github/workflows/build-apk.yml').read_text()
        self.assertTrue('resources/android/drawable/ic_stat_school.xml' in workflow or
                        'render_stat_icon(px).save(os.path.join(dpath, "ic_stat_school.png")' in workflow)


if __name__ == '__main__':
    unittest.main()
