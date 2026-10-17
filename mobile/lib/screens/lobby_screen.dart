import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/game_models.dart';
import '../services/game_service.dart';
import '../services/sound_fx.dart';
import 'admin_screen.dart';
import 'login_screen.dart';
import 'table_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    GameService.instance.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    GameService.instance.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _showPlayerHistorySheet() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A2419),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return FutureBuilder<Map<String, dynamic>>(
          future: GameService.instance.fetchMyHistory(),
          builder: (ctx, snap) {
            final stats = snap.data?['stats'] as Map<String, dynamic>? ?? {};
            final txs = List<Map<String, dynamic>>.from(
              snap.data?['transactions'] ?? [],
            );

            return SizedBox(
              height: MediaQuery.sizeOf(ctx).height * 0.72,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '📜 Oyun & Kredi Geçmişim',
                          style: TextStyle(
                            color: Color(0xFFFDE047),
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (snap.connectionState == ConnectionState.waiting)
                      const Expanded(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFD4AF37),
                          ),
                        ),
                      )
                    else ...[
                      // Özet İstatistik Kartları
                      Row(
                        children: [
                          Expanded(
                            child: _buildMiniStatBox(
                              'Oynanan Maç',
                              '${stats['totalGames'] ?? 0}',
                              const Color(0xFF38BDF8),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMiniStatBox(
                              'Şampiyonluk',
                              '${stats['totalWins'] ?? 0} 🏆',
                              const Color(0xFF10B981),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMiniStatBox(
                              'Kazanılan Ödül',
                              '${stats['totalWonCredits'] ?? 0} 🪙',
                              const Color(0xFFFDE047),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Son Kredi ve Masa Hareketleri',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const Divider(color: Colors.white24),
                      Expanded(
                        child: txs.isEmpty
                            ? const Center(
                                child: Text(
                                  'Henüz kayıtlı bir kredi veya oyun hareketiniz yok.',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              )
                            : ListView.builder(
                                itemCount: txs.length,
                                itemBuilder: (_, i) {
                                  final tx = txs[i];
                                  final amt =
                                      int.tryParse(tx['amount'].toString()) ?? 0;
                                  final isPos = amt >= 0;
                                  final rawDate =
                                      tx['created_at']?.toString() ?? '';
                                  final shortDate = rawDate.length >= 16
                                      ? rawDate
                                          .substring(0, 16)
                                          .replaceAll('T', ' ')
                                      : rawDate;

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black26,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isPos
                                            ? const Color(0xFF10B981)
                                                .withValues(alpha: 0.4)
                                            : Colors.white12,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isPos
                                              ? Icons.add_circle_outline
                                              : Icons.remove_circle_outline,
                                          color: isPos
                                              ? const Color(0xFF10B981)
                                              : Colors.orangeAccent,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                tx['description']?.toString() ??
                                                    '',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              Text(
                                                shortDate,
                                                style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          '${isPos ? '+$amt' : '$amt'} 🪙',
                                          style: TextStyle(
                                            color: isPos
                                                ? const Color(0xFF10B981)
                                                : Colors.redAccent,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMiniStatBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Future<void> _showSettingsDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0E2F21),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
          ),
          title: const Text(
            '⚙️ Ses ve Oyun Ayarları',
            style: TextStyle(
              color: Color(0xFFFDE047),
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                activeThumbColor: const Color(0xFFD4AF37),
                title: const Text(
                  '🔊 Kart & Geri Sayım Sesleri',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                subtitle: const Text(
                  'Kağıt çekme/atma ve son 5 sn uyarı sesi',
                  style: TextStyle(color: Colors.white54, fontSize: 11.5),
                ),
                value: SoundFx.soundEnabled,
                onChanged: (val) async {
                  await SoundFx.setSoundEnabled(val);
                  if (val) SoundFx.playCardTap();
                  setDialogState(() {});
                },
              ),
              SwitchListTile(
                activeThumbColor: const Color(0xFFD4AF37),
                title: const Text(
                  '🎙️ Bas-Konuş Sesli Sohbet',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                subtitle: const Text(
                  'Masadaki telsiz sesli iletişimi aç/kapat',
                  style: TextStyle(color: Colors.white54, fontSize: 11.5),
                ),
                value: SoundFx.voiceEnabled,
                onChanged: (val) async {
                  await SoundFx.setVoiceEnabled(val);
                  setDialogState(() {});
                },
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Tamam',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateTableDialog() async {
    final user = GameService.instance.currentUser;
    final nameCtrl = TextEditingController(
      text: '${user?.username ?? 'VIP'} Masası',
    );
    final feeCtrl = TextEditingController(text: '200');
    int maxPlayers = 4;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0E2F21),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFD4AF37), width: 1.8),
          ),
          title: const Text(
            '🃏 Yeni Oyun Masası Kur',
            style: TextStyle(
              color: Color(0xFFFDE047),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Masa Adı',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon:
                        const Icon(Icons.table_bar, color: Color(0xFFD4AF37)),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Masa Kapasitesi (Min 2 - Maks 6 Oyuncu):',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [2, 3, 4, 5, 6].map((cnt) {
                    final sel = cnt == maxPlayers;
                    return ChoiceChip(
                      label: Text('$cnt Kişilik'),
                      selected: sel,
                      selectedColor: const Color(0xFFD4AF37),
                      labelStyle: TextStyle(
                        color: sel ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      backgroundColor: const Color(0xFF143D2B),
                      onSelected: (_) =>
                          setDialogState(() => maxPlayers = cnt),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Oyun Giriş Kredisi (Kişi Başı 1x):',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [50, 100, 250, 500, 1000, 2500].map((preset) {
                    return ActionChip(
                      backgroundColor: const Color(0xFF143D2B),
                      label: Text(
                        '$preset 🪙',
                        style: const TextStyle(color: Color(0xFFFDE047)),
                      ),
                      onPressed: () => feeCtrl.text = '$preset',
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: feeCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Giriş Kredisi Miktarı',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.monetization_on,
                        color: Color(0xFFD4AF37)),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'ℹ️ Oyuncular masadan ayrıldığında özel kurulan masa otomatik kapanır. Oyun sonunda potun %5\'i kasaya, %95\'i şampiyona gider.',
                  style: TextStyle(color: Colors.white54, fontSize: 11.5),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final fee = int.tryParse(feeCtrl.text.trim()) ?? 100;
                try {
                  final tableId = await GameService.instance.createTable(
                    name: nameCtrl.text.trim(),
                    maxPlayers: maxPlayers,
                    entryFee: fee,
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  _openTable(tableId);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString()),
                      backgroundColor: Colors.red.shade800,
                    ),
                  );
                }
              },
              child: const Text(
                'Masayı Kur ve Gir',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAvatarPickerDialog() async {
    final user = GameService.instance.currentUser;
    if (user == null) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0E2F21),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
        ),
        title: const Text(
          '🎭 Kulüp Avatarınızı Seçin',
          style: TextStyle(color: Color(0xFFFDE047), fontSize: 17),
        ),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: VipAvatar.all.map((av) {
            final selected = av.key == user.avatar;
            return InkWell(
              onTap: () async {
                await GameService.instance.updateAvatar(av.key);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Container(
                width: 86,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF1A4D36) : Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? const Color(0xFFFDE047) : Colors.white24,
                    width: selected ? 2.2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(av.emoji, style: const TextStyle(fontSize: 30)),
                    const SizedBox(height: 4),
                    Text(
                      av.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _openTable(String tableId) async {
    GameService.instance.enterTable(tableId);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TableScreen(tableId: tableId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = GameService.instance;
    final user = service.currentUser;
    final avatar = VipAvatar.fromKey(user?.avatar);
    final tables = service.lobbyTables;

    return Scaffold(
      backgroundColor: const Color(0xFF05160F),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. ÜST PROFİL, KREDİ VE HIZLI MENÜ BARI
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0E3524), Color(0xFF071D13)],
                ),
                border: Border(
                  bottom: BorderSide(color: Color(0xFFD4AF37), width: 1.5),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Oyuncu Avatarı & İsim
                      Expanded(
                        child: InkWell(
                          onTap: _showAvatarPickerDialog,
                          borderRadius: BorderRadius.circular(30),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black38,
                                  border: Border.all(
                                    color: const Color(0xFFD4AF37),
                                    width: 1.8,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    avatar.emoji,
                                    style: const TextStyle(fontSize: 23),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user?.username ?? 'Oyuncu',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15.5,
                                      ),
                                    ),
                                    Text(
                                      user?.isAdmin == true
                                          ? '👑 Kulüp Yöneticisi'
                                          : '✨ VIP Kulüp Üyesi',
                                      style: const TextStyle(
                                        color: Color(0xFFFDE047),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Kredi Rozeti (Tıklanınca Geçmişi Açar)
                      InkWell(
                        onTap: _showPlayerHistorySheet,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1E3A2F), Color(0xFF0F241C)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFFACC15),
                              width: 1.4,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('🪙', style: TextStyle(fontSize: 14)),
                              const SizedBox(width: 5),
                              Text(
                                '${user?.credits ?? 0}',
                                style: const TextStyle(
                                  color: Color(0xFFFDE047),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Geçmişim Butonu
                      IconButton(
                        tooltip: 'Oyun & Kredi Geçmişim',
                        visualDensity: VisualDensity.compact,
                        onPressed: _showPlayerHistorySheet,
                        icon: const Icon(
                          Icons.history,
                          color: Color(0xFFFDE047),
                        ),
                      ),

                      // Ses & Oyun Ayarları Butonu
                      IconButton(
                        tooltip: 'Ses ve Oyun Ayarları',
                        visualDensity: VisualDensity.compact,
                        onPressed: _showSettingsDialog,
                        icon: const Icon(Icons.settings, color: Colors.white70),
                      ),

                      // Çıkış Butonu
                      IconButton(
                        tooltip: 'Çıkış Yap',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          service.logout();
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.logout, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // AKSİYON BUTONLARI SATIRI
                  Row(
                    children: [
                      if (user?.isAdmin == true) ...[
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7E22CE),
                                foregroundColor: Colors.white,
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(
                                    color: Color(0xFFD8B4FE),
                                    width: 1,
                                  ),
                                ),
                              ),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const AdminScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.admin_panel_settings,
                                size: 18,
                              ),
                              label: const Text(
                                'YÖNETİM PANELİ',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD4AF37),
                              foregroundColor: Colors.black,
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _showCreateTableDialog,
                            icon: const Icon(Icons.add_circle, size: 18),
                            label: const Text(
                              'YENİ MASA KUR',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 2. OYUN KULÜBÜ VİTRİNİ
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: SizedBox(
                height: 62,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildGameHubChip(
                      icon: '🃏',
                      title: 'Yunan Yanık VIP',
                      subtitle: '${tables.length} Açık Masa',
                      isActive: true,
                      onTap: () {},
                    ),
                    _buildGameHubChip(
                      icon: '🎲',
                      title: '101 Okey VIP',
                      subtitle: 'Yakında',
                      isActive: false,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('101 Okey VIP çok yakında kulüpte!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                    _buildGameHubChip(
                      icon: '♠️',
                      title: 'Batak HD Kulüp',
                      subtitle: 'Yakında',
                      isActive: false,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Batak HD Kulüp çok yakında eklenecek!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // 3. CANLI MASALAR BAŞLIĞI
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '🟢 CANLI YUNAN YANIK MASALARI',
                    style: TextStyle(
                      color: Color(0xFFFDE047),
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 0.7,
                    ),
                  ),
                  Text(
                    '${tables.length} Masa Açık',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),

            // 4. CANLI MASALAR LİSTESİ
            Expanded(
              child: tables.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('🃏', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 10),
                          const Text(
                            'Şu anda açık masa yok. İlk masayı sen kur!',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 15),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD4AF37),
                              foregroundColor: Colors.black,
                            ),
                            onPressed: _showCreateTableDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('Yeni Masa Kur'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      itemCount: tables.length,
                      itemBuilder: (ctx, i) {
                        final t = tables[i];
                        final isPlaying = t.status == 'playing' ||
                            t.status == 'round_summary';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF124630), Color(0xFF082217)],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isPlaying
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFD4AF37)
                                      .withValues(alpha: 0.8),
                              width: 1.6,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: InkWell(
                            onTap: () => _openTable(t.id),
                            borderRadius: BorderRadius.circular(18),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          t.name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15.5,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isPlaying
                                              ? const Color(0xFF059669)
                                              : const Color(0xFFD97706),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          isPlaying
                                              ? '🔥 El #${t.roundNumber}'
                                              : '⏳ Bekliyor',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black38,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'Giriş: ${t.entryFee} 🪙',
                                          style: const TextStyle(
                                            color: Color(0xFFFDE047),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black26,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'Oyuncu: ${t.seatedCount}/${t.maxPlayers}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      if (t.pot > 0)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF065F46),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '🏆 Pot: ${t.pot} 🪙',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  Row(
                                    children: [
                                      Expanded(
                                        child: Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: List.generate(t.maxPlayers,
                                              (seatIdx) {
                                            final occupant = t.players
                                                .cast<Map<String, dynamic>?>()
                                                .firstWhere(
                                                  (p) =>
                                                      p?['seatIndex'] == seatIdx,
                                                  orElse: () => null,
                                                );
                                            final av = occupant != null
                                                ? VipAvatar.fromKey(
                                                    occupant['avatar']
                                                        ?.toString(),
                                                  )
                                                : null;
                                            return Container(
                                              width: 30,
                                              height: 30,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: occupant != null
                                                    ? const Color(0xFF1E3A2F)
                                                    : Colors.black26,
                                                border: Border.all(
                                                  color: occupant != null
                                                      ? const Color(0xFFFDE047)
                                                      : Colors.white24,
                                                ),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  av != null ? av.emoji : '🪑',
                                                  style: const TextStyle(
                                                      fontSize: 14),
                                                ),
                                              ),
                                            );
                                          }),
                                        ),
                                      ),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFFD4AF37),
                                          foregroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 8,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                        ),
                                        onPressed: () => _openTable(t.id),
                                        icon:
                                            const Icon(Icons.login, size: 16),
                                        label: const Text(
                                          'MASAYA GİR',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameHubChip({
    required String icon,
    required String title,
    required String subtitle,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  colors: [Color(0xFF1A563B), Color(0xFF0E3322)],
                )
              : null,
          color: isActive ? null : Colors.black26,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? const Color(0xFFFACC15) : Colors.white24,
            width: isActive ? 1.8 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: isActive ? const Color(0xFFFDE047) : Colors.white38,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
