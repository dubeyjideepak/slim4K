import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Slim4KApp());
}

class Slim4KApp extends StatelessWidget {
  const Slim4KApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Slim4K - 10x 4K Video Compressor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090D13),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF7C4DFF),
          surface: Color(0xFF161B22),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D1117),
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
