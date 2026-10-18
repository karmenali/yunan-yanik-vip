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
  String _selectedFilter = 'all'; // 'all', 'assisted', 'unassisted', 'open'

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

  void _handleQuickPlay() {
    final service = GameService.instance;
    final userCredits = service.currentUser?.credits ?? 0;

    // Eğer oyuncunun zaten oturduğu aktif bir masa varsa direkt oraya dön
    if (service.rejoinedActiveTableId != null) {
      _openTable(service.rejoinedActiveTableId!);
      return;
    }

    // Bekleyen, boş koltuğu olan ve oyuncunun kredisinin yettiği en dolu masayı bul
    final candidates = service.lobbyTables.where((t) {
      final isWaiting = t.status == 'waiting' || t.status == 'finished';
      final hasSeat = t.seatedCount < t.maxPlayers;
      final canAfford = userCredits >= t.entryFee;
      return isWaiting && hasSeat && canAfford;
    }).toList();

    if (candidates.isNotEmpty) {
      candidates.sort((a, b) => b.seatedCount.compareTo(a.seatedCount));
      final chosen = candidates.first;
      _openTable(chosen.id, autoSit: true);
    } else if (service.lobbyTables.isNotEmpty) {
      _openTable(service.lobbyTables.first.id, autoSit: true);
    } else {
      _showCreateTableDialog();
    }
  }

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
                      '📖 Yunan Yanık VIP — Oyun Kuralları',
                      style: TextStyle(
                        color: Color(0xFFFDE047),
                        fontWeight: FontWeight.w900,
                        fontSize: 16.5,
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
                        '🃏 106 Kağıt & 3 Sıralı Dikey Istaka',
                        'Oyun 2 tam deste (104 kağıt) + 2 Fiziksel Joker olmak üzere toplam 106 kağıtla oynanır. Her oyuncuya 10\'ar kağıt dağıtılır. Kağıtlarınızı ekrandaki 3 yatay sırada parmağınızla sürükleyerek dilediğiniz gibi gruplayabilirsiniz.',
                      ),
                      _buildRuleCard(
                        '👑 Gösterge Jokeri (Wild Card)',
                        'Dağıtım sonunda açılan Gösterge kağıdı ile aynı sayıdaki tüm kağıtlar (ve 2 fiziksel Joker) o el boyunca JOKER (Wild) yerine geçer. Boşta kalan Joker 25 ceza puanı yazar.',
                      ),
                      _buildRuleCard(
                        '✨ Yardımlı Mod vs 🔥 Yardımsız (Usta) Mod',
                        '• Yardımlı Mod: Geçerli perleriniz (✓ PER) ve elinizdeki ceza puanı otomatik gösterilir.\n'
                            '• Yardımsız (Usta) Mod: Hiçbir per veya ceza ipucu gösterilmez! Herkes kendi perlerini 3 sırada dizer. DİKKAT: Yardımsız modda hatalı el açan oyuncu DİREKT YANMIŞ SAYILIR ve o maç için tekrar kredi yatırıp en yüksek puanlı oyuncudan devam etme (Re-buy) hakkını tamamen kaybeder!',
                      ),
                      _buildRuleCard(
                        '🔍 Şeffaf El Açma (10 Sn Gösterim + Saat Yönü Ceza)',
                        'Bir oyuncu el açtığında açtığı 10 kağıt tam 10 saniye boyunca masanın ortasında herkese açık gösterilir. Ardından diğer oyuncuların ellerinde kalan kağıtlar saat yönünde sırayla açılarak yedikleri ceza puanları şeffaf biçimde toplama eklenir.',
                      ),
                      _buildRuleCard(
                        '🔥 101 Yanma & Yeniden Giriş (Re-buy)',
                        'Toplam ceza puanı 101 veya üzerine çıkan oyuncu yanar. Masada en az 2 oyuncu devam ediyorsa (ve oyuncu hatalı el açarak yanmadıysa), 1x, 2x, 3x masa ücreti ödeyerek hayatta kalan en yüksek puanlı oyuncunun puanıyla maça geri dönebilir. Maç sonunda potun %95\'i şampiyona aktarılır!',
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
    bool isAssisted = true;

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
                const SizedBox(height: 14),
                const Text(
                  'Oyun Modu Seçimi:',
                  style: TextStyle(
                    color: Color(0xFFFDE047),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setDialogState(() => isAssisted = true),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isAssisted
                                ? const Color(0xFF065F46)
                                : Colors.black26,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isAssisted
                                  ? const Color(0xFFFDE047)
                                  : Colors.white24,
                              width: isAssisted ? 2 : 1,
                            ),
                          ),
                          child: const Column(
                            children: [
                              Text('✨ Yardımlı Mod',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12.5)),
                              SizedBox(height: 3),
                              Text('Per & Ceza Gösterir',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 10.5)),
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
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: !isAssisted
                                ? const Color(0xFF991B1B)
                                : Colors.black26,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: !isAssisted
                                  ? const Color(0xFFFDE047)
                                  : Colors.white24,
                              width: !isAssisted ? 2 : 1,
                            ),
                          ),
                          child: const Column(
                            children: [
                              Text('🔥 Yardımsız Mod',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12.5)),
                              SizedBox(height: 3),
                              Text('Usta İşi • Ceza Korumasız',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 10.5)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (!isAssisted) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent),
                    ),
                    child: const Text(
                      '⚠️ Yardımsız Mod Kuralı: Per ipucu verilmez. Hatalı el açan oyuncu direkt yanar ve o oyun için tekrar para yatırıp dahil olma (Re-buy) hakkını kaybeder!',
                      style: TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
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
                const SizedBox(height: 14),
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
                    isAssisted: isAssisted,
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  _openTable(tableId, autoSit: true);
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

  @override
  Widget build(BuildContext context) {
    final service = GameService.instance;
    final user = service.currentUser;
    final avatar = VipAvatar.fromKey(user?.avatar);
    final allTables = service.lobbyTables;

    final filteredTables = allTables.where((t) {
      if (_selectedFilter == 'assisted') return t.isAssisted;
      if (_selectedFilter == 'unassisted') return !t.isAssisted;
      if (_selectedFilter == 'open') {
        return (t.status == 'waiting' || t.status == 'finished') &&
            t.seatedCount < t.maxPlayers;
      }
      return true;
    }).toList();

    LobbyTableModel? activeRejoinTable;
    if (service.rejoinedActiveTableId != null) {
      for (final t in allTables) {
        if (t.id == service.rejoinedActiveTableId) {
          activeRejoinTable = t;
          break;
        }
      }
    }

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
                      const SizedBox(width: 2),
                      IconButton(
                        tooltip: 'Oyun Kuralları',
                        visualDensity: VisualDensity.compact,
                        onPressed: _showRulesSheet,
                        icon: const Icon(
                          Icons.menu_book_rounded,
                          color: Color(0xFFFDE047),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Oyun & Kredi Geçmişim',
                        visualDensity: VisualDensity.compact,
                        onPressed: _showPlayerHistorySheet,
                        icon: const Icon(
                          Icons.history,
                          color: Color(0xFFFDE047),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Ses ve Oyun Ayarları',
                        visualDensity: VisualDensity.compact,
                        onPressed: _showSettingsDialog,
                        icon: const Icon(Icons.settings, color: Colors.white70),
                      ),
                      IconButton(
                        tooltip: 'Çıkış Yap',
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          await service.logout();
                          if (!context.mounted) return;
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

                  // AKSİYON BUTONLARI SATIRI (HIZLI OYNA + YENİ MASA KUR + ADMİN)
                  Row(
                    children: [
                      if (user?.isAdmin == true) ...[
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7E22CE),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
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
                                size: 16,
                              ),
                              label: const Text(
                                'YÖNETİM',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: SizedBox(
                          height: 42,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(
                                  color: Color(0xFF34D399),
                                ),
                              ),
                            ),
                            onPressed: _handleQuickPlay,
                            icon: const Icon(Icons.flash_on_rounded, size: 17),
                            label: const Text(
                              'HIZLI OYNA',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 42,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD4AF37),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _showCreateTableDialog,
                            icon: const Icon(Icons.add_circle, size: 17),
                            label: const Text(
                              'MASA KUR',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 11.5,
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

            // AKTİF MASANA DÖN BANNERI (Eğer oyuncunun devam eden bir masası varsa)
            if (activeRejoinTable != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: InkWell(
                  onTap: () => _openTable(activeRejoinTable!.id),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFB45309), Color(0xFF78350F)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFFDE047),
                        width: 1.6,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.play_circle_fill_rounded,
                          color: Color(0xFFFDE047),
                          size: 26,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AKTİF OYUNUNUZ DEVAM EDİYOR: ${activeRejoinTable.name}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12.5,
                                ),
                              ),
                              const Text(
                                'Koltuk ve eliniz korunuyor • Masaya dönmek için dokunun',
                                style: TextStyle(
                                  color: Color(0xFFFDE047),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 2. MASA FİLTRE SEKMELERİ
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  _buildFilterChip('all', 'Tümü (${allTables.length})'),
                  const SizedBox(width: 6),
                  _buildFilterChip('assisted', '✨ Yardımlı Mod'),
                  const SizedBox(width: 6),
                  _buildFilterChip('unassisted', '🔥 Yardımsız (Usta)'),
                  const SizedBox(width: 6),
                  _buildFilterChip('open', '🪑 Boş Koltuk'),
                ],
              ),
            ),

            // 3. CANLI MASALAR LİSTESİ
            Expanded(
              child: filteredTables.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('🃏', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 10),
                          const Text(
                            'Bu filtrede açık masa yok. Yeni bir masa kurabilirsiniz!',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 14),
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
                      itemCount: filteredTables.length,
                      itemBuilder: (ctx, i) {
                        final t = filteredTables[i];
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
                              color: !t.isAssisted
                                  ? const Color(0xFFEF4444).withValues(alpha: 0.85)
                                  : isPlaying
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
                                          horizontal: 9,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: t.isAssisted
                                              ? const Color(0xFF065F46)
                                              : const Color(0xFF7F1D1D),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                            color: t.isAssisted
                                                ? const Color(0xFF34D399)
                                                : const Color(0xFFF87171),
                                            width: 0.9,
                                          ),
                                        ),
                                        child: Text(
                                          t.isAssisted
                                              ? '✨ Yardımlı Mod'
                                              : '🔥 Yardımsız (Usta)',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
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

  Widget _buildFilterChip(String key, String label) {
    final selected = _selectedFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: const Color(0xFFD4AF37),
      backgroundColor: const Color(0xFF0E2F21),
      labelStyle: TextStyle(
        color: selected ? Colors.black : Colors.white70,
        fontWeight: FontWeight.w800,
        fontSize: 11.5,
      ),
      onSelected: (_) => setState(() => _selectedFilter = key),
    );
  }
}
