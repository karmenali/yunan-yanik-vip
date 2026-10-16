import 'package:flutter/material.dart';
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
  String? _error;

  Future<void> _handleLogin() async {
    if (_usernameCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Lütfen kullanıcı adı ve şifrenizi girin.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await GameService.instance.login(
        _usernameCtrl.text.trim(),
        _passwordCtrl.text,
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

  Future<void> _showServerConfigDialog() async {
    final urlCtrl = TextEditingController(text: GameService.instance.serverUrl);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0E2F21),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
        ),
        title: const Text(
          '🌐 Linux Oyun Sunucusu Adresi',
          style: TextStyle(color: Color(0xFFFDE047), fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Örnek: http://SUNUCU_IP_ADRESINIZ:4545',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: urlCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Sunucu URL',
                  labelStyle: TextStyle(color: Colors.white70),
                  prefixIcon: Icon(Icons.dns, color: Color(0xFFD4AF37)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              await GameService.instance.setServerUrl(urlCtrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.1,
            colors: [
              Color(0xFF0F3D29),
              Color(0xFF061A12),
              Color(0xFF020C08),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Sağ üst Sunucu Ayarı Butonu
            Positioned(
              top: 16,
              right: 20,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFDE047),
                  side: const BorderSide(color: Color(0xFFD4AF37)),
                ),
                onPressed: _showServerConfigDialog,
                icon: const Icon(Icons.settings_ethernet, size: 18),
                label: Text(
                  'Sunucu: ${GameService.instance.serverUrl}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),

            // Merkez VIP Giriş Kartı
            Center(
              child: SingleChildScrollView(
                child: Container(
                  width: 440,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A261A).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFD4AF37), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.7),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('♠️ ♥️ ', style: TextStyle(fontSize: 22)),
                          Text(
                            'YUNAN YANIK VIP',
                            style: TextStyle(
                              color: Color(0xFFFDE047),
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          Text(' ♣️ ♦️', style: TextStyle(fontSize: 22)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Özel Kurallı Çok Oyunculu Kulüp Salonu',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 16),

                      if (_error != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade900.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.redAccent),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      TextField(
                        controller: _usernameCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Kullanıcı Adı',
                          labelStyle: const TextStyle(color: Colors.white70),
                          prefixIcon: const Icon(Icons.person, color: Color(0xFFD4AF37)),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Şifre',
                          labelStyle: const TextStyle(color: Colors.white70),
                          prefixIcon: const Icon(Icons.lock, color: Color(0xFFD4AF37)),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onSubmitted: (_) => _handleLogin(),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD4AF37),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _loading ? null : _handleLogin,
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.black,
                                  ),
                                )
                              : const Text(
                                  'SALONA GİRİŞ YAP',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          ActionChip(
                            backgroundColor: const Color(0xFF143D2B),
                            label: const Text(
                              '👑 Admin',
                              style: TextStyle(color: Color(0xFFFDE047), fontSize: 11),
                            ),
                            onPressed: () {
                              _usernameCtrl.text = 'admin';
                              _passwordCtrl.text = 'admin123456';
                            },
                          ),
                          ActionChip(
                            backgroundColor: const Color(0xFF143D2B),
                            label: const Text(
                              '🦁 Oyuncu 1',
                              style: TextStyle(color: Colors.white, fontSize: 11),
                            ),
                            onPressed: () {
                              _usernameCtrl.text = 'oyuncu1';
                              _passwordCtrl.text = '123456';
                            },
                          ),
                          ActionChip(
                            backgroundColor: const Color(0xFF143D2B),
                            label: const Text(
                              '👸 Oyuncu 2',
                              style: TextStyle(color: Colors.white, fontSize: 11),
                            ),
                            onPressed: () {
                              _usernameCtrl.text = 'oyuncu2';
                              _passwordCtrl.text = '123456';
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
