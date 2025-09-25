import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'pages/select_session_page.dart';
import 'pages/history_page.dart';
import 'pages/settings_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ContagemApp());
}

class ContagemApp extends StatelessWidget {
  const ContagemApp({super.key});

  @override
  Widget build(BuildContext context) {
    final seed = const Color(0xFF4F46E5);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Contagem de Garrafas',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          background: const Color(0xFFF6F7FB),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Color(0xFF4F46E5),
          foregroundColor: Colors.white,
        ),
        cardTheme: CardTheme(
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 0),
          elevation: 4,
          shadowColor: Colors.black.withOpacity(0.1),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: const HomePage(),
      routes: {
        '/start': (_) => const SelectSessionPage(),
        '/history': (_) => const HistoryPage(),
        '/settings': (_) => const SettingsPage(),
      },
    );
  }
}
