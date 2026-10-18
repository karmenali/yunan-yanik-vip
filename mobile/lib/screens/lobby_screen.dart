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
  // 0: Ana Menü (Dashboard), 1: Odalara Katıl
  int _currentView = 0;

  // Odalara Katıl Filtreleri
  String _selectedTab = 'assisted'; // 'assisted' (Yardımlı) veya 'unassisted' (Yardımsız)
  int _selectedCapacityFilter = 0; // 0: Tümü, 2, 3, 4, 5: 5+

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

  // ===========================================================================
  // 📖 OYUN KURALLARI (TEMİZ & NET YANIK İSKAMBİL KURALLARI)
  // ===========================================================================
  Future<void> _showRulesSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A2419),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.78,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '📖 Oyun Kuralları',
                      style: TextStyle(
                        color: Color(0xFFFDE047),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
                const Divider(color: Colors.white24),
                Expanded(
                  child: ListView(
                    children: [
                      _buildRuleCard(
                        '🃏 106 Kağıt & 3 Sıralı Istaka Düzeni',
                        'Oyun 2 tam deste (104 kağıt) + 2 Fiziksel Joker olmak üzere toplam 106 kağıtla oynanır. '
                            'Her oyuncuya 10\'ar kağıt dağıtılır. Kağıtlarınızı ekrandaki 3 yatay sırada parmağınızla serbestçe dizebilirsiniz.',
                      ),
                      _buildRuleCard(
                        '👑 Gösterge Jokeri (Wild Card)',
                        'Dağıtım sonunda açılan Gösterge kağıdı ile aynı sayıdaki tüm kağıtlar (ve 2 fiziksel Joker) o el boyunca JOKER yerine geçer. '
                            'Elinizde per yapmadan kalan Joker 25 ceza puanı yazar.',
                      ),
                      _buildRuleCard(
                        '✨ Yardımlı Mod vs 🔥 Yardımsız Mod',
                        '• Yardımlı Mod: Geçerli perleriniz (✓ PER) ve elinizdeki ceza puanı otomatik olarak canlı gösterilir.\n'
                            '• Yardımsız Mod: Hiçbir per veya ceza ipucu verilmez! DİKKAT: Yardımsız modda hatalı el açan oyuncu DİREKT YANMIŞ SAYILIR ve o maç için yeniden giriş (Re-buy) hakkını tamamen kaybeder!',
                      ),
                      _buildRuleCard(
                        '🔍 Şeffaf El Açma & Ceza İşleme',
                        'Bir oyuncu geçerli 10 kağıdını yere açtığında, açtığı perler masanın ortasında 10 saniye boyunca herkese açık şeffaf biçimde gösterilir. '
                            'Ardından diğer oyuncuların ellerinde kalan kağıtlar sırayla açılarak ceza puanları işlenir.',
                      ),
                      _buildRuleCard(
                        '🔥 101 Barajı & Yeniden Giriş (Re-buy)',
                        'Toplam ceza puanı 101 veya üzerine çıkan oyuncu yanar. '
                            'Masada en az 2 oyuncu devam ediyorsa, elenen oyuncu katlanarak (1x, 2x, 3x) masa ücreti ödeyip en yüksek puanlı oyuncunun puanıyla oyuna geri dönebilir.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRuleCard(String title, String body) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFFDE047),
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 🔔 BİLDİRİMLER & DAVETLER MODALI
  // ===========================================================================
  Future<void> _showNotificationsSheet() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A2419),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '🔔 Bildirimler & Davetler',
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
              const Divider(color: Colors.white24),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mark_chat_unread, color: Color(0xFFFDE047)),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hoş Geldiniz!',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Arkadaşlarınızı oyuna davet edebilir ve anlık oyun odası bildirimleri alabilirsiniz.',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // 👥 ARKADAŞLAR & OYUNA DAVET MODALI
  // ===========================================================================
  Future<void> _showFriendsSheet() async {
    final friendAddCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A2419),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            top: 18,
            left: 18,
            right: 18,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '👥 Arkadaşlar & Davet',
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
                const Divider(color: Colors.white24),
                const SizedBox(height: 8),

                // Arkadaş Ekleme Inputu
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: friendAddCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Kullanıcı adı ile arkadaş ekle...',
                          hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                          prefixIcon: const Icon(Icons.person_add, color: Color(0xFFD4AF37), size: 18),
                          filled: true,
                          fillColor: Colors.black38,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFD4AF37)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4AF37),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        if (friendAddCtrl.text.trim().isNotEmpty) {
                          final name = friendAddCtrl.text.trim();
                          friendAddCtrl.clear();
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('$name kullanıcısına arkadaşlık isteği gönderildi! 📲'),
                              backgroundColor: const Color(0xFF059669),
                            ),
                          );
                        }
                      },
                      child: const Text('Ekle', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                const Text(
                  'Çevrimiçi Oyuncular & Arkadaşlar:',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
                const SizedBox(height: 8),

                Expanded(
                  child: ListView(
                    children: [
                      _buildFriendTile('Ahmet_Usta', 'lion', true),
                      _buildFriendTile('Merve_Kralice', 'queen', true),
                      _buildFriendTile('Emre_99', 'wolf', false),
                      _buildFriendTile('Mehmet_VIP', 'king', true),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFriendTile(String username, String avatarKey, bool isOnline) {
    final avatar = VipAvatar.fromKey(avatarKey);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Text(avatar.emoji, style: const TextStyle(fontSize: 22)),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOnline ? const Color(0xFF10B981) : Colors.grey,
                    border: Border.all(color: Colors.black, width: 1.2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  isOnline ? 'Çevrimiçi' : 'Çevrimdışı',
                  style: TextStyle(
                    color: isOnline ? const Color(0xFF34D399) : Colors.white38,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isOnline ? const Color(0xFF10B981) : Colors.white12,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: isOnline
                ? () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('$username telefonuna oyun davet bildirimi gönderildi! 📲'),
                        backgroundColor: const Color(0xFF059669),
                      ),
                    );
                  }
                : null,
            icon: const Icon(Icons.send_rounded, size: 14),
            label: const Text('Davet Et', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 📜 OYUNCU İSTATİSTİKLERİ VE HAREKETLERİ
  // ===========================================================================
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
                          child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
                        ),
                      )
                    else ...[
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
                        'Son Kredi ve Oyun Hareketleri',
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
                                  final amt = int.tryParse(tx['amount'].toString()) ?? 0;
                                  final isPos = amt >= 0;
                                  final rawDate = tx['created_at']?.toString() ?? '';
                                  final shortDate = rawDate.length >= 16
                                      ? rawDate.substring(0, 16).replaceAll('T', ' ')
                                      : rawDate;

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.black26,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isPos
                                            ? const Color(0xFF10B981).withValues(alpha: 0.4)
                                            : Colors.white12,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isPos ? Icons.add_circle_outline : Icons.remove_circle_outline,
                                          color: isPos ? const Color(0xFF10B981) : Colors.orangeAccent,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                tx['description']?.toString() ?? '',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              Text(
                                                shortDate,
                                                style: const TextStyle(color: Colors.white54, fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          '${isPos ? '+$amt' : '$amt'} 🪙',
                                          style: TextStyle(
                                            color: isPos ? const Color(0xFF10B981) : Colors.redAccent,
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
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15),
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

  // ===========================================================================
  // ⚙️ SES VE OYUN AYARLARI
  // ===========================================================================
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
            style: TextStyle(color: Color(0xFFFDE047), fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                activeThumbColor: const Color(0xFFD4AF37),
                title: const Text('🔊 Kart & Efekt Sesleri', style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text('Kağıt çekme/atma ve bildirim sesleri', style: TextStyle(color: Colors.white54, fontSize: 11.5)),
                value: SoundFx.soundEnabled,
                onChanged: (val) async {
                  await SoundFx.setSoundEnabled(val);
                  if (val) SoundFx.playCardTap();
                  setDialogState(() {});
                },
              ),
              SwitchListTile(
                activeThumbColor: const Color(0xFFD4AF37),
                title: const Text('🎙️ Sesli Sohbet Dinleme', style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text('Odadaki canlı sesli iletişimi aç/kapat', style: TextStyle(color: Colors.white54, fontSize: 11.5)),
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
              child: const Text('Tamam', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 🃏 OYUN ODASI AÇ MODALI (GÖRSEL 1 REFERANSIYLA SADELEŞTİRİLMİŞ)
  // ===========================================================================
  Future<void> _showCreateTableDialog() async {
    final user = GameService.instance.currentUser;
    final nameCtrl = TextEditingController(text: '${user?.username ?? 'Oyuncu'} Odası');
    final feeCtrl = TextEditingController(text: '100');
    int maxPlayers = 4;
    bool isAssisted = true;
    int turnDuration = 30; // 15, 30, 45 sn
    bool addBotForTest = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF092015),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            top: 14,
            left: 18,
            right: 18,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ÜST BAŞLIK (Ferahlama, taşma ve yarım kalma önlendi)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFD4AF37)),
                          ),
                          child: const Icon(Icons.arrow_back_ios_new, size: 14, color: Color(0xFFFDE047)),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          '♠ OYUN ODASI AÇ',
                          style: TextStyle(
                            color: Color(0xFFFDE047),
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 1. ODA ADI (Rastgele zar kaldırıldı, geniş alan bırakıldı)
                const Text('Oda Adı', style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.door_front_door_rounded, color: Color(0xFFD4AF37)),
                    filled: true,
                    fillColor: Colors.black38,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFD4AF37)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // 2. OYUN TİPİ (Yardımlı / Yardımsız)
                const Text('Oyun Tipi', style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setDialogState(() => isAssisted = true),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                          decoration: BoxDecoration(
                            color: isAssisted ? const Color(0xFF065F46) : Colors.black26,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isAssisted ? const Color(0xFFFDE047) : Colors.white24,
                              width: isAssisted ? 2 : 1,
                            ),
                          ),
                          child: const Column(
                            children: [
                              Text('✨ Yardımlı Mod', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                              SizedBox(height: 3),
                              Text('Per & Ceza Rehberi', style: TextStyle(color: Colors.white70, fontSize: 10.5)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => setDialogState(() => isAssisted = false),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                          decoration: BoxDecoration(
                            color: !isAssisted ? const Color(0xFF991B1B) : Colors.black26,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: !isAssisted ? const Color(0xFFFDE047) : Colors.white24,
                              width: !isAssisted ? 2 : 1,
                            ),
                          ),
                          child: const Column(
                            children: [
                              Text('🔥 Yardımsız Mod', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                              SizedBox(height: 3),
                              Text('Usta İşi • Hata Yapan Yanar', style: TextStyle(color: Colors.white70, fontSize: 10.5)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 3. OYUNCU SAYISI
                const Text('Oyuncu Sayısı', style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [2, 3, 4, 5, 6].map((cnt) {
                    final sel = cnt == maxPlayers;
                    return InkWell(
                      onTap: () => setDialogState(() => maxPlayers = cnt),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? const Color(0xFFD4AF37) : Colors.black38,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: sel ? const Color(0xFFFDE047) : Colors.white24),
                        ),
                        child: Text(
                          '$cnt Kişilik',
                          style: TextStyle(
                            color: sel ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),

                // 4. OYNAMA BEKLEME SÜRESİ (Hamle Tur Süresi)
                const Text('Oynama Bekleme Süresi', style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [15, 30, 45].map((sec) {
                    final sel = sec == turnDuration;
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          onTap: () => setDialogState(() => turnDuration = sec),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: sel ? const Color(0xFF047857) : Colors.black38,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: sel ? const Color(0xFF34D399) : Colors.white24),
                            ),
                            child: Center(
                              child: Text(
                                '$sec Saniye',
                                style: TextStyle(
                                  color: sel ? Colors.white : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),

                // 5. GİRİŞ KREDİSİ
                const Text('Giriş Kredisi (Kişi Başı 1x)', style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [50, 100, 250, 500, 1000, 2500].map((preset) {
                    return ActionChip(
                      backgroundColor: const Color(0xFF143D2B),
                      label: Text('$preset 🪙', style: const TextStyle(color: Color(0xFFFDE047), fontSize: 11.5)),
                      onPressed: () => feeCtrl.text = '$preset',
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: feeCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.monetization_on, color: Color(0xFFD4AF37), size: 18),
                    filled: true,
                    fillColor: Colors.black26,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),

                // 6. BOT OYUNCU İLE BAŞLAT SEÇENEĞİ (Tek Kişiyle Test Edebilmek İçin)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: const Color(0xFFD4AF37),
                  title: const Row(
                    children: [
                      Text('🤖 Test İçin Bot Oyuncu ile Başlat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  subtitle: const Text('Oda açıldığında hemen 1 bot oturur ve anında test edebilirsiniz.', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  value: addBotForTest,
                  onChanged: (val) => setDialogState(() => addBotForTest = val),
                ),
                const SizedBox(height: 16),

                // 7. ODA AÇ BUTONU (BÜYÜK YEŞİL KART TASARIMI)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 6,
                    ),
                    onPressed: () async {
                      final fee = int.tryParse(feeCtrl.text.trim()) ?? 100;
                      try {
                        final tableId = await GameService.instance.createTable(
                          name: nameCtrl.text.trim(),
                          maxPlayers: maxPlayers,
                          entryFee: fee,
                          isAssisted: isAssisted,
                          turnDurationSeconds: turnDuration,
                        );
                        if (addBotForTest) {
                          GameService.instance.addBot(tableId);
                        }
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        _openTable(tableId, autoSit: true);
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade800),
                        );
                      }
                    },
                    icon: const Text('♠', style: TextStyle(fontSize: 18, color: Color(0xFFFDE047))),
                    label: const Text(
                      'OYUN ODASI AÇ',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1.0),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
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
        title: const Text('🎭 Profil Avatarınızı Seçin', style: TextStyle(color: Color(0xFFFDE047), fontSize: 17)),
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
                    Text(av.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _openTable(String tableId, {bool autoSit = false}) async {
    GameService.instance.enterTable(tableId);
    if (autoSit) {
      Future.delayed(const Duration(milliseconds: 350), () {
        final t = GameService.instance.activeTable;
        final myId = GameService.instance.currentUser?.id;
        if (t != null &&
            t.id == tableId &&
            (t.status == 'waiting' || t.status == 'finished') &&
            !t.seats.any((s) => s?.userId == myId)) {
          final emptyIdx = t.seats.indexWhere((s) => s == null);
          if (emptyIdx != -1) {
            GameService.instance.sitAtSeat(emptyIdx);
          }
        }
      });
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TableScreen(tableId: tableId)),
    );
  }

  void _handleQuickPlay() {
    final tables = GameService.instance.lobbyTables;
    // Açık ve boş koltuğu olan ilk odayı bul
    for (final t in tables) {
      if ((t.status == 'waiting' || t.status == 'finished') && t.seatedCount < t.maxPlayers) {
        _openTable(t.id, autoSit: true);
        return;
      }
    }
    // Yoksa hemen hızlı oda aç
    _showCreateTableDialog();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05160F),
      body: SafeArea(
        child: _currentView == 0
            ? _buildMainMenuView()
            : _buildJoinRoomsView(),
      ),
    );
  }

  // ===========================================================================
  // 1. ANA MENÜ (GÖRSEL 5 REFERANSIYLA SEVİYE/BARSIZ, KREDİ + BUTONSUZ, SADE VE ŞIK)
  // ===========================================================================
  Widget _buildMainMenuView() {
    final service = GameService.instance;
    final user = service.currentUser;
    final avatar = VipAvatar.fromKey(user?.avatar);
    final allTables = service.lobbyTables;

    LobbyTableModel? activeRejoinTable;
    if (service.rejoinedActiveTableId != null) {
      for (final t in allTables) {
        if (t.id == service.rejoinedActiveTableId) {
          activeRejoinTable = t;
          break;
        }
      }
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          // ÜST PROFİL VE KREDİ BARI
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                // Profil Avatarı & İsim (Seviye ve bar kaldırıldı)
                InkWell(
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
                          border: Border.all(color: const Color(0xFFD4AF37), width: 1.8),
                        ),
                        child: Center(
                          child: Text(avatar.emoji, style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        user?.username ?? 'Oyuncu',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // Kredi Kutusu (Yanındaki '+' butonu kaldırıldı)
                InkWell(
                  onTap: _showPlayerHistorySheet,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E3A2F), Color(0xFF0F241C)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFACC15), width: 1.4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🪙', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(
                          '${user?.credits ?? 0}',
                          style: const TextStyle(
                            color: Color(0xFFFDE047),
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Bildirim Zili
                IconButton(
                  tooltip: 'Bildirimler',
                  visualDensity: VisualDensity.compact,
                  onPressed: _showNotificationsSheet,
                  icon: const Icon(Icons.notifications_active, color: Color(0xFFFDE047), size: 23),
                ),

                // Ayarlar Dişlisi
                IconButton(
                  tooltip: 'Ayarlar',
                  visualDensity: VisualDensity.compact,
                  onPressed: _showSettingsDialog,
                  icon: const Icon(Icons.settings, color: Colors.white70, size: 23),
                ),
              ],
            ),
          ),

          // AKTİF MASANA DÖN BANNERI (Varsa)
          if (activeRejoinTable != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: InkWell(
                onTap: () => _openTable(activeRejoinTable!.id),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFB45309), Color(0xFF78350F)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFDE047), width: 1.6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.play_circle_fill_rounded, color: Color(0xFFFDE047), size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'DEVAM EDEN ODA: ${activeRejoinTable.name}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 14),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(height: 20),

          // ORTA LOGO & YANIK İSKAMBİL HD MARKASI
          Center(
            child: Column(
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Color(0xFF2D1B10), Color(0xFF0F0B08)],
                    ),
                    border: Border.all(color: const Color(0xFFD4AF37), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text('♠', style: TextStyle(fontSize: 48, color: Color(0xFFFDE047))),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'YANIK İSKAMBİL HD',
                  style: TextStyle(
                    color: Color(0xFFFDE047),
                    fontWeight: FontWeight.w900,
                    fontSize: 26,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'KLASİK İSKAMBİL DENEYİMİ',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 36),

          // 3 ANA BUTON (OYNA, OYUN ODASI AÇ, ODALARA KATIL)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                // 1. OYNA BUTONU (Yeşil Gradient)
                _buildBigMenuButton(
                  title: 'OYNA',
                  icon: Icons.play_arrow_rounded,
                  gradient: const [Color(0xFF059669), Color(0xFF047857)],
                  borderColor: const Color(0xFF34D399),
                  onTap: _handleQuickPlay,
                ),
                const SizedBox(height: 14),

                // 2. OYUN ODASI AÇ BUTONU
                _buildBigMenuButton(
                  title: 'OYUN ODASI AÇ',
                  icon: Icons.table_restaurant_rounded,
                  gradient: const [Color(0xFF1E293B), Color(0xFF0F172A)],
                  borderColor: const Color(0xFFD4AF37),
                  onTap: _showCreateTableDialog,
                ),
                const SizedBox(height: 14),

                // 3. ODALARA KATIL BUTONU
                _buildBigMenuButton(
                  title: 'ODALARA KATIL',
                  icon: Icons.groups_rounded,
                  gradient: const [Color(0xFF1E293B), Color(0xFF0F172A)],
                  borderColor: const Color(0xFFD4AF37),
                  onTap: () => setState(() => _currentView = 1),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ALT GRID BUTONLARI (Arkadaşlar, Oyun Kuralları, İstatistikler)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSmallActionTile(
                  icon: Icons.people_alt_rounded,
                  label: 'Arkadaşlar',
                  onTap: _showFriendsSheet,
                ),
                _buildSmallActionTile(
                  icon: Icons.menu_book_rounded,
                  label: 'Kurallar',
                  onTap: _showRulesSheet,
                ),
                _buildSmallActionTile(
                  icon: Icons.leaderboard_rounded,
                  label: 'İstatistikler',
                  onTap: _showPlayerHistorySheet,
                ),
                if (user?.isAdmin == true)
                  _buildSmallActionTile(
                    icon: Icons.admin_panel_settings,
                    label: 'Yönetim',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AdminScreen()),
                      );
                    },
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ÇIKIŞ YAP KÜÇÜK BUTONU
          TextButton.icon(
            onPressed: () async {
              await service.logout();
              if (!mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            icon: const Icon(Icons.logout, size: 16, color: Colors.white38),
            label: const Text('Oturumu Kapat', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildBigMenuButton({
    required String title,
    required IconData icon,
    required List<Color> gradient,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFFFDE047), size: 26),
                const SizedBox(width: 14),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSmallActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 78,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.45)),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFFFDE047), size: 22),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 2. ODALARA KATIL EKRANI (GÖRSEL 3 REFERANSIYLA YARDIMLI / YARDIMSIZ SEKME)
  // ===========================================================================
  Widget _buildJoinRoomsView() {
    final allTables = GameService.instance.lobbyTables;

    // Filtreleme: Önce Yardımlı / Yardımsız Sekmesi, sonra Kişi Sayısı
    final filtered = allTables.where((t) {
      if (_selectedTab == 'assisted' && !t.isAssisted) return false;
      if (_selectedTab == 'unassisted' && t.isAssisted) return false;

      if (_selectedCapacityFilter == 2 && t.maxPlayers != 2) return false;
      if (_selectedCapacityFilter == 3 && t.maxPlayers != 3) return false;
      if (_selectedCapacityFilter == 4 && t.maxPlayers != 4) return false;
      if (_selectedCapacityFilter == 5 && t.maxPlayers < 5) return false;

      return true;
    }).toList();

    return Column(
      children: [
        // ÜST BAR: Geri Dön + Başlık + "+ ODA AÇ"
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFF071D13),
            border: Border(bottom: BorderSide(color: Color(0xFFD4AF37), width: 1.2)),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _currentView = 0),
                icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFFFDE047), size: 18),
              ),
              const SizedBox(width: 4),
              const Text(
                'ODALARA KATIL',
                style: TextStyle(
                  color: Color(0xFFFDE047),
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4AF37),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _showCreateTableDialog,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('ODA AÇ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
              ),
            ],
          ),
        ),

        // MOD SEKMELERİ (Açık/Özel yerine: Yardımlı Odalar / Yardımsız Odalar)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _selectedTab = 'assisted'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: _selectedTab == 'assisted' ? const Color(0xFF059669) : Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedTab == 'assisted' ? const Color(0xFF34D399) : Colors.white24,
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        '✨ Yardımlı Odalar',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _selectedTab = 'unassisted'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: _selectedTab == 'unassisted' ? const Color(0xFF991B1B) : Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedTab == 'unassisted' ? const Color(0xFFF87171) : Colors.white24,
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        '🔥 Yardımsız Odalar',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // KAPASİTE FİLTRELERİ (Tümü, 2 Kişilik, 3 Kişilik, 4 Kişilik, 5+ Kişilik)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              _buildCapacityChip(0, 'Tümü'),
              const SizedBox(width: 6),
              _buildCapacityChip(2, '2 Kişilik'),
              const SizedBox(width: 6),
              _buildCapacityChip(3, '3 Kişilik'),
              const SizedBox(width: 6),
              _buildCapacityChip(4, '4 Kişilik'),
              const SizedBox(width: 6),
              _buildCapacityChip(5, '5+ Kişilik'),
            ],
          ),
        ),

        const SizedBox(height: 6),

        // ODA LİSTESİ (Pull-to-refresh & Otomatik Socket Güncellemeli)
        Expanded(
          child: RefreshIndicator(
            color: const Color(0xFFD4AF37),
            onRefresh: () async {
              GameService.instance.refreshLobbyTables();
            },
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('🃏', style: TextStyle(fontSize: 44)),
                        const SizedBox(height: 10),
                        const Text(
                          'Şu anda bu filtrede açık oda bulunmuyor.\nYeni bir oda açarak oyunu hemen başlatabilirsiniz!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD4AF37),
                            foregroundColor: Colors.black,
                          ),
                          onPressed: _showCreateTableDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Oyun Odası Aç', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final t = filtered[i];
                      final isPlaying = t.status == 'playing' || t.status == 'round_summary';
                      final isFull = t.seatedCount >= t.maxPlayers;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B2419),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: t.isAssisted ? const Color(0xFFD4AF37).withValues(alpha: 0.6) : Colors.redAccent.withValues(alpha: 0.6),
                          ),
                          boxShadow: const [
                            BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 3)),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              // Oda İkonu / Thumbnail
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black38,
                                  border: Border.all(color: const Color(0xFFD4AF37)),
                                ),
                                child: Center(
                                  child: Text(t.isAssisted ? '✨' : '🔥', style: const TextStyle(fontSize: 22)),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Oda Detayları
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.name,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${t.isAssisted ? "Yardımlı" : "Yardımsız"} • Oynama: ${t.turnDurationSeconds} sn • ${t.entryFee} 🪙',
                                      style: const TextStyle(color: Color(0xFFFDE047), fontSize: 11),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.person, size: 13, color: isFull ? Colors.redAccent : const Color(0xFF10B981)),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${t.seatedCount}/${t.maxPlayers} Oyuncu',
                                          style: TextStyle(
                                            color: isFull ? Colors.redAccent : Colors.white70,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (isPlaying) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.redAccent.withValues(alpha: 0.3),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text('El #${t.roundNumber}', style: const TextStyle(color: Colors.redAccent, fontSize: 10)),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // Katıl Butonu
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isFull
                                      ? Colors.grey.shade800
                                      : const Color(0xFF059669),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: isFull ? null : () => _openTable(t.id, autoSit: true),
                                child: Text(
                                  isFull ? 'DOLU' : 'KATIL',
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildCapacityChip(int capacity, String label) {
    final selected = _selectedCapacityFilter == capacity;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: const Color(0xFFD4AF37),
      backgroundColor: const Color(0xFF0E2F21),
      labelStyle: TextStyle(
        color: selected ? Colors.black : Colors.white70,
        fontWeight: FontWeight.bold,
        fontSize: 11,
      ),
      onSelected: (_) => setState(() => _selectedCapacityFilter = capacity),
    );
  }
}
