import 'package:flutter/material.dart';
import '../models/game_models.dart';
import '../services/game_service.dart';
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
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFD4AF37), width: 1.8),
          ),
          title: const Text(
            '🃏 Yeni Oyun Masası Kur',
            style: TextStyle(
              color: Color(0xFFFDE047),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Masa Adı',
                      labelStyle: TextStyle(color: Colors.white70),
                      prefixIcon: Icon(Icons.table_bar, color: Color(0xFFD4AF37)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Masa Kapasitesi (Min 2 - Maks 6 Oyuncu):',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
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
                        onSelected: (_) => setDialogState(() => maxPlayers = cnt),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Oyun Giriş Kredisi (Kişi Başı 1x):',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
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
                  const SizedBox(height: 8),
                  TextField(
                    controller: feeCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Giriş Kredisi Miktarı',
                      labelStyle: TextStyle(color: Colors.white70),
                      prefixIcon:
                          Icon(Icons.monetization_on, color: Color(0xFFD4AF37)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'ℹ️ Oyun sonunda toplam kasanın %5\'i sistem kasasına kesilir, %95\'i şampiyon oyuncuya aktarılır.',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
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
          '🎭 VIP Kulüp Avatarınızı Seçin',
          style: TextStyle(color: Color(0xFFFDE047)),
        ),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: VipAvatar.all.map((av) {
            final selected = av.key == user.avatar;
            return InkWell(
              onTap: () async {
                await GameService.instance.updateAvatar(av.key);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Container(
                width: 95,
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
                    Text(av.emoji, style: const TextStyle(fontSize: 32)),
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

  void _openTable(String tableId) {
    GameService.instance.enterTable(tableId);
    Navigator.of(context).push(
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
      body: Column(
        children: [
          // ÜST VIP BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0C2E1F), Color(0xFF071D13)],
              ),
              border: Border(
                bottom: BorderSide(color: Color(0xFFD4AF37), width: 1.5),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  // Avatar & Kullanıcı
                  InkWell(
                    onTap: _showAvatarPickerDialog,
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: const Color(0xFFD4AF37)),
                      ),
                      child: Row(
                        children: [
                          Text(avatar.emoji, style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.username ?? 'Oyuncu',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                user?.isAdmin == true ? '👑 Kulüp Yöneticisi' : 'VIP Üye',
                                style: const TextStyle(
                                  color: Color(0xFFFDE047),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Canlı Sanal Kredi Göstergesi
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E3A2F), Color(0xFF0F241C)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFACC15), width: 1.4),
                    ),
                    child: Row(
                      children: [
                        const Text('🪙', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Text(
                          '${user?.credits ?? 0} KREDİ',
                          style: const TextStyle(
                            color: Color(0xFFFDE047),
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  const Text(
                    '♠️ YUNAN YANIK LOBİSİ ♦️',
                    style: TextStyle(
                      color: Color(0xFFFDE047),
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 1.1,
                    ),
                  ),

                  const Spacer(),

                  // Admin Butonu (Sadece Admin Yetkilisi Görür)
                  if (user?.isAdmin == true) ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF9333EA),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AdminScreen()),
                        );
                      },
                      icon: const Icon(Icons.admin_panel_settings, size: 18),
                      label: const Text(
                        'YÖNETİM PANELİ',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],

                  // Yeni Masa Kur Butonu
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _showCreateTableDialog,
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text(
                      'MASA KUR',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),

                  IconButton(
                    tooltip: 'Çıkış Yap',
                    onPressed: () {
                      service.logout();
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    },
                    icon: const Icon(Icons.logout, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),

          // MASALAR LİSTESİ (ÖZGÜRCE GEZİNME)
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
                          style: TextStyle(color: Colors.white70, fontSize: 16),
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
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 1.65,
                    ),
                    itemCount: tables.length,
                    itemBuilder: (ctx, i) {
                      final t = tables[i];
                      final isPlaying =
                          t.status == 'playing' || t.status == 'round_summary';

                      return InkWell(
                        onTap: () => _openTable(t.id),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            gradient: const RadialGradient(
                              center: Alignment.center,
                              radius: 1.0,
                              colors: [Color(0xFF134E35), Color(0xFF09261A)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isPlaying
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFD4AF37),
                              width: 1.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      t.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isPlaying
                                          ? const Color(0xFF059669)
                                          : const Color(0xFFD97706),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      isPlaying
                                          ? '🔥 El #${t.roundNumber}'
                                          : '⏳ Oyuncu Bekliyor',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black38,
                                      borderRadius: BorderRadius.circular(8),
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
                                  const SizedBox(width: 8),
                                  if (t.pot > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF065F46),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Kasa Pot: ${t.pot} 🪙',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const Spacer(),
                              // Koltuk İkonları
                              Row(
                                children: [
                                  ...List.generate(t.maxPlayers, (seatIdx) {
                                    final occupant = t.players.cast<Map<String, dynamic>?>().firstWhere(
                                      (p) => p?['seatIndex'] == seatIdx,
                                      orElse: () => null,
                                    );
                                    final av = occupant != null
                                        ? VipAvatar.fromKey(occupant['avatar']?.toString())
                                        : null;
                                    return Container(
                                      margin: const EdgeInsets.only(right: 5),
                                      width: 28,
                                      height: 28,
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
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    );
                                  }),
                                  const Spacer(),
                                  Text(
                                    '${t.seatedCount}/${t.maxPlayers}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
