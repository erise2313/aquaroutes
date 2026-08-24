import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final String supabaseUrl;
  final String supabaseAnonKey;

  if (kIsWeb) {
    // flutter_dotenv's runtime asset fetch (rootBundle.loadString) works in
    // debug web builds but is unreliable in optimized release builds --
    // dotenv.env ends up empty even though the .env asset itself loads
    // successfully (a load-order/timing difference between the debug and
    // release web compilers, not a missing-file problem). Compile-time
    // dart-define values are the reliable path for web instead. Build with:
    // flutter build web --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
    supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
    supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL/SUPABASE_ANON_KEY were not provided at build time. '
        'Rebuild with --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
      );
    }
  } else {
    await dotenv.load(fileName: '.env');
    supabaseUrl = dotenv.env['SUPABASE_URL']!;
    supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY']!;
  }

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
  );

  // TEMPORARY debug workaround: force every launch to start fully signed
  // out instead of resuming a persisted session. Investigating a crash
  // that appears tied to relaunching while still logged in (possibly a
  // driver account resuming ON-DUTY GPS tracking on startup) -- this
  // sidesteps that path entirely while we isolate the real cause. Remove
  // once the crash is root-caused; don't ship this to a real build.
  await Supabase.instance.client.auth.signOut();

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GenTri: WASA',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}
