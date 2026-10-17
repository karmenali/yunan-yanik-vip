import 'dart:async';
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
  int? _draggingIndex;
  double _dragAccumulatedDx = 0;

  bool _showScoreboardModal = false;
  bool _showChatDrawer = false;
  bool _dismissedWinnerModal = false;
  String? _lastSeenWinnerId;

  bool _isPttPressed = false;
  int _lastBeepSecond = -1;

  String? _toastBanner;
  Timer? _toastTimer;
  final List<Map<String, dynamic>> _floatingEffects = [];

  StreamSubscription<String>? _toastSub;
  StreamSubscription<Map<String, dynamic>>? _effectSub;
  final _chatCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Kullanıcının talebi üzerine Yunan Yanık masası da Batak HD gibi DİKEY (Portrait) modda çalışır
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    final gs = GameService.instance;
    gs.addListener(_onGameUpdate);

    _toastSub = gs.toastStreamController.stream.listen((msg) {
      if (!mounted) return;
      _toastTimer?.cancel();
      setState(() => _toastBanner = msg);
      _toastTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _toastBanner = null);
      });
    });

    _effectSub = gs.effectStreamController.stream.listen((eff) {
      if (!mounted) return;
      SoundFx.playCardTap();
      setState(() => _floatingEffects.add(eff));
      Future.delayed(const Duration(milliseconds: 2400), () {
        if (mounted) {
          setState(() => _floatingEffects.remove(eff));
        }
      });
    });
  }

  @override
  void dispose() {
    GameService.instance.removeListener(_onGameUpdate);
    _toastSub?.cancel();
    _effectSub?.cancel();
    _toastTimer?.cancel();
    _chatCtrl.dispose();
    super.dispose();
  }

  void _onGameUpdate() {
    if (!mounted) return;
    final table = GameService.instance.activeTable;

    // Son 5 saniye sesli geri sayım uyarısı
    if (table != null && table.status == 'playing') {
      final rem = table.turnRemainingSeconds;
      if (rem <= 5 && rem > 0 && rem != _lastBeepSecond) {
        _lastBeepSecond = rem;
        SoundFx.playCountdownBeep(urgent: rem <= 2);
      } else if (rem > 5) {
        _lastBeepSecond = -1;
      }
    }

    // Yeni bir şampiyon bilgisi geldiyse modalı tekrar göster
    final winnerId = table?.lastWinnerInfo?['winnerId']?.toString();
    if (winnerId != _lastSeenWinnerId) {
      _lastSeenWinnerId = winnerId;
      _dismissedWinnerModal = false;
    }
    setState(() {});
  }

  void _leaveTable() {
    GameService.instance.leaveCurrentTable();
    Navigator.of(context).pop();
  }

  void _swapLocalHandCards(
    List<CardModel> hand,
    int fromIndex,
    int toIndex,
  ) {
    if (fromIndex < 0 ||
        toIndex < 0 ||
        fromIndex >= hand.length ||
        toIndex >= hand.length ||
        fromIndex == toIndex) {
      return;
    }
    final item = hand.removeAt(fromIndex);
    hand.insert(toIndex, item);
    GameService.instance.reorderHand(
      orderedCardIds: hand.map((c) => c.id).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gs = GameService.instance;
    final table = gs.activeTable;

    if (table == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF061B12),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFFF59E0B)),
              const SizedBox(height: 16),
              const Text(
                'Masa verisi yükleniyor...',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _leaveTable,
                child: const Text('Lobiye Dön'),
              ),
            ],
          ),
        ),
      );
    }

    final seats = table.seats;
    final myUserId = gs.currentUser?.id;
    int mySeatIdx = -1;
    SeatPlayerModel? mySeat;
    for (int i = 0; i < seats.length; i++) {
      if (seats[i] != null && seats[i]!.userId == myUserId) {
        mySeatIdx = i;
        mySeat = seats[i];
        break;
      }
    }

    final status = table.status;
    final isPlaying = status == 'playing';
    final isRoundEnd = status == 'round_summary';
    final isFinished = status == 'finished';
    final isMyTurn = isPlaying && table.currentTurnSeat == mySeatIdx;
    final hasDrawn = table.hasDrawnThisTurn;

    return Scaffold(
      backgroundColor: const Color(0xFF04140D),
      body: Stack(
        children: [
          // 1. ZÜMRÜT YEŞİLİ VIP ÇUHA ARKA PLAN (DİKEY BATAK HD STİLİ)
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.18),
                  radius: 1.05,
                  colors: [
                    Color(0xFF0F5438),
                    Color(0xFF083523),
                    Color(0xFF04180F),
                  ],
                ),
              ),
            ),
          ),

          // 2. ANA DİKEY MASA DÜZENİ
          SafeArea(
            child: Column(
              children: [
                // ÜST BAR (Lobiye Dön, Masa & Pot, 101 Tablo, Ses Ayarı, Bas-Konuş)
                _buildTopBar(table, gs),

                // RAKİPLER VE ORTA ÇUHA ALANI
                Expanded(
                  flex: 47,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        // Rakip Koltukları (2-6 Kişilik Dikey Uyumlu Grid)
                        Expanded(
                          child: _buildOpponentsArea(
                            seats,
                            mySeatIdx,
                            table,
                            gs,
                          ),
                        ),

                        const SizedBox(height: 4),

                        // ORTA MASA MERKEZİ (Gösterge Jokeri + Kapalı Deste + Atılan Kağıt)
                        _buildCenterFeltArea(
                          table,
                          isMyTurn,
                          hasDrawn,
                          mySeatIdx,
                          mySeat,
                          isPlaying,
                        ),
                      ],
                    ),
                  ),
                ),

                // ALT OYUNCU ELİ VE AKSİYON KONTROLLERİ (Batak HD Tarzı Büyük Kartlar)
                Expanded(
                  flex: 53,
                  child: _buildBottomPlayerHandArea(
                    gs,
                    table,
                    mySeat,
                    mySeatIdx,
                    isMyTurn,
                    hasDrawn,
                    isPlaying,
                  ),
                ),
              ],
            ),
          ),

          // 3. UÇAN EFEKT KATMANI (Bomba, Domates, Gül vb.)
          ..._floatingEffects.map((eff) => _buildFloatingEffectOverlay(eff)),

          // 4. BİLGİ / HATA BİLDİRİMİ (Üst Orta)
          if (_toastBanner != null)
            Positioned(
              top: 66,
              left: 20,
              right: 20,
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A2418).withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 12),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.notifications_active,
                          color: Color(0xFFFBBF24),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _toastBanner!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => setState(() => _toastBanner = null),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white70,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 5. EL SONU / 101 PUAN TABLOSU MODALI (Profesyonel Çizelge)
          if (_showScoreboardModal || isRoundEnd)
            _buildScoreboardOverlay(table, mySeat, mySeatIdx, isRoundEnd),

          // 6. MAÇ SONU ŞAMPİYON EKRANI (Kapatılabilir & Koltuk Seçimini Engellemez)
          if (isFinished &&
              table.lastWinnerInfo != null &&
              !_dismissedWinnerModal)
            _buildMatchFinishedOverlay(table, mySeatIdx),

          // 7. SOHBET ÇEKMECESİ
          if (_showChatDrawer) _buildChatDrawer(gs),
        ],
      ),
    );
  }

  // ===========================================================================
  // 1. ÜST BAR (DİKEY EKRAN UYUMLU)
  // ===========================================================================
  Widget _buildTopBar(TableStateModel table, GameService gs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.50),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Row(
        children: [
          // Çıkış Butonu
          InkWell(
            onTap: _leaveTable,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.45),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.redAccent,
                    size: 13,
                  ),
                  SizedBox(width: 3),
                  Text(
                    'Lobi',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 7),

          // Masa Bilgisi ve Ortadaki Ödül Havuzu
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${table.name} ${table.roundNumber > 0 ? '• El #${table.roundNumber}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.emoji_events,
                        color: Color(0xFFF59E0B),
                        size: 12,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          'Ödül: ${table.pot} (${table.entryFee} G.)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFFBBF24),
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 5),

          // 101 Çizelge Butonu
          InkWell(
            onTap: () {
              SoundFx.playCardTap();
              setState(() => _showScoreboardModal = !_showScoreboardModal);
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.leaderboard, color: Color(0xFFFBBF24), size: 14),
                  SizedBox(width: 3),
                  Text(
                    '101',
                    style: TextStyle(
                      color: Color(0xFFFBBF24),
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 5),

          // Ses Aç/Kapat Hızlı Butonu
          InkWell(
            onTap: () async {
              await SoundFx.setSoundEnabled(!SoundFx.soundEnabled);
              if (SoundFx.soundEnabled) SoundFx.playCardTap();
              setState(() {});
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                SoundFx.soundEnabled ? Icons.volume_up : Icons.volume_off,
                color: SoundFx.soundEnabled
                    ? const Color(0xFF34D399)
                    : Colors.white38,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 5),

          // Gerçek Mikrofon Bas-Konuş (Push-To-Talk) Butonu
          GestureDetector(
            onTapDown: (_) async {
              final ok = await gs.startVoicePushToTalk();
              if (mounted) setState(() => _isPttPressed = ok);
            },
            onTapUp: (_) async {
              if (_isPttPressed) {
                setState(() => _isPttPressed = false);
                await gs.stopVoicePushToTalk();
              }
            },
            onTapCancel: () async {
              if (_isPttPressed) {
                setState(() => _isPttPressed = false);
                await gs.stopVoicePushToTalk();
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: _isPttPressed
                    ? const Color(0xFF10B981)
                    : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _isPttPressed ? Colors.greenAccent : Colors.white24,
                ),
                boxShadow: _isPttPressed
                    ? [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.6),
                          blurRadius: 10,
                        )
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isPttPressed ? Icons.mic : Icons.mic_none,
                    color: Colors.white,
                    size: 15,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _isPttPressed ? 'CANLI' : 'Ses',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 5),

          // Sohbet Çekmecesi Butonu
          InkWell(
            onTap: () => setState(() => _showChatDrawer = !_showChatDrawer),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. RAKİP KOLTUKLARI ALANI (DİKEY EKRAN İÇİN KOMPAKT & NET GÖRÜNÜM)
  // ===========================================================================
  Widget _buildOpponentsArea(
    List<SeatPlayerModel?> seats,
    int mySeatIdx,
    TableStateModel table,
    GameService gs,
  ) {
    final List<int> visibleSeatIndices = [];
    for (int i = 0; i < seats.length; i++) {
      visibleSeatIndices.add(i);
    }

    return Center(
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: visibleSeatIndices.map((seatIdx) {
            final seat = seats[seatIdx];
            return _buildCompactSeatCard(seat, seatIdx, mySeatIdx, table, gs);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCompactSeatCard(
    SeatPlayerModel? seat,
    int seatIndex,
    int mySeatIdx,
    TableStateModel table,
    GameService gs,
  ) {
    final isEmpty = seat == null;
    final isMe = seatIndex == mySeatIdx && mySeatIdx != -1;
    final isCurrentTurn =
        table.status == 'playing' && table.currentTurnSeat == seatIndex;

    // Boş koltuk görünümü
    if (isEmpty) {
      final canSit = mySeatIdx == -1 &&
          (table.status == 'waiting' || table.status == 'finished');
      return GestureDetector(
        onTap: canSit
            ? () {
                SoundFx.playCardTap();
                gs.sitAtSeat(seatIndex);
              }
            : null,
        child: Container(
          width: 104,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: canSit
                ? const Color(0xFFF59E0B).withValues(alpha: 0.16)
                : Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: canSit
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.75)
                  : Colors.white12,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                canSit ? Icons.event_seat : Icons.chair_outlined,
                color: canSit ? const Color(0xFFFBBF24) : Colors.white30,
                size: 16,
              ),
              const SizedBox(height: 2),
              Text(
                canSit ? 'OTUR #${seatIndex + 1}' : 'Boş #${seatIndex + 1}',
                style: TextStyle(
                  color: canSit ? const Color(0xFFFBBF24) : Colors.white38,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final avatar = VipAvatar.fromKey(seat.avatar);
    final isEliminated = seat.isEliminated;
    final isSpeaking = gs.activeVoiceSpeakerUsername == seat.username;

    return GestureDetector(
      onTap: () {
        if (!isMe && mySeatIdx != -1) {
          _showEffectPickerDialog(seat.userId, seat.username);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 112,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isMe
              ? const Color(0xFF103826).withValues(alpha: 0.95)
              : const Color(0xFF0A2418).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCurrentTurn
                ? const Color(0xFFF59E0B)
                : isSpeaking
                    ? const Color(0xFF10B981)
                    : isMe
                        ? const Color(0xFF34D399).withValues(alpha: 0.7)
                        : isEliminated
                            ? Colors.redAccent.withValues(alpha: 0.6)
                            : Colors.white24,
            width: isCurrentTurn || isSpeaking ? 2.0 : 1.1,
          ),
          boxShadow: isCurrentTurn
              ? [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                    blurRadius: 10,
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(avatar.emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    isMe ? '${seat.username} (Sen)' : seat.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isMe ? const Color(0xFFFDE047) : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                    ),
                  ),
                ),
                if (isSpeaking)
                  const Icon(
                    Icons.volume_up,
                    color: Color(0xFF10B981),
                    size: 13,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 101 Ceza Puanı
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: seat.totalScore >= 85
                        ? Colors.redAccent.withValues(alpha: 0.28)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '${seat.totalScore}/101',
                    style: TextStyle(
                      color: seat.totalScore >= 85
                          ? Colors.redAccent
                          : const Color(0xFFFBBF24),
                      fontWeight: FontWeight.w900,
                      fontSize: 9.5,
                    ),
                  ),
                ),
                if (table.status == 'playing')
                  Row(
                    children: [
                      const Icon(Icons.style, color: Colors.white60, size: 11),
                      const SizedBox(width: 2),
                      Text(
                        '${seat.cardCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    seat.isReady ? 'HAZIR' : 'Bekliyor',
                    style: TextStyle(
                      color: seat.isReady
                          ? const Color(0xFF34D399)
                          : Colors.white38,
                      fontWeight: FontWeight.bold,
                      fontSize: 9.5,
                    ),
                  ),
              ],
            ),
            if (isCurrentTurn) ...[
              const SizedBox(height: 3),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '⏳ ${table.turnRemainingSeconds} sn',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontSize: 9,
                  ),
                ),
              ),
            ] else if (seat.rebuyCount > 0) ...[
              const SizedBox(height: 2),
              Text(
                '🔄 ${seat.rebuyCount}x Giriş',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 8.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 3. ORTA ÇUHA MERKEZİ (GÖSTERGE JOKERİ DESTENİN YANINDA %100 GÖRÜNÜR!)
  // ===========================================================================
  Widget _buildCenterFeltArea(
    TableStateModel table,
    bool isMyTurn,
    bool hasDrawn,
    int mySeatIdx,
    SeatPlayerModel? mySeat,
    bool isPlaying,
  ) {
    final gs = GameService.instance;
    final indicator = table.indicatorCard;
    final drawCount = table.drawPileCount;
    final discardTop = table.topDiscardCard;
    final canDrawNow = isMyTurn && !hasDrawn;

    if (!isPlaying) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '🃏 YUNAN YANIK VIP MASASI',
              style: TextStyle(
                color: Color(0xFFFBBF24),
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              mySeatIdx == -1
                  ? 'Oyuna katılmak için yukarıdaki boş koltuklardan birine dokunun.'
                  : 'En az 2 oyuncu HAZIR olduğunda 10\'ar kağıt otomatik dağıtılır.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            if (mySeat != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      SoundFx.playCardTap();
                      gs.toggleReady();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: mySeat.isReady
                          ? const Color(0xFF059669)
                          : const Color(0xFFF59E0B),
                      foregroundColor:
                          mySeat.isReady ? Colors.white : Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 9,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Icon(
                      mySeat.isReady
                          ? Icons.check_circle
                          : Icons.play_arrow_rounded,
                      size: 17,
                    ),
                    label: Text(
                      mySeat.isReady
                          ? 'HAZIRSINIZ (Bekleniyor...)'
                          : 'MAÇ İÇİN HAZIR OL',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () {
                      SoundFx.playCardTap();
                      gs.standUp();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                    ),
                    child: const Text('Kalk', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    // OYUN SIRASINDA ORTA MASA:
    // Sol: GÖSTERGE JOKERİ (Tam açık ve çok net — destenin hemen yanında!)
    // Orta: KAPALI DESTE (Dokununca kart çeker)
    // Sağ: ATILAN KAĞIT (Son atılan kart)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: canDrawNow
              ? const Color(0xFF10B981).withValues(alpha: 0.75)
              : Colors.white.withValues(alpha: 0.12),
          width: canDrawNow ? 1.8 : 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 1. GÖSTERGE JOKERİ (Destenin hemen yanında tam görünür!)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.65),
                  ),
                ),
                child: Text(
                  indicator != null
                      ? '👑 JOKER: ${indicator.rankLabel}'
                      : '👑 JOKER',
                  style: const TextStyle(
                    color: Color(0xFFFBBF24),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              if (indicator != null)
                PlayingCardWidget(
                  card: indicator,
                  wildRank: table.wildRank,
                  width: 58,
                  height: 84,
                )
              else
                const SizedBox(width: 58, height: 84),
            ],
          ),

          const SizedBox(width: 16),

          // 2. KAPALI DESTE (Sıra oyuncudaysa parlak çerçeveli)
          GestureDetector(
            onTap: canDrawNow ? () => gs.drawCard() : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: canDrawNow
                        ? const Color(0xFF10B981)
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    canDrawNow
                        ? '👇 KAĞIT ÇEK ($drawCount)'
                        : 'DESTE ($drawCount)',
                    style: TextStyle(
                      color: canDrawNow ? Colors.black : Colors.white70,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: canDrawNow
                        ? [
                            BoxShadow(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.65),
                              blurRadius: 14,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: const CardBackWidget(
                    width: 60,
                    height: 86,
                    badgeText: 'ÇEK',
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // 3. ATILAN KAĞIT YIĞINI
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'ATILAN KAĞIT',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              discardTop != null
                  ? PlayingCardWidget(
                      card: discardTop,
                      wildRank: table.wildRank,
                      width: 58,
                      height: 84,
                    )
                  : Container(
                      width: 58,
                      height: 84,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Center(
                        child: Text(
                          'BOŞ',
                          style: TextStyle(
                            color: Colors.white30,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 4. ALT OYUNCU ELİ (BATAK HD STİLİ BÜYÜK YELPAZE + SÜRÜKLE BIRAK)
  // ===========================================================================
  Widget _buildBottomPlayerHandArea(
    GameService gs,
    TableStateModel table,
    SeatPlayerModel? mySeat,
    int mySeatIdx,
    bool isMyTurn,
    bool hasDrawn,
    bool isPlaying,
  ) {
    final hand = table.myHand;
    final meldedIds = table.meldedCardIds;
    final canFinish = table.canFinishNow;
    final deadwoodPoints = table.currentHandPenalty;
    final remainingSec = table.turnRemainingSeconds;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.15),
            Colors.black.withValues(alpha: 0.65),
          ],
        ),
        border: Border(
          top: BorderSide(
            color: isMyTurn
                ? const Color(0xFFF59E0B).withValues(alpha: 0.65)
                : Colors.white.withValues(alpha: 0.1),
            width: isMyTurn ? 1.5 : 1.0,
          ),
        ),
      ),
      child: Column(
        children: [
          // ÜST BİLGİ & BASİT PUAN ROZETİ + DİZ BUTONU
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                // Basit ve Şık Elde Kalan Sayı Rozeti
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: canFinish
                        ? const Color(0xFF10B981).withValues(alpha: 0.25)
                        : const Color(0xFF0F291E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: canFinish
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B).withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        canFinish
                            ? Icons.verified_rounded
                            : Icons.calculate_outlined,
                        color: canFinish
                            ? const Color(0xFF34D399)
                            : const Color(0xFFFBBF24),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        canFinish
                            ? 'EL AÇMAYA HAZIR (0p)'
                            : 'Elde: $deadwoodPoints Puan',
                        style: TextStyle(
                          color: canFinish
                              ? const Color(0xFF34D399)
                              : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 6),

                // Sıra ve Geri Sayım Göstergesi
                if (isPlaying && isMyTurn)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: remainingSec <= 5
                          ? Colors.redAccent
                          : const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      !hasDrawn
                          ? '⏳ $remainingSec sn • Kağıt Çek'
                          : '⏳ $remainingSec sn • Kağıt At',
                      style: TextStyle(
                        color:
                            remainingSec <= 5 ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 10.5,
                      ),
                    ),
                  ),

                const Spacer(),

                // Otomatik Per / Seri Dizme Butonu
                if (hand.isNotEmpty)
                  InkWell(
                    onTap: () {
                      SoundFx.playCardTap();
                      gs.reorderHand();
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_fix_high,
                            color: Color(0xFFFBBF24),
                            size: 13,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Otomatik Diz',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // KARTLAR ALANI (Batak HD Gibi Elde Büyük Yelpaze + Kolay Sürükleme)
          Expanded(
            child: hand.isEmpty
                ? Center(
                    child: Text(
                      mySeatIdx == -1
                          ? 'Oynamak için yukarıdan bir koltuğa oturun'
                          : 'Yeni elin başlaması bekleniyor...',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  )
                : _buildInteractiveFanHand(
                    hand: hand,
                    meldedIds: meldedIds,
                    wildRank: table.wildRank,
                    winningDiscardCardId: table.winningDiscardCardId,
                    lastDrawnCardId: gs.lastDrawnCardId,
                  ),
          ),

          // ALT HAMLE BUTONLARI (Desteden Çek / Seçili Kağıdı At / El Aç Bitir)
          if (isPlaying && mySeatIdx != -1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isMyTurn && !hasDrawn)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => gs.drawCard(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text(
                          'DESTEDEN KAĞIT ÇEK',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  if (isMyTurn && hasDrawn) ...[
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _selectedCardId != null
                            ? () {
                                gs.discardCard(_selectedCardId!);
                                setState(() => _selectedCardId = null);
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          disabledBackgroundColor: Colors.white12,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.upload_rounded, size: 18),
                        label: Text(
                          _selectedCardId != null
                              ? 'SEÇİLİ KAĞIDI AT'
                              : 'ATILACAK KAĞIDA DOKUNUN',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (isMyTurn && canFinish) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        gs.declareFinish(
                          discardCardId:
                              _selectedCardId ?? table.winningDiscardCardId,
                        );
                        setState(() => _selectedCardId = null);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(
                        Icons.local_fire_department,
                        size: 18,
                      ),
                      label: const Text(
                        'EL AÇ / BİTİR',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Batak HD tarzı: Kartlar dikey ekranda 2 kademeli kavisli yelpaze olarak
  /// çok büyük, net okunaklı ve parmakla sağa-sola kolayca sürüklenebilir!
  Widget _buildInteractiveFanHand({
    required List<CardModel> hand,
    required Set<String> meldedIds,
    required int wildRank,
    required String? winningDiscardCardId,
    required String? lastDrawnCardId,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;

        final int topCount = (hand.length / 2).ceil();
        final int bottomCount = hand.length - topCount;

        final double cardW = (maxW / 5.3).clamp(68.0, 86.0);
        final double cardH = (cardW * 1.42).clamp(96.0, 122.0);

        Widget buildRow(int startIdx, int count) {
          if (count <= 0) return const SizedBox.shrink();
          final overlapStep = count > 1
              ? ((maxW - 22 - cardW) / (count - 1)).clamp(38.0, cardW + 6.0)
              : cardW;
          final totalRowWidth = cardW + overlapStep * (count - 1);
          final startX = (maxW - totalRowWidth) / 2;

          return SizedBox(
            width: maxW,
            height: cardH + 20,
            child: Stack(
              clipBehavior: Clip.none,
              children: List.generate(count, (localIdx) {
                final globalIdx = startIdx + localIdx;
                final card = hand[globalIdx];
                final cardId = card.id;
                final isSelected = _selectedCardId == cardId;
                final isBeingDragged = _draggingIndex == globalIdx;
                final isMelded = meldedIds.contains(cardId);
                final isNewlyDrawn = lastDrawnCardId == cardId;
                final isWinningDiscard = winningDiscardCardId == cardId;

                // Hafif Batak HD yelpaze kavisi
                final normalized =
                    count > 1 ? (localIdx / (count - 1)) - 0.5 : 0.0;
                final angle = normalized * 0.13;
                final arcY = (normalized * normalized) * 9.0;

                return AnimatedPositioned(
                  key: ValueKey(cardId),
                  duration: Duration(milliseconds: isBeingDragged ? 0 : 180),
                  curve: Curves.easeOutCubic,
                  left: startX + (localIdx * overlapStep),
                  top: 8 + arcY - (isSelected ? 12 : 0),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      SoundFx.playCardTap();
                      setState(() {
                        if (_selectedCardId == null) {
                          _selectedCardId = cardId;
                        } else if (_selectedCardId == cardId) {
                          _selectedCardId = null;
                        } else {
                          final oldIdx = hand.indexWhere(
                            (c) => c.id == _selectedCardId,
                          );
                          if (oldIdx != -1) {
                            _swapLocalHandCards(hand, oldIdx, globalIdx);
                          }
                          _selectedCardId = cardId;
                        }
                      });
                    },
                    onPanStart: (_) {
                      SoundFx.playCardTap();
                      setState(() {
                        _draggingIndex = globalIdx;
                        _selectedCardId = cardId;
                        _dragAccumulatedDx = 0;
                      });
                    },
                    onPanUpdate: (details) {
                      if (_draggingIndex == null) return;
                      _dragAccumulatedDx += details.delta.dx;
                      const threshold = 34.0;
                      if (_dragAccumulatedDx.abs() >= threshold) {
                        final dir = _dragAccumulatedDx > 0 ? 1 : -1;
                        final targetIdx =
                            (_draggingIndex! + dir).clamp(0, hand.length - 1);
                        if (targetIdx != _draggingIndex) {
                          _swapLocalHandCards(hand, _draggingIndex!, targetIdx);
                          setState(() {
                            _draggingIndex = targetIdx;
                            _dragAccumulatedDx = 0;
                          });
                        }
                      }
                    },
                    onPanEnd: (_) {
                      setState(() {
                        _draggingIndex = null;
                        _dragAccumulatedDx = 0;
                      });
                    },
                    child: Transform.rotate(
                      angle: angle,
                      child: PlayingCardWidget(
                        card: card,
                        wildRank: wildRank,
                        width: cardW,
                        height: cardH,
                        isSelected: isSelected || isBeingDragged,
                        isMelded: isMelded,
                        isNewlyDrawn: isNewlyDrawn,
                        isWinningDiscardCandidate: isWinningDiscard,
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }

        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: SizedBox(
            height: maxH,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                buildRow(0, topCount),
                Transform.translate(
                  offset: const Offset(0, -14),
                  child: buildRow(topCount, bottomCount),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // 5. PROFESYONEL 101 PUAN TABLOSU & YENİDEN GİRİŞ (RE-BUY) MODALI
  // ===========================================================================
  Widget _buildScoreboardOverlay(
    TableStateModel table,
    SeatPlayerModel? mySeat,
    int mySeatIdx,
    bool isRoundEnd,
  ) {
    final gs = GameService.instance;
    final seatedPlayers =
        table.seats.whereType<SeatPlayerModel>().toList();
    final showdownMap = {
      for (final s in table.lastShowdown) s.userId: s,
    };
    final myShowdown =
        mySeat != null ? showdownMap[mySeat.userId] : null;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.82),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 28),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460, maxHeight: 590),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0A2318),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.65),
                width: 1.5,
              ),
              boxShadow: const [
                BoxShadow(color: Colors.black87, blurRadius: 24),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Başlık
                Row(
                  children: [
                    const Icon(
                      Icons.leaderboard_rounded,
                      color: Color(0xFFFBBF24),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isRoundEnd
                            ? 'EL #${table.roundNumber} SONUCU & 101 TABLOSU'
                            : '101 CEZA PUAN ÇİZELGESİ',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                    if (!isRoundEnd)
                      IconButton(
                        onPressed: () =>
                            setState(() => _showScoreboardModal = false),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                  ],
                ),
                const Divider(color: Colors.white12),

                // Profesyonel Tablo Başlığı
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          'OYUNCU',
                          style: TextStyle(
                            color: Colors.white60,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'SON EL',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white60,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'TOPLAM',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white60,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'DURUM',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: Colors.white60,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // Oyuncu Satırları
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: seatedPlayers.length,
                    separatorBuilder: (_, _) =>
                        const Divider(color: Colors.white10, height: 8),
                    itemBuilder: (context, idx) {
                      final s = seatedPlayers[idx];
                      final sd = showdownMap[s.userId];
                      final total = s.totalScore;
                      final lastDelta = sd?.roundPenalty;
                      final eliminated = s.isEliminated;
                      final rebuyCount = s.rebuyCount;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: eliminated
                              ? Colors.redAccent.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.username,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (rebuyCount > 0)
                                    Text(
                                      '🔄 $rebuyCount kez yeniden girdi',
                                      style: const TextStyle(
                                        color: Colors.orangeAccent,
                                        fontSize: 10,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                lastDelta == null
                                    ? '-'
                                    : lastDelta == 0
                                        ? '0 (Açtı)'
                                        : '+$lastDelta',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: lastDelta == 0
                                      ? const Color(0xFF34D399)
                                      : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '$total',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: total >= 101
                                      ? Colors.redAccent
                                      : const Color(0xFFFBBF24),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: eliminated
                                        ? Colors.redAccent
                                            .withValues(alpha: 0.25)
                                        : const Color(0xFF10B981)
                                            .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    eliminated ? '🔥 YANDI' : 'DEVAM',
                                    style: TextStyle(
                                      color: eliminated
                                          ? Colors.redAccent
                                          : const Color(0xFF34D399),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 10),
                Text(
                  'Toplam ${table.scoreHistory.length} el oynandı • Havuz: ${table.pot} Kredi',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),

                // Eğer El Sonuysa: Yeniden Katıl (Re-buy) veya Sıradaki El Butonu
                if (isRoundEnd && mySeat != null) ...[
                  const SizedBox(height: 12),
                  if (myShowdown != null && myShowdown.canRebuy)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => gs.rebuyIntoMatch(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF59E0B),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.replay_circle_filled),
                          label: Text(
                            'OYUNA TEKRAR DAHİL OL (${myShowdown.rebuyMultiplier}x = ${myShowdown.rebuyCost} Kredi • ${myShowdown.rebuyTargetScore} Puanla)',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (!mySeat.isEliminated)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => gs.toggleReady(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.skip_next_rounded),
                        label: Text(
                          mySeat.isReady
                              ? 'HAZIRSINIZ (Diğerleri Bekleniyor...)'
                              : 'SIRADAKİ EL İÇİN HAZIRIM',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 6. MAÇ SONU ŞAMPİYON OVERLAY (KAPATILABİLİR, KOLTUKLARI ASLA ENGELLEMEZ!)
  // ===========================================================================
  Widget _buildMatchFinishedOverlay(
    TableStateModel table,
    int mySeatIdx,
  ) {
    final winner = table.lastWinnerInfo!;
    final winnerName = winner['winnerUsername'] ?? 'Şampiyon';
    final prize = winner['winnerPrize'] ?? 0;
    final totalPot = winner['totalPot'] ?? 0;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.78),
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF123828), Color(0xFF071A12)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFF59E0B), width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black87, blurRadius: 24),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.emoji_events_rounded,
                  color: Color(0xFFFBBF24),
                  size: 54,
                ),
                const SizedBox(height: 8),
                const Text(
                  'MAÇ TAMAMLANDI!',
                  style: TextStyle(
                    color: Color(0xFFFBBF24),
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Kazanan: $winnerName',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '🏆 Net Ödül (%95): +$prize Kredi',
                        style: const TextStyle(
                          color: Color(0xFF34D399),
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Toplam Masa Havuzu: $totalPot Kredi',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() => _dismissedWinnerModal = true);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Masayı Gör'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() => _dismissedWinnerModal = true);
                          if (mySeatIdx != -1) {
                            GameService.instance.toggleReady();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          mySeatIdx != -1 ? 'Yeni Maça Hazır Ol' : 'Koltuk Seç',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 7. EFEKT GÖNDERME VE SOHBET ÇEKMECESİ
  // ===========================================================================
  void _showEffectPickerDialog(String targetUserId, String targetName) {
    final cost = GameService.instance.emojiCost;
    final effects = [
      {'type': 'rose', 'emoji': '🌹', 'name': 'Gül Gönder'},
      {'type': 'clap', 'emoji': '👏', 'name': 'Alkışla'},
      {'type': 'laugh', 'emoji': '😂', 'name': 'Kahkaha'},
      {'type': 'tomato', 'emoji': '🍅', 'name': 'Domates At'},
      {'type': 'bomb', 'emoji': '💣', 'name': 'Bomba At'},
      {'type': 'cry', 'emoji': '😭', 'name': 'Mendil Gönder'},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A2418),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$targetName oyuncusuna efekt gönder',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: effects.map((e) {
                return InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    GameService.instance.sendInteractiveEffect(
                      targetUserId,
                      e['type'].toString(),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 100,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      children: [
                        Text(
                          e['emoji'].toString(),
                          style: const TextStyle(fontSize: 24),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          e['name'].toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '$cost Kredi',
                          style: const TextStyle(
                            color: Color(0xFFFBBF24),
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

  Widget _buildFloatingEffectOverlay(Map<String, dynamic> eff) {
    final emojiMap = {
      'bomb': '💣💥',
      'tomato': '🍅💦',
      'rose': '🌹✨',
      'clap': '👏🎉',
      'laugh': '😂🔥',
      'cry': '😭💧',
    };
    final key = eff['effectKey']?.toString() ?? '';
    final emoji = emojiMap[key] ?? '✨';
    return Positioned(
      top: 130,
      left: 30,
      right: 30,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0xFFF59E0B)),
            ),
            child: Text(
              '$emoji  ${eff['fromUsername']} ➔ ${eff['targetUsername']}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatDrawer(GameService gs) {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: 290,
      child: Material(
        color: const Color(0xFF071B12).withValues(alpha: 0.98),
        elevation: 16,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.forum, color: Color(0xFFFBBF24), size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Masa Sohbeti',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () =>
                          setState(() => _showChatDrawer = false),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: gs.tableChatMessages.length,
                  itemBuilder: (ctx, i) {
                    final m = gs.tableChatMessages[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${m['username'] ?? 'Oyuncu'}: ',
                              style: const TextStyle(
                                color: Color(0xFFFBBF24),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            TextSpan(
                              text: m['message']?.toString() ?? '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatCtrl,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Mesaj yaz...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: () {
                        if (_chatCtrl.text.trim().isNotEmpty) {
                          gs.sendChatMessage(_chatCtrl.text);
                          _chatCtrl.clear();
                        }
                      },
                      icon: const Icon(Icons.send, color: Color(0xFFF59E0B)),
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
}
