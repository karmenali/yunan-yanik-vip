import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/game_models.dart';
import '../services/game_service.dart';
import '../services/sound_fx.dart';
import '../widgets/playing_card_widget.dart';

class TableScreen extends StatefulWidget {
  final String tableId;

  const TableScreen({super.key, required this.tableId});

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  String? _selectedCardId;
  int _localRemainingSeconds = 30;
  Timer? _countdownTimer;
  StreamSubscription? _effectSub;
  StreamSubscription? _toastSub;

  // Uçan emoji / efekt animasyonu durumu
  Map<String, dynamic>? _activeFlyingEffect;
  bool _isPttPressed = false;

  @override
  void initState() {
    super.initState();
    // Oyun masası açıldığında tam ekran Yatay (Landscape) moda geç
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    GameService.instance.addListener(_onServiceUpdate);

    _effectSub = GameService.instance.effectStreamController.stream.listen((eff) {
      SoundFx.playCelebration();
      if (!mounted) return;
      setState(() => _activeFlyingEffect = eff);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _activeFlyingEffect = null);
      });
    });

    _toastSub = GameService.instance.toastStreamController.stream.listen((msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF0E2F21),
        ),
      );
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final table = GameService.instance.activeTable;
      if (table == null) return;
      if (table.status == 'playing' || table.status == 'round_summary') {
        if (_localRemainingSeconds > 0) {
          setState(() {
            _localRemainingSeconds -= 1;
          });
          // Son 5 saniye sesli geri sayım uyarısı!
          if (table.status == 'playing' &&
              _localRemainingSeconds > 0 &&
              _localRemainingSeconds <= 5) {
            SoundFx.playCountdownBeep(urgent: _localRemainingSeconds <= 2);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _effectSub?.cancel();
    _toastSub?.cancel();
    GameService.instance.removeListener(_onServiceUpdate);
    // Masadan çıkılırken Lobi için tekrar Dikey (Portrait) moda dön
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  void _onServiceUpdate() {
    final table = GameService.instance.activeTable;
    if (table != null) {
      _localRemainingSeconds = table.turnRemainingSeconds;
    }
    if (mounted) setState(() {});
  }

  void _onCardTapped(CardModel tappedCard, List<CardModel> hand) {
    SoundFx.playCardTap();
    if (_selectedCardId == null) {
      setState(() => _selectedCardId = tappedCard.id);
      return;
    }

    if (_selectedCardId == tappedCard.id) {
      setState(() => _selectedCardId = null);
      return;
    }

    // Seçili kağıt ile tıklanan kağıdın yerini değiştir (Yelpaze içinde kağıt dizme)
    final ids = hand.map((c) => c.id).toList();
    final idx1 = ids.indexOf(_selectedCardId!);
    final idx2 = ids.indexOf(tappedCard.id);
    if (idx1 != -1 && idx2 != -1) {
      final temp = ids[idx1];
      ids[idx1] = ids[idx2];
      ids[idx2] = temp;
      setState(() => _selectedCardId = null);
      GameService.instance.reorderHand(orderedCardIds: ids);
    } else {
      setState(() => _selectedCardId = tappedCard.id);
    }
  }

  void _showEffectPickerForPlayer(SeatPlayerModel target) {
    final cost = GameService.instance.emojiCost;
    final effects = [
      {'key': 'bomb', 'icon': '💣', 'name': 'Bomba'},
      {'key': 'tomato', 'icon': '🍅', 'name': 'Domates'},
      {'key': 'rose', 'icon': '🌹', 'name': 'Gül'},
      {'key': 'clap', 'icon': '👏', 'name': 'Alkış'},
      {'key': 'laugh', 'icon': '😂', 'name': 'Kahkaha'},
      {'key': 'cry', 'icon': '😭', 'name': 'Ağlama'},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E2F21),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🎭 ${target.username} Oyuncusuna Efekt Gönder (Her biri $cost 🪙)',
              style: const TextStyle(
                color: Color(0xFFFDE047),
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 10,
              children: effects.map((e) {
                return InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    GameService.instance.sendInteractiveEffect(
                      target.userId,
                      e['key']!,
                    );
                  },
                  child: Container(
                    width: 88,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD4AF37)),
                    ),
                    child: Column(
                      children: [
                        Text(e['icon']!, style: const TextStyle(fontSize: 28)),
                        const SizedBox(height: 4),
                        Text(
                          e['name']!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '$cost 🪙',
                          style: const TextStyle(
                            color: Color(0xFFFDE047),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showScoreboardDialog(TableStateModel table) {
    final seatedPlayers = table.seats.whereType<SeatPlayerModel>().toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A261A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFD4AF37), width: 1.8),
        ),
        title: const Row(
          children: [
            Text('📊 101 YANIK ÇİZELGESİ (SKOR TABLOSU)',
                style: TextStyle(color: Color(0xFFFDE047), fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Güncel Toplamlar
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: seatedPlayers.map((p) {
                    final av = VipAvatar.fromKey(p.avatar);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: p.isEliminated
                            ? Colors.red.shade900.withValues(alpha: 0.5)
                            : Colors.black38,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: p.isEliminated
                              ? Colors.redAccent
                              : const Color(0xFFD4AF37),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text('${av.emoji} ${p.username}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          Text(
                            '${p.totalScore} / 101',
                            style: TextStyle(
                              color: p.isEliminated
                                  ? Colors.redAccent
                                  : const Color(0xFFFDE047),
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          if (p.rebuyCount > 0)
                            Text(
                              'Re-buy: ${p.rebuyCount}x',
                              style: const TextStyle(
                                  color: Colors.orangeAccent, fontSize: 10),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.white24),
                if (table.scoreHistory.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Henüz tamamlanan el bulunmuyor.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  )
                else
                  ...table.scoreHistory.map((round) {
                    final rNum = round['roundNumber'];
                    final scores =
                        Map<String, dynamic>.from(round['scoresByUser'] ?? {});
                    return ListTile(
                      dense: true,
                      title: Text(
                        '$rNum. El Sonucu',
                        style: const TextStyle(
                          color: Color(0xFFFDE047),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Wrap(
                        spacing: 12,
                        children: seatedPlayers.map((p) {
                          final sc = scores[p.userId];
                          return Text(
                            '${p.username}: ${sc != null ? '+$sc' : '-'}',
                            style: const TextStyle(color: Colors.white70),
                          );
                        }).toList(),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat', style: TextStyle(color: Color(0xFFFDE047))),
          ),
        ],
      ),
    );
  }

  void _showChatSheet() {
    final msgCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A261A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final messages = GameService.instance.tableChatMessages;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 16,
              right: 16,
              top: 12,
            ),
            child: SizedBox(
              height: 280,
              child: Column(
                children: [
                  const Text(
                    '💬 Masa İçi Sohbet',
                    style: TextStyle(
                      color: Color(0xFFFDE047),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(color: Colors.white24),
                  Expanded(
                    child: messages.isEmpty
                        ? const Center(
                            child: Text(
                              'Henüz mesaj yok. İlk mesajı sen yaz!',
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                        : ListView.builder(
                            itemCount: messages.length,
                            itemBuilder: (_, i) {
                              final m = messages[i];
                              final av = VipAvatar.fromKey(m['avatar']?.toString());
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '${av.emoji} ${m['username']}: ',
                                        style: const TextStyle(
                                          color: Color(0xFFFDE047),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      TextSpan(
                                        text: m['message']?.toString() ?? '',
                                        style: const TextStyle(color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: msgCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Mesajınızı yazın...',
                            hintStyle: TextStyle(color: Colors.white54),
                          ),
                          onSubmitted: (val) {
                            GameService.instance.sendChatMessage(val);
                            msgCtrl.clear();
                            setSheetState(() {});
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send, color: Color(0xFFD4AF37)),
                        onPressed: () {
                          GameService.instance.sendChatMessage(msgCtrl.text);
                          msgCtrl.clear();
                          setSheetState(() {});
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = GameService.instance;
    final table = service.activeTable;
    final user = service.currentUser;

    if (table == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF05160F),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Color(0xFFD4AF37)),
              const SizedBox(height: 12),
              const Text('Masaya bağlanılıyor...',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Lobiye Dön',
                    style: TextStyle(color: Color(0xFFFDE047))),
              ),
            ],
          ),
        ),
      );
    }

    final mySeat = table.seats
        .whereType<SeatPlayerModel>()
        .cast<SeatPlayerModel?>()
        .firstWhere((s) => s?.userId == user?.id, orElse: () => null);
    final bool isMyTurn =
        table.status == 'playing' && mySeat != null && table.currentTurnSeat == mySeat.seatIndex;

    return Scaffold(
      backgroundColor: const Color(0xFF04120C),
      body: Stack(
        children: [
          // 1. ARKA PLAN VE YEŞİL ÇUHA MASA ALANI
          Column(
            children: [
              // ÜST BAR: Masa Bilgisi, Pot, Bakiye, Skor Çizelgesi, Ses & Sohbet
              _buildTopHeader(table, user, mySeat),

              // ORTA OYUN MASASI VE KOLTUKLAR
              Expanded(
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // VIP Oval Zümrüt Çuha Masa
                        Container(
                          width: constraints.maxWidth * 0.78,
                          height: constraints.maxHeight * 0.78,
                          decoration: BoxDecoration(
                            gradient: const RadialGradient(
                              center: Alignment.center,
                              radius: 0.85,
                              colors: [
                                Color(0xFF155E3F),
                                Color(0xFF0B3B26),
                                Color(0xFF062316),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(180),
                            border: Border.all(
                              color: const Color(0xFFD4AF37),
                              width: 5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.75),
                                blurRadius: 25,
                                spreadRadius: 6,
                              ),
                            ],
                          ),
                        ),

                        // MASA ORTASI: Kapalı Deste + Yarısı Görünür Gösterge Jokeri + Atılan Kağıt + Pot
                        _buildTableCenterArea(table, isMyTurn),

                        // KOLTUKLAR (2 - 6 Kişilik Dinamik Yerleşim)
                        ..._buildSeatWidgets(
                          table,
                          constraints.maxWidth,
                          constraints.maxHeight,
                          user?.id,
                        ),
                      ],
                    );
                  },
                ),
              ),

              // ALT ALAN: KLASİK YELPAZE (CURVED FAN) OYUNCU ELİ VE AKSİYON BUTONLARI
              if (mySeat != null && table.status == 'playing' && !mySeat.isEliminated)
                _buildBottomPlayerHandFan(table, mySeat, isMyTurn)
              else if (table.status == 'waiting' || table.status == 'finished')
                _buildWaitingBottomBar(table, mySeat),
            ],
          ),

          // 2. UÇAN EMOJİ / EFEKT ANİMASYONU (Bomba, Domates, Gül vb.)
          if (_activeFlyingEffect != null)
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.4, end: 1.2),
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                builder: (_, scale, _) => Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFFACC15), width: 2),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _activeFlyingEffect!['effectIcon']?.toString() ?? '🎭',
                          style: const TextStyle(fontSize: 54),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_activeFlyingEffect!['senderUsername']} ➔ ${_activeFlyingEffect!['effectName']} gönderdi!',
                          style: const TextStyle(
                            color: Color(0xFFFDE047),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 3. EL SONU AÇIK EL GÖSTERİMİ (SHOWDOWN) & RE-BUY (1x, 2x, 3x...) EKRANI
          if (table.status == 'round_summary' && table.lastShowdown.isNotEmpty)
            _buildShowdownAndRebuyOverlay(table, user?.id),

          // 4. OYUN SONU ŞAMPİYON KUTLAMASI (%95 KAZANAN / %5 KASA)
          if (table.status == 'finished' && table.lastWinnerInfo != null)
            _buildMatchWinnerOverlay(table),
        ],
      ),
    );
  }

  Widget _buildTopHeader(
    TableStateModel table,
    UserModel? user,
    SeatPlayerModel? mySeat,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF082217),
        border: Border(
          bottom: BorderSide(color: Color(0xFFD4AF37), width: 1.2),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Lobiye Dön
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              ),
              onPressed: () {
                GameService.instance.leaveCurrentTable();
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Lobi', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 10),

            Flexible(
              child: Text(
                table.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                ),
              ),
            ),
            const SizedBox(width: 8),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF143D2B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD4AF37)),
              ),
              child: Text(
                '🏆 Pot: ${table.pot} 🪙  |  Giriş: ${table.entryFee} 🪙',
                style: const TextStyle(
                  color: Color(0xFFFDE047),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),

            const Spacer(),

            // Sesli Sohbet Aktif Konuşan Göstergesi
            if (GameService.instance.activeVoiceSpeakerUsername != null)
              Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade800,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mic, color: Colors.white, size: 15),
                    const SizedBox(width: 4),
                    Text(
                      '${GameService.instance.activeVoiceSpeakerUsername} konuşuyor...',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ),

            // Oyuncunun Kendi Kredi Bakiyesi
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Bakiyem: ${user?.credits ?? 0} 🪙',
                style: const TextStyle(
                  color: Color(0xFFFDE047),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 101 Çizelgesi Butonu
            IconButton(
              tooltip: '101 Puan Çizelgesi',
              onPressed: () => _showScoreboardDialog(table),
              icon: const Icon(Icons.leaderboard, color: Color(0xFFFDE047), size: 20),
            ),

            // Yazılı Sohbet Butonu
            IconButton(
              tooltip: 'Masa Sohbeti',
              onPressed: _showChatSheet,
              icon: const Icon(Icons.chat_bubble_outline,
                  color: Colors.white, size: 20),
            ),

            // Bas-Konuş (Push-to-Talk) Mikrofon Butonu
            GestureDetector(
              onTapDown: (_) {
                setState(() => _isPttPressed = true);
                GameService.instance.setVoicePushToTalk(true);
              },
              onTapUp: (_) {
                setState(() => _isPttPressed = false);
                GameService.instance.setVoicePushToTalk(false);
              },
              onTapCancel: () {
                setState(() => _isPttPressed = false);
                GameService.instance.setVoicePushToTalk(false);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _isPttPressed
                      ? Colors.redAccent
                      : const Color(0xFF143D2B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFD4AF37)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isPttPressed ? Icons.mic : Icons.mic_none,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isPttPressed ? 'Konuşuluyor' : 'Bas-Konuş',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /**
   * MASA ORTASI:
   * - Kapalı Deste + En altta yarısı görünen Gösterge Jokeri
   * - Atılan Kağıt (Iskarta)
   * - Ödül Havuzu (Pot)
   */
  Widget _buildTableCenterArea(TableStateModel table, bool isMyTurn) {
    final canDraw = isMyTurn && !table.hasDrawnThisTurn && table.drawPileCount > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Ödül Havuzu & El Bilgisi
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD4AF37), width: 1.2),
          ),
          child: Text(
            table.status == 'playing'
                ? 'EL #${table.roundNumber}  •  JOKER SAYISI: ${table.indicatorCard?.rankLabel ?? '-'}  •  KASA POT: ${table.pot} 🪙'
                : 'MASA GİRİŞİ: ${table.entryFee} 🪙  •  ŞAMPİYON %95 ALIR',
            style: const TextStyle(
              color: Color(0xFFFDE047),
              fontWeight: FontWeight.w900,
              fontSize: 11.5,
            ),
          ),
        ),
        const SizedBox(height: 10),

        if (table.status == 'playing')
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // KAPALI DESTE + ALTINDA YARISI GÖRÜNÜR GÖSTERGE JOKERİ
              GestureDetector(
                onTap: canDraw
                    ? () {
                        SoundFx.playCardTap();
                        GameService.instance.drawCard();
                      }
                    : null,
                child: SizedBox(
                  width: 115,
                  height: 92,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // En altta yarısı dışarı taşan Gösterge Jokeri!
                      if (table.indicatorCard != null)
                        Positioned(
                          left: 38,
                          top: 8,
                          child: Transform.rotate(
                            angle: 0.18,
                            child: PlayingCardWidget(
                              card: table.indicatorCard!,
                              wildRank: table.wildRank,
                              width: 58,
                              height: 82,
                            ),
                          ),
                        ),
                      // Üstteki Kapalı Deste
                      Positioned(
                        left: 0,
                        child: Container(
                          decoration: canDraw
                              ? BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFACC15)
                                          .withValues(alpha: 0.7),
                                      blurRadius: 14,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                )
                              : null,
                          child: CardBackWidget(
                            width: 60,
                            height: 86,
                            badgeText: '${table.drawPileCount}',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 24),

              // ATILAN SON KAĞIT (ISKARTA ALANI - ALINAMAZ, GÖRSEL)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (table.topDiscardCard != null)
                    PlayingCardWidget(
                      card: table.topDiscardCard!,
                      wildRank: table.wildRank,
                      width: 60,
                      height: 86,
                    )
                  else
                    Container(
                      width: 60,
                      height: 86,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Center(
                        child: Text(
                          'Atılan\nKağıt',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, fontSize: 10),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  /**
   * 2 ile 6 kişilik koltukları oval masa etrafına yerleştirir
   */
  List<Widget> _buildSeatWidgets(
    TableStateModel table,
    double maxW,
    double maxH,
    String? myUserId,
  ) {
    final int count = table.maxPlayers;
    final List<Widget> widgets = [];

    // Koltuk açıları (Oval masa etrafında dengeli dağılım)
    for (int i = 0; i < count; i++) {
      final double angle = (2 * math.pi * i / count) + (math.pi / 2);
      final double rx = maxW * 0.39;
      final double ry = maxH * 0.34;

      final double cx = (maxW / 2) + rx * math.cos(angle) - 62;
      final double cy = (maxH / 2) + ry * math.sin(angle) - 36;

      final seatPlayer = i < table.seats.length ? table.seats[i] : null;
      final bool isTurn =
          table.status == 'playing' && table.currentTurnSeat == i;

      widgets.add(
        Positioned(
          left: cx.clamp(8.0, maxW - 132.0),
          top: cy.clamp(6.0, maxH - 82.0),
          child: _buildSingleSeatNode(
            table: table,
            seatIndex: i,
            occupant: seatPlayer,
            isTurn: isTurn,
            myUserId: myUserId,
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _buildSingleSeatNode({
    required TableStateModel table,
    required int seatIndex,
    required SeatPlayerModel? occupant,
    required bool isTurn,
    required String? myUserId,
  }) {
    if (occupant == null) {
      final canSit = table.status == 'waiting' || table.status == 'finished';
      return GestureDetector(
        onTap: canSit ? () => GameService.instance.sitAtSeat(seatIndex) : null,
        child: Container(
          width: 120,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.6),
              width: 1.4,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🪑 Boş Koltuk',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
              if (canSit)
                const Text(
                  'OTUR',
                  style: TextStyle(
                    color: Color(0xFFFDE047),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final av = VipAvatar.fromKey(occupant.avatar);
    final bool isMe = occupant.userId == myUserId;
    final bool urgentTime = isTurn && _localRemainingSeconds <= 5;

    return GestureDetector(
      onTap: !isMe ? () => _showEffectPickerForPlayer(occupant) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 128,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: occupant.isEliminated
              ? Colors.red.shade900.withValues(alpha: 0.7)
              : isTurn
                  ? const Color(0xFF1E4D38)
                  : const Color(0xFF0A2419).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: urgentTime
                ? Colors.redAccent
                : isTurn
                    ? const Color(0xFFFACC15)
                    : const Color(0xFFD4AF37).withValues(alpha: 0.55),
            width: isTurn ? 2.6 : 1.3,
          ),
          boxShadow: isTurn
              ? [
                  BoxShadow(
                    color: (urgentTime
                            ? Colors.redAccent
                            : const Color(0xFFFACC15))
                        .withValues(alpha: 0.5),
                    blurRadius: 12,
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(av.emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    occupant.username,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (!isMe)
                  const Text('🎭', style: TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  occupant.isEliminated
                      ? '🔥 YANDI (${occupant.totalScore})'
                      : 'Puan: ${occupant.totalScore}',
                  style: TextStyle(
                    color: occupant.isEliminated
                        ? Colors.redAccent
                        : const Color(0xFFFDE047),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (table.status == 'waiting' || table.status == 'finished')
                  Text(
                    occupant.isReady ? '✅ Hazır' : '⏳',
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 10),
                  )
                else if (isTurn)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: urgentTime ? Colors.red : const Color(0xFFD97706),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${_localRemainingSeconds}s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /**
   * ALT BAR: Bekleme durumunda Koltuktan Kalk / Oyuna Başla (Hazır)
   */
  Widget _buildWaitingBottomBar(TableStateModel table, SeatPlayerModel? mySeat) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: const Color(0xFF071D13),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (mySeat == null)
            const Text(
              '🪑 Oyuna katılmak için masadaki boş koltuklardan birine tıklayın.',
              style: TextStyle(color: Color(0xFFFDE047), fontSize: 13),
            )
          else ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white38),
              ),
              onPressed: () => GameService.instance.standUp(),
              icon: const Icon(Icons.event_seat, size: 18),
              label: const Text('Koltuktan Kalk'),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: mySeat.isReady
                    ? Colors.orange.shade800
                    : const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () => GameService.instance.toggleReady(),
              icon: Icon(mySeat.isReady ? Icons.pause : Icons.play_arrow),
              label: Text(
                mySeat.isReady
                    ? 'HAZIR BEKLENİYOR...'
                    : 'OYUNA BAŞLA (${table.entryFee} 🪙)',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /**
   * KLASİK YELPAZE (CURVED FAN) OYUNCU ELİ VE AKSİYON BUTONLARI
   */
  Widget _buildBottomPlayerHandFan(
    TableStateModel table,
    SeatPlayerModel mySeat,
    bool isMyTurn,
  ) {
    final hand = table.myHand;
    final int n = hand.length;

    return Container(
      height: 138,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0xFF051810).withValues(alpha: 0.96),
          ],
        ),
      ),
      child: Row(
        children: [
          // SOL PANEL: Otomatik Diz & El Ceza Durumu
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF143D2B),
                  foregroundColor: const Color(0xFFFDE047),
                  side: const BorderSide(color: Color(0xFFD4AF37)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () {
                  SoundFx.playCardTap();
                  GameService.instance.reorderHand();
                },
                icon: const Icon(Icons.auto_fix_high, size: 16),
                label: const Text(
                  'Otomatik Diz',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Boşta Ceza: ${table.currentHandPenalty} Puan',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          // ORTA ALAN: KLASİK YELPAZE (CURVED FAN) KAĞIT DİZİLİMİ
          Expanded(
            child: Center(
              child: SizedBox(
                width: math.max(320, n * 48.0 + 40),
                height: 125,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: List.generate(n, (i) {
                    final card = hand[i];
                    final double mid = (n - 1) / 2.0;
                    final double offsetFromCenter = i - mid;
                    // Klasik yelpaze açısı ve kavis yüksekliği
                    final double angle = offsetFromCenter * 0.045;
                    final double archDrop =
                        (offsetFromCenter * offsetFromCenter) * 1.4;
                    final bool isSelected = _selectedCardId == card.id;
                    final bool isMelded = table.meldedCardIds.contains(card.id);
                    final bool isWinDiscard =
                        table.winningDiscardCardId == card.id;

                    return AnimatedPositioned(
                      duration: const Duration(milliseconds: 180),
                      left: (i * 42.0) + 16,
                      bottom: (isSelected ? 18.0 : 4.0) - archDrop.clamp(0.0, 16.0),
                      child: Transform.rotate(
                        angle: angle,
                        child: PlayingCardWidget(
                          card: card,
                          wildRank: table.wildRank,
                          isSelected: isSelected,
                          isMelded: isMelded,
                          isWinningDiscardCandidate: isWinDiscard,
                          width: 64,
                          height: 94,
                          onTap: () => _onCardTapped(card, hand),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),

          // SAĞ PANEL: HAMLE BUTONLARI (Desteden Çek / Kağıt At / El Aç Bitir)
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isMyTurn && !table.hasDrawnThisTurn)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFACC15),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () {
                    SoundFx.playCardTap();
                    GameService.instance.drawCard();
                  },
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text(
                    'DESTEDEN ÇEK',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ),

              if (isMyTurn && table.hasDrawnThisTurn) ...[
                if (table.canFinishNow)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      onPressed: () {
                        SoundFx.playCelebration();
                        GameService.instance.declareFinish(
                          discardCardId:
                              _selectedCardId ?? table.winningDiscardCardId,
                        );
                      },
                      icon: const Icon(Icons.local_fire_department, size: 18),
                      label: const Text(
                        '🔥 EL AÇ / BİTİR!',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  onPressed: _selectedCardId == null
                      ? null
                      : () {
                          final cardId = _selectedCardId!;
                          setState(() => _selectedCardId = null);
                          SoundFx.playCardTap();
                          GameService.instance.discardCard(cardId);
                        },
                  icon: const Icon(Icons.upload, size: 16),
                  label: Text(
                    _selectedCardId == null ? 'Atılacak Kağıdı Seç' : 'KAĞIDI AT',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],

              if (!isMyTurn)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '⏳ Sıra Bekleniyor...',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /**
   * EL SONU AÇIK EL GÖSTERİMİ (SHOWDOWN) & YANAN OYUNCU İÇİN RE-BUY (1x, 2x, 3x...) EKRANI
   */
  Widget _buildShowdownAndRebuyOverlay(
    TableStateModel table,
    String? myUserId,
  ) {
    final myResult = table.lastShowdown
        .cast<ShowdownPlayerResultModel?>()
        .firstWhere((r) => r?.userId == myUserId, orElse: () => null);

    return Container(
      color: Colors.black.withValues(alpha: 0.84),
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Container(
          width: 680,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF0A261A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD4AF37), width: 2),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '🃏 ${table.roundNumber}. EL SONU — AÇIK ELLER & PUANLAR',
                    style: const TextStyle(
                      color: Color(0xFFFDE047),
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD97706),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Sonraki El: ${_localRemainingSeconds}s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white24),

              // Tüm oyuncuların açık elleri (Perler + Boşta kalanlar)
              Expanded(
                child: ListView.builder(
                  itemCount: table.lastShowdown.length,
                  itemBuilder: (ctx, i) {
                    final sd = table.lastShowdown[i];
                    final av = VipAvatar.fromKey(sd.avatar);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sd.burnedThisRound
                              ? Colors.redAccent
                              : sd.roundPenalty == 0
                                  ? const Color(0xFF10B981)
                                  : Colors.white24,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${av.emoji} ${sd.username} ${sd.roundPenalty == 0 ? '🏆 (ELİ AÇTI!)' : ''}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '+${sd.roundPenalty} Ceza  ➔  Toplam: ${sd.newTotalScore} / 101 ${sd.burnedThisRound ? '🔥 YANDI!' : ''}',
                                style: TextStyle(
                                  color: sd.burnedThisRound
                                      ? Colors.redAccent
                                      : const Color(0xFFFDE047),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                // Per olmuş gruplar
                                ...sd.melds.map((meld) {
                                  return Container(
                                    margin: const EdgeInsets.only(right: 10),
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF065F46)
                                          .withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: meld
                                          .map(
                                            (c) => Padding(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 1.5),
                                              child: PlayingCardWidget(
                                                card: c,
                                                wildRank: table.wildRank,
                                                isMelded: true,
                                                width: 40,
                                                height: 58,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  );
                                }),
                                // Boşta kalan (ceza yazılan) kağıtlar
                                ...sd.unmelded.map(
                                  (c) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 2),
                                    child: PlayingCardWidget(
                                      card: c,
                                      wildRank: table.wildRank,
                                      width: 40,
                                      height: 58,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Eğer oyuncu bu elde 101 olup YANDIYSA ve Re-buy hakkı açıksa (Son 2 oyuncu değilse):
              if (myResult != null && myResult.burnedThisRound && myResult.canRebuy)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFACC15), width: 2),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '🔥 101 Puana Ulaştınız! (${myResult.rebuyMultiplier}. Giriş: ${myResult.rebuyMultiplier}x Masa Kredisi = ${myResult.rebuyCost} 🪙 ödeyerek ${myResult.rebuyTargetScore} puanla devam edebilirsiniz)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFACC15),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onPressed: () => GameService.instance.rebuyIntoMatch(),
                        icon: const Icon(Icons.replay_circle_filled),
                        label: Text(
                          'OYUNA GERİ DÖN (${myResult.rebuyCost} 🪙)',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /**
   * OYUN SONU ŞAMPİYON KUTLAMASI (%95 KAZANAN / %5 KASA)
   */
  Widget _buildMatchWinnerOverlay(TableStateModel table) {
    final info = table.lastWinnerInfo!;
    final av = VipAvatar.fromKey(info['avatar']?.toString());

    return Container(
      color: Colors.black.withValues(alpha: 0.82),
      child: Center(
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0A261A),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFFACC15), width: 2.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🏆 MASA ŞAMPİYONU 🏆',
                  style: TextStyle(
                      color: Color(0xFFFDE047),
                      fontSize: 20,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Text(av.emoji, style: const TextStyle(fontSize: 52)),
              const SizedBox(height: 6),
              Text(
                info['username']?.toString() ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      'Toplam Biriken Pot: ${info['totalPot']} 🪙',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      'Kasa Komisyonu (%5): -${info['houseRake']} 🪙',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const Divider(color: Colors.white24),
                    Text(
                      'Net Kazanç (%95): +${info['prizeWon']} 🪙',
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4AF37),
                  foregroundColor: Colors.black,
                ),
                onPressed: () => GameService.instance.toggleReady(),
                child: const Text(
                  'Yeni Maç İçin Hazır Ol',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
