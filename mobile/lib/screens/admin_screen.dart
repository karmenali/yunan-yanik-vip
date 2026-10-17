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
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
              ),
              title: const Text(
                '👤 Yeni Oyuncu Oluştur',
                style: TextStyle(
                  color: Color(0xFFFDE047),
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              content: SingleChildScrollView(
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
                        prefixIcon:
                            Icon(Icons.monetization_on, color: Color(0xFFD4AF37)),
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
                            DropdownMenuItem(
                                value: 'admin', child: Text('Admin Yetkilisi')),
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
                      runSpacing: 6,
                      children: VipAvatar.all.map((av) {
                        final sel = av.key == selectedAvatar;
                        return ChoiceChip(
                          label: Text('${av.emoji} ${av.title}'),
                          selected: sel,
                          selectedColor: const Color(0xFFD4AF37),
                          labelStyle: TextStyle(
                            color: sel ? Colors.black : Colors.white,
                          ),
                          onSelected: (_) {
                            setDialogState(() => selectedAvatar = av.key);
                          },
                        );
                      }).toList(),
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
                    try {
                      await GameService.instance.adminCreateUser(
                        username: usernameCtrl.text.trim(),
                        password: passwordCtrl.text.trim(),
                        initialCredits:
                            int.tryParse(creditsCtrl.text.trim()) ?? 0,
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
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
        ),
        title: Text(
          isAdd
              ? '💰 ${user['username']} — Kredi Yükle'
              : '➖ ${user['username']} — Kredi Düş',
          style: const TextStyle(color: Color(0xFFFDE047), fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Mevcut Bakiye: ${user['credits']} 🪙',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [500, 1000, 5000, 10000].map((preset) {
                  return ActionChip(
                    label: Text('$preset 🪙'),
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
              backgroundColor:
                  isAdd ? const Color(0xFF10B981) : Colors.redAccent,
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
          style: const TextStyle(color: Color(0xFFFDE047), fontSize: 16),
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
        title: const Text(
          '👑 YÖNETİM PANELİ',
          style: TextStyle(
            color: Color(0xFFFDE047),
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Yeni Oyuncu Aç',
            onPressed: _showCreateUserDialog,
            icon: const Icon(Icons.person_add_alt_1, color: Color(0xFFFDE047)),
          ),
          IconButton(
            tooltip: 'Yenile',
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          indicatorColor: const Color(0xFFD4AF37),
          labelColor: const Color(0xFFFDE047),
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: const [
            Tab(text: '👥 Oyuncular'),
            Tab(text: '🏦 Kasa (%5)'),
            Tab(text: '📜 Kayıtlar'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFD4AF37),
        foregroundColor: Colors.black,
        onPressed: _showCreateUserDialog,
        icon: const Icon(Icons.person_add),
        label: const Text(
          'Yeni Oyuncu Aç',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    // TAB 1: OYUNCULAR (HER TELEFONDA TAŞMADAN GÖRÜNEN KARTLAR)
                    ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                      itemCount: _users.length,
                      itemBuilder: (ctx, i) {
                        final u = _users[i];
                        final av = VipAvatar.fromKey(u['avatar']?.toString());
                        final banned = u['is_banned'] == true;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0E2F21),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: banned
                                  ? Colors.redAccent
                                  : const Color(0xFFD4AF37).withValues(alpha: 0.45),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor:
                                        av.color.withValues(alpha: 0.25),
                                    child: Text(
                                      av.emoji,
                                      style: const TextStyle(fontSize: 22),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                u['username']?.toString() ?? '',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                            if (u['role'] == 'admin')
                                              Container(
                                                margin: const EdgeInsets.only(
                                                    left: 6),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFD4AF37),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  'ADMİN',
                                                  style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            if (banned)
                                              Container(
                                                margin: const EdgeInsets.only(
                                                    left: 6),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.redAccent,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  'BANLI',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'Bakiye: ${u['credits']} 🪙',
                                          style: const TextStyle(
                                            color: Color(0xFFFDE047),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              const Divider(color: Colors.white12, height: 1),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF10B981),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                      ),
                                      onPressed: () =>
                                          _showCreditDialog(u, true),
                                      icon: const Icon(Icons.add, size: 16),
                                      label: const Text(
                                        'Kredi Ekle',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.orangeAccent,
                                        side: const BorderSide(
                                            color: Colors.orangeAccent),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                      ),
                                      onPressed: () =>
                                          _showCreditDialog(u, false),
                                      icon: const Icon(Icons.remove, size: 16),
                                      label: const Text(
                                        'Kredi Düş',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    tooltip: 'Şifre Değiştir',
                                    onPressed: () =>
                                        _showPasswordResetDialog(u),
                                    icon: const Icon(Icons.key,
                                        color: Colors.white70),
                                  ),
                                  if (u['role'] != 'admin')
                                    IconButton(
                                      tooltip: banned
                                          ? 'Banı Kaldır'
                                          : 'Hesabı Banla',
                                      onPressed: () async {
                                        await GameService.instance.adminSetBan(
                                          u['id'].toString(),
                                          !banned,
                                        );
                                        _loadDashboard();
                                      },
                                      icon: Icon(
                                        banned ? Icons.lock_open : Icons.block,
                                        color: banned
                                            ? Colors.greenAccent
                                            : Colors.redAccent,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    // TAB 2: SİSTEM KASASI (%5 KOMİSYON & EMOJİ GELİRLERİ)
                    ListView(
                      padding: const EdgeInsets.all(14),
                      children: [
                        _buildStatCard(
                          title: '🏦 %5 Masa Komisyon Geliri',
                          value: '$rake 🪙',
                          subtitle: 'Oyun sonu potlardan kesilen %5 kasa payı',
                          color: const Color(0xFFD4AF37),
                        ),
                        const SizedBox(height: 10),
                        _buildStatCard(
                          title: '🎭 Masa İçi Efekt/Emoji Geliri',
                          value: '$emojiRev 🪙',
                          subtitle:
                              'Bomba, Domates, Gül vb. gönderim gelirleri',
                          color: const Color(0xFF10B981),
                        ),
                        const SizedBox(height: 10),
                        _buildStatCard(
                          title: '🃏 Tamamlanan Maç Sayısı',
                          value: '$totalGames Maç',
                          subtitle:
                              'Toplam Kasa Net Gelir: ${rake + emojiRev} 🪙',
                          color: const Color(0xFF38BDF8),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0E2F21),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFD4AF37)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '🎭 Masa İçi Emoji / Efekt Gönderim Ücreti',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Her efekt gönderiminde oyuncudan $emojiCost Kredi düşülür:',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                children: [5, 10, 25, 50].map((c) {
                                  final active = c == emojiCost;
                                  return ChoiceChip(
                                    label: Text('$c 🪙'),
                                    selected: active,
                                    selectedColor: const Color(0xFFD4AF37),
                                    labelStyle: TextStyle(
                                      color:
                                          active ? Colors.black : Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    onSelected: (_) async {
                                      await GameService.instance
                                          .adminSetEmojiCost(c);
                                      _loadDashboard();
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // TAB 3: HAREKETLER & AKTİF MASALAR
                    ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        const Text(
                          '🟢 Açık Masalar',
                          style: TextStyle(
                            color: Color(0xFFFDE047),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ..._tables.map((t) {
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
                                icon: const Icon(Icons.delete_forever,
                                    color: Colors.redAccent),
                                onPressed: () async {
                                  await GameService.instance
                                      .adminCloseTable(t['id'].toString());
                                  _loadDashboard();
                                },
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                        const Text(
                          '📜 Son Kredi Hareketleri',
                          style: TextStyle(
                            color: Color(0xFFFDE047),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ..._transactions.map((tx) {
                          final amt =
                              int.tryParse(tx['amount'].toString()) ?? 0;
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              amt >= 0
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              color: amt >= 0
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
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
                        }),
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
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E2F21),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }
}
