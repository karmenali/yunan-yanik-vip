import 'package:flutter/material.dart';
import '../models/game_models.dart';
import '../services/game_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _users = [];
  Map<String, dynamic> _vault = {};
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _tables = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadDashboard();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await GameService.instance.fetchAdminDashboard();
      if (!mounted) return;
      setState(() {
        _users = List<Map<String, dynamic>>.from(data['users'] ?? []);
        _vault = Map<String, dynamic>.from(data['vault'] ?? {});
        _transactions =
            List<Map<String, dynamic>>.from(data['transactions'] ?? []);
        _tables = List<Map<String, dynamic>>.from(data['tables'] ?? []);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade800 : const Color(0xFF059669),
      ),
    );
  }

  Future<void> _showCreateUserDialog() async {
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final creditsCtrl = TextEditingController(text: '5000');
    String selectedAvatar = 'lion';
    String selectedRole = 'player';

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F291E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
              ),
              title: const Text(
                '👤 Yeni Oyuncu Oluştur',
                style: TextStyle(
                  color: Color(0xFFFDE047),
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 380,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: usernameCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Kullanıcı Adı',
                          labelStyle: TextStyle(color: Colors.white70),
                          prefixIcon: Icon(Icons.person, color: Color(0xFFD4AF37)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: passwordCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Şifre',
                          labelStyle: TextStyle(color: Colors.white70),
                          prefixIcon: Icon(Icons.lock, color: Color(0xFFD4AF37)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: creditsCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Başlangıç Sanal Kredisi',
                          labelStyle: TextStyle(color: Colors.white70),
                          prefixIcon: Icon(Icons.monetization_on, color: Color(0xFFD4AF37)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('Yetki: ', style: TextStyle(color: Colors.white70)),
                          const SizedBox(width: 12),
                          DropdownButton<String>(
                            value: selectedRole,
                            dropdownColor: const Color(0xFF0F291E),
                            style: const TextStyle(color: Colors.white),
                            items: const [
                              DropdownMenuItem(value: 'player', child: Text('Oyuncu')),
                              DropdownMenuItem(value: 'admin', child: Text('Admin Yetkilisi')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => selectedRole = v);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: VipAvatar.all.map((av) {
                          final sel = av.key == selectedAvatar;
                          return ChoiceChip(
                            label: Text('${av.emoji} ${av.title}'),
                            selected: sel,
                            selectedColor: const Color(0xFFD4AF37),
                            onSelected: (_) {
                              setDialogState(() => selectedAvatar = av.key);
                            },
                          );
                        }).toList(),
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
                    try {
                      await GameService.instance.adminCreateUser(
                        username: usernameCtrl.text.trim(),
                        password: passwordCtrl.text.trim(),
                        initialCredits: int.tryParse(creditsCtrl.text.trim()) ?? 0,
                        avatar: selectedAvatar,
                        role: selectedRole,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      _showSnack('Oyuncu başarıyla oluşturuldu!');
                      _loadDashboard();
                    } catch (e) {
                      _showSnack(e.toString(), isError: true);
                    }
                  },
                  child: const Text('Oluştur'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCreditDialog(Map<String, dynamic> user, bool isAdd) async {
    final amountCtrl = TextEditingController(text: '1000');
    final descCtrl = TextEditingController(
      text: isAdd ? 'Admin kredi yüklemesi' : 'Admin kredi kesintisi',
    );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F291E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
        ),
        title: Text(
          isAdd
              ? '💰 ${user['username']} — Kredi Yükle'
              : '➖ ${user['username']} — Kredi Düş',
          style: const TextStyle(color: Color(0xFFFDE047)),
        ),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Mevcut Bakiye: ${user['credits']} Kredi',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [500, 1000, 5000, 10000].map((preset) {
                  return ActionChip(
                    label: Text('$preset'),
                    onPressed: () => amountCtrl.text = '$preset',
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Kredi Miktarı',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Açıklama',
                  labelStyle: TextStyle(color: Colors.white70),
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
              backgroundColor: isAdd ? const Color(0xFF10B981) : Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final raw = int.tryParse(amountCtrl.text.trim()) ?? 0;
              if (raw <= 0) return;
              final signedAmount = isAdd ? raw : -raw;
              try {
                await GameService.instance.adminAdjustCredits(
                  userId: user['id'].toString(),
                  amount: signedAmount,
                  description: descCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _showSnack('Kredi bakiyesi güncellendi!');
                _loadDashboard();
              } catch (e) {
                _showSnack(e.toString(), isError: true);
              }
            },
            child: Text(isAdd ? '+ Kredi Tanımla' : '- Kredi Düş'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPasswordResetDialog(Map<String, dynamic> user) async {
    final passCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F291E),
        title: Text(
          '🔑 ${user['username']} — Yeni Şifre',
          style: const TextStyle(color: Color(0xFFFDE047)),
        ),
        content: TextField(
          controller: passCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Yeni Şifre (en az 4 karakter)',
            labelStyle: TextStyle(color: Colors.white70),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await GameService.instance.adminResetPassword(
                  user['id'].toString(),
                  passCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _showSnack('Şifre değiştirildi.');
              } catch (e) {
                _showSnack(e.toString(), isError: true);
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rake = _vault['rake_collected'] ?? 0;
    final emojiRev = _vault['emoji_collected'] ?? 0;
    final totalGames = _vault['total_games_played'] ?? 0;
    final emojiCost = _vault['emoji_cost'] ?? 10;

    return Scaffold(
      backgroundColor: const Color(0xFF061A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A281C),
        title: const Row(
          children: [
            Text('👑 ', style: TextStyle(fontSize: 22)),
            Text(
              'VIP YÖNETİM PANELİ (ADMİN)',
              style: TextStyle(
                color: Color(0xFFFDE047),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: Colors.black,
            ),
            onPressed: _showCreateUserDialog,
            icon: const Icon(Icons.person_add, size: 18),
            label: const Text('Yeni Oyuncu Aç'),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh, color: Color(0xFFFDE047)),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFD4AF37),
          labelColor: const Color(0xFFFDE047),
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: '👥 Oyuncular & Kredi Tanımlama'),
            Tab(text: '🏦 Sistem Kasası (%5 Komisyon & Emoji)'),
            Tab(text: '📜 Kredi Hareketleri & Masalar'),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
            )
          : _error != null
              ? Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    // TAB 1: OYUNCULAR
                    ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _users.length,
                      itemBuilder: (ctx, i) {
                        final u = _users[i];
                        final av = VipAvatar.fromKey(u['avatar']?.toString());
                        final banned = u['is_banned'] == true;
                        return Card(
                          color: const Color(0xFF0E2F21),
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: banned
                                  ? Colors.redAccent
                                  : const Color(0xFFD4AF37).withValues(alpha: 0.4),
                            ),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: av.color.withValues(alpha: 0.25),
                              child: Text(av.emoji, style: const TextStyle(fontSize: 22)),
                            ),
                            title: Row(
                              children: [
                                Text(
                                  u['username']?.toString() ?? '',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (u['role'] == 'admin')
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD4AF37),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'ADMİN',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                if (banned)
                                  Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'BANLI',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              'Sanal Kredi: ${u['credits']} 🪙',
                              style: const TextStyle(
                                color: Color(0xFFFDE047),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: Wrap(
                              spacing: 6,
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                  ),
                                  onPressed: () => _showCreditDialog(u, true),
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('Kredi Ekle'),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.orangeAccent,
                                    side: const BorderSide(color: Colors.orangeAccent),
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                  ),
                                  onPressed: () => _showCreditDialog(u, false),
                                  icon: const Icon(Icons.remove, size: 16),
                                  label: const Text('Kredi Düş'),
                                ),
                                IconButton(
                                  tooltip: 'Şifre Değiştir',
                                  onPressed: () => _showPasswordResetDialog(u),
                                  icon: const Icon(Icons.key, color: Colors.white70),
                                ),
                                if (u['role'] != 'admin')
                                  IconButton(
                                    tooltip: banned ? 'Banı Kaldır' : 'Hesabı Banla',
                                    onPressed: () async {
                                      await GameService.instance.adminSetBan(
                                        u['id'].toString(),
                                        !banned,
                                      );
                                      _loadDashboard();
                                    },
                                    icon: Icon(
                                      banned ? Icons.lock_open : Icons.block,
                                      color: banned ? Colors.greenAccent : Colors.redAccent,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    // TAB 2: SİSTEM KASASI (%5 KOMİSYON & EMOJİ GELİRLERİ)
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  title: '🏦 %5 Masa Komisyon Geliri',
                                  value: '$rake 🪙',
                                  subtitle: 'Oyun sonu potlardan kesilen %5 kasa payı',
                                  color: const Color(0xFFD4AF37),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  title: '🎭 Masa İçi Efekt/Emoji Geliri',
                                  value: '$emojiRev 🪙',
                                  subtitle: 'Bomba, Domates, Gül vb. gönderim gelirleri',
                                  color: const Color(0xFF10B981),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  title: '🃏 Tamamlanan Maç Sayısı',
                                  value: '$totalGames',
                                  subtitle: 'Toplam kasa net gelir: ${rake + emojiRev} 🪙',
                                  color: const Color(0xFF38BDF8),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Card(
                            color: const Color(0xFF0E2F21),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: const BorderSide(color: Color(0xFFD4AF37)),
                            ),
                            child: ListTile(
                              title: const Text(
                                '🎭 Masa İçi Emoji / Efekt Gönderim Ücreti',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                'Şu anki ücret: Her emoji/efekt gönderiminde oyuncudan $emojiCost Kredi düşülür.',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              trailing: Wrap(
                                spacing: 8,
                                children: [5, 10, 25, 50].map((c) {
                                  final active = c == emojiCost;
                                  return ChoiceChip(
                                    label: Text('$c 🪙'),
                                    selected: active,
                                    selectedColor: const Color(0xFFD4AF37),
                                    onSelected: (_) async {
                                      await GameService.instance.adminSetEmojiCost(c);
                                      _loadDashboard();
                                    },
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // TAB 3: HAREKETLER & AKTİF MASALAR
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _transactions.length,
                            itemBuilder: (ctx, i) {
                              final tx = _transactions[i];
                              final amt = int.tryParse(tx['amount'].toString()) ?? 0;
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  amt >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                                  color: amt >= 0 ? Colors.greenAccent : Colors.redAccent,
                                ),
                                title: Text(
                                  '${tx['username']} (${amt >= 0 ? '+$amt' : '$amt'} 🪙)',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                subtitle: Text(
                                  tx['description']?.toString() ?? '',
                                  style: const TextStyle(color: Colors.white60),
                                ),
                              );
                            },
                          ),
                        ),
                        const VerticalDivider(color: Colors.white24),
                        Expanded(
                          flex: 1,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _tables.length,
                            itemBuilder: (ctx, i) {
                              final t = _tables[i];
                              return Card(
                                color: const Color(0xFF0E2F21),
                                child: ListTile(
                                  title: Text(
                                    t['name']?.toString() ?? '',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  subtitle: Text(
                                    'Pot: ${t['pot']} 🪙 | Giriş: ${t['entryFee']} 🪙',
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                                    onPressed: () async {
                                      await GameService.instance
                                          .adminCloseTable(t['id'].toString());
                                      _loadDashboard();
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0E2F21),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }
}
