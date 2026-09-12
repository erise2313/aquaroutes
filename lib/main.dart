import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

import 'constants/app_theme.dart';
import 'constants/web_theme.dart';
import 'providers/app_theme_provider.dart';
import 'providers/web_theme_provider.dart';
import 'screens/auth/auth_gate.dart';
import 'web_router.dart';

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

  runApp(const ProviderScope(child: MyApp()));
}

/// True only for the public website build. The admin portal
/// (--dart-define=PORTAL=admin) and the mobile app are deliberately excluded
/// from URL routing: admin having shareable, indexable URLs works against
/// keeping it hidden, and the app has no address bar to benefit.
const _isPublicWebsite = kIsWeb && String.fromEnvironment('PORTAL') != 'admin';

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  // Built once and held: rebuilding a GoRouter on every theme toggle would
  // reset the navigation stack.
  final GoRouter? _router = _isPublicWebsite ? buildWebRouter() : null;

  @override
  Widget build(BuildContext context) {
    final webMode = ref.watch(webThemeProvider);

    if (_router != null) {
      return MaterialApp.router(
        title: 'GenTri: WASA',
        theme: WebTheme.light,
        darkTheme: WebTheme.dark,
        themeMode: webMode.material,
        routerConfig: _router,
      );
    }

    // The app (not the website) follows the phone's light/dark setting, with
    // a Light/Dark/Follow-phone override in Account settings. The website
    // keeps its own manual switch above: it paints its own warm-paper and
    // navy surfaces, so inheriting the OS preference there produced dark
    // Material text on light backgrounds rather than a designed dark mode.
    final appMode = ref.watch(appThemeProvider);
    return MaterialApp(
      title: 'GenTri: WASA',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: appMode.material,
      home: const AuthGate(),
    );
  }
}
