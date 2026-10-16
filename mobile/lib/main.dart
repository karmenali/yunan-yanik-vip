import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/login_screen.dart';
import 'services/game_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Tam ekran Yatay (Landscape) Mod
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  await GameService.instance.init();

  runApp(const YunanYanikVipApp());
}

class YunanYanikVipApp extends StatelessWidget {
  const YunanYanikVipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yunan Yanık VIP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF05160F),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD4AF37),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}
