import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/game_service.dart';
import 'lobby_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUser = prefs.getString('saved_username');
    if (savedUser != null && savedUser.isNotEmpty) {
      _usernameCtrl.text = savedUser;
      if (mounted) setState(() => _loading = true);
    }

    final autoLogged = await GameService.instance.tryAutoLogin();
    if (!mounted) return;
    if (autoLogged) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LobbyScreen()),
      );
      return;
    }
    setState(() => _loading = false);
  }

  Future<void> _handleLogin() async {
    final uname = _usernameCtrl.text.trim();
    final pass = _passwordCtrl.text;

    if (uname.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Lütfen kullanıcı adı ve şifrenizi girin.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await GameService.instance.login(
        uname,
        pass,
        rememberMe: _rememberMe,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LobbyScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      body: Container(
        width: size.width,
        height: size.height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0E3A27),
              Color(0xFF071F15),
              Color(0xFF030D08),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ÜST OYUN LOGOSU (PROFESYONEL 3D KRALİYET ARMASI)
                    Container(
                      width: 146,
                      height: 146,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: const Color(0xFFD4AF37),
                          width: 2.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFD4AF37).withValues(alpha: 0.45),
                            blurRadius: 30,
                            spreadRadius: 3,
                          ),
                          const BoxShadow(
                            color: Colors.black87,
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: Image.asset(
                          'assets/images/game_logo.jpg',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'YUNAN YANIK VIP',
                      style: TextStyle(
                        color: Color(0xFFFDE047),
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // GİRİŞ FORMU KARTI
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A2419).withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0xFFD4AF37).withValues(alpha: 0.75),
                          width: 1.6,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.65),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Üye Girişi',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Kulüp hesabınızla oyun salonuna bağlanın',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          const SizedBox(height: 20),

                          if (_error != null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.red.shade900.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.redAccent),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    color: Colors.redAccent,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          TextField(
                            controller: _usernameCtrl,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(color: Colors.white, fontSize: 15),
                            decoration: InputDecoration(
                              labelText: 'Kullanıcı Adı',
                              labelStyle: const TextStyle(color: Colors.white70),
                              prefixIcon: const Icon(
                                Icons.person_outline,
                                color: Color(0xFFD4AF37),
                              ),
                              filled: true,
                              fillColor: Colors.black26,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Colors.white24),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD4AF37),
                                  width: 1.8,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          TextField(
                            controller: _passwordCtrl,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            style: const TextStyle(color: Colors.white, fontSize: 15),
                            decoration: InputDecoration(
                              labelText: 'Şifre',
                              labelStyle: const TextStyle(color: Colors.white70),
                              prefixIcon: const Icon(
                                Icons.lock_outline,
                                color: Color(0xFFD4AF37),
                              ),
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() => _obscurePassword = !_obscurePassword);
                                },
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: Colors.white60,
                                ),
                              ),
                              filled: true,
                              fillColor: Colors.black26,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Colors.white24),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD4AF37),
                                  width: 1.8,
                                ),
                              ),
                            ),
                            onSubmitted: (_) => _handleLogin(),
                          ),
                          const SizedBox(height: 10),

                          Row(
                            children: [
                              Checkbox(
                                value: _rememberMe,
                                activeColor: const Color(0xFFD4AF37),
                                checkColor: Colors.black,
                                onChanged: (v) {
                                  setState(() => _rememberMe = v ?? true);
                                },
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() => _rememberMe = !_rememberMe);
                                },
                                child: const Text(
                                  'Beni Hatırla',
                                  style: TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD4AF37),
                                foregroundColor: Colors.black,
                                elevation: 6,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: _loading ? null : _handleLogin,
                              child: _loading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.6,
                                        color: Colors.black,
                                      ),
                                    )
                                  : const Text(
                                      'OYUN SALONUNA GİR',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15.5,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
