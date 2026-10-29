import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'screens/mk20_diagnostics_screen.dart';
import 'screens/upload_screen.dart';
import 'screens/analysis_screen.dart';
import 'screens/preset_list_screen.dart';
import 'screens/preset_editor_screen.dart';
import 'screens/transfer_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tone_comparison_screen.dart';
import 'screens/mk300_pilot_screen.dart';
import 'screens/pedal_reference_screen.dart';
import 'services/api_service.dart';
import 'services/preset_store.dart';
import 'theme/app_theme.dart';
import 'models/preset_pair.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiService();
  await api.loadSettings();
  runApp(
    MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider(create: (_) => PresetStore()),
      ],
      child: const AiToneStudioApp(),
    ),
  );
}

class AiToneStudioApp extends StatelessWidget {
  const AiToneStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Tone Studio',
      theme: AppTheme.dark(),
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/pedal-reference':
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
                builder: (_) =>
                    PedalReferenceScreen(pairId: args['pair_id'] as String));
          case '/mk20-diagnostics':
            return MaterialPageRoute(
                builder: (_) => const Mk20DiagnosticsScreen());
          case '/mk300-pilot':
            return MaterialPageRoute(builder: (_) => const Mk300PilotScreen());
          case '/':
            return MaterialPageRoute(builder: (_) => const HomeScreen());
          case '/upload':
            final args = settings.arguments as Map<String, dynamic>? ?? {};
            return MaterialPageRoute(
                builder: (_) => UploadScreen(
                      initialArtist: args['artist'] as String?,
                      initialSongTitle: args['song_title'] as String?,
                      initialRhythmDevice:
                          args['rhythm_device'] as String? ?? 'MK300',
                      initialLeadDevice:
                          args['lead_device'] as String? ?? 'MK300',
                    ));
          case '/analysis':
            final args = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              builder: (_) =>
                  AnalysisScreen(jobId: args?['job_id'] as String? ?? ''),
            );
          case '/presets':
            final args = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              builder: (_) =>
                  PresetListScreen(pairId: args?['pair_id'] as String? ?? ''),
            );
          case '/editor':
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (_) => PresetEditorScreen(
                preset: args['preset'] as PresetData,
                pairId: args['pair_id'] as String,
              ),
            );
          case '/transfer':
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (_) => TransferScreen(
                  pairId: args['pair_id'] as String,
                  initialRole: args['role'] as String?),
            );
          case '/compare':
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
                builder: (_) => ToneComparisonScreen(
                    pairId: args['pair_id'] as String,
                    initialRole: args['role'] as String? ?? 'lead'));
          case '/settings':
            return MaterialPageRoute(builder: (_) => const SettingsScreen());
          default:
            return MaterialPageRoute(builder: (_) => const HomeScreen());
        }
      },
    );
  }
}
