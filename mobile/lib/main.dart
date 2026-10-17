import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/login_screen.dart';
import 'services/game_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // İlk giriş ve Lobi dikey (Portrait) tam ekran olarak başlar,
  // Oyun masasına girildiğinde otomatik Yatay (Landscape) moda geçer.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF04120C),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  await GameService.instance.init();

  runApp(const YunanYanikVipApp());
}

class YunanYanikVipApp extends StatelessWidget {
  const YunanYanikVipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VIP Oyun Kulübü',
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
