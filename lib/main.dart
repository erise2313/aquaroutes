import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth/login_screen.dart'; // Ensure this points to your actual login screen file

Future<void> main() async {
  // 1. Ensure Flutter bindings are initialized before calling async code
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize the Supabase connection
  await Supabase.initialize(
    url: 'https://kdptnxvspqunjngaduok.supabase.co',
    publishableKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtkcHRueHZzcHF1bmpuZ2FkdW9rIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIyMTQyNzgsImV4cCI6MjA5Nzc5MDI3OH0.DCiZ07Bz-nqTl0k-lKb38U1QFq8CLGIywhbnbFGUygA',
  );

  // 3. Run the app
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AquaRoutes',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      // Route directly to the Login Screen on startup
      home: const LoginScreen(),
    );
  }
}
