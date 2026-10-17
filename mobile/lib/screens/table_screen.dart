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
  // 60 FPS Sıfır Gecikmeli Yerel Kart Listesi ve Sürükleme Durumu
  List<CardModel> _localHand = [];
  String? _selectedCardId;
  String? _draggingCardId;
  double _dragFingerX = 0;

  bool _showScoreboardModal = false;
  bool _showChatDrawer = false;
  bool _dismissedWinnerModal = false;
  String? _lastSeenWinnerId;

  // Sesli Sohbet (Hem Basılı Tut-Konuş hem Dokun-Konuş desteği)
  bool _isVoiceRecording = false;
  DateTime? _pttDownTime;
  Timer? _pttAutoStopTimer;
  int _recordingSeconds = 0;
  Timer? _recordingTickTimer;

  // Canlı Sayaç (Sunucu + Yerel Saniyelik Akıcı Senkronizasyon)
  Timer? _localSecondTicker;
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
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    final gs = GameService.instance;
    gs.addListener(_onGameUpdate);
    _syncLocalHandFromServer();

    // Yerel 1 saniyelik sayaç: Sunucu paketi gecikse bile ekran sayacının asla donmamasını garanti eder
    _localSecondTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final table = gs.activeTable;
      if (table != null &&
          (table.status == 'playing' || table.status == 'round_summary')) {
        setState(() {});
      }
    });

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
    _localSecondTicker?.cancel();
    _pttAutoStopTimer?.cancel();
    _recordingTickTimer?.cancel();
    _toastSub?.cancel();
    _effectSub?.cancel();
    _toastTimer?.cancel();
    _chatCtrl.dispose();
    super.dispose();
  }

  void _syncLocalHandFromServer() {
    final table = GameService.instance.activeTable;
    if (table == null) {
      _localHand = [];
      return;
    }
    // Kullanıcı şu an parmağıyla kart sürüklüyorsa ve kart sayısı değişmediyse
    // parmağın altındaki sırayı bozma!
    if (_draggingCardId != null &&
        _localHand.length == table.myHand.length &&
        _localHand.map((c) => c.id).toSet().containsAll(
              table.myHand.map((c) => c.id),
            )) {
      return;
    }
    _localHand = List<CardModel>.from(table.myHand);
  }

  void _onGameUpdate() {
    if (!mounted) return;
    final table = GameService.instance.activeTable;
    _syncLocalHandFromServer();

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

    final winnerId = table?.lastWinnerInfo?['userId']?.toString();
    if (winnerId != _lastSeenWinnerId) {
      _lastSeenWinnerId = winnerId;
      _dismissedWinnerModal = false;
    }
    setState(() {});
  }

  void _leaveTable() {
    if (_isVoiceRecording) {
      _stopVoiceRecording();
    }
    GameService.instance.leaveCurrentTable();
    Navigator.of(context).pop();
  }

  // ===========================================================================
  // 🎙️ KESİNTİSİZ TELSİZ SESLİ SOHBET (BASILI TUT VEYA DOKUN-KONUŞ)
  // ===========================================================================
  Future<void> _onMicPointerDown() async {
    _pttDownTime = DateTime.now();
    if (_isVoiceRecording) {
      // Zaten dokun-konuş modunda açıksa, ikinci dokunuşta kaydı bitir ve gönder!
      await _stopVoiceRecording();
      return;
    }

    final started = await GameService.instance.startVoicePushToTalk();
    if (!mounted) return;
    if (started) {
      _pttAutoStopTimer?.cancel();
      _recordingTickTimer?.cancel();
      setState(() {
        _isVoiceRecording = true;
        _recordingSeconds = 0;
      });
      _recordingTickTimer =
          Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || !_isVoiceRecording) {
          timer.cancel();
          return;
        }
        setState(() => _recordingSeconds += 1);
      });
      // Maksimum 8 saniye sonra otomatik gönder
      _pttAutoStopTimer = Timer(const Duration(seconds: 8), () {
        if (_isVoiceRecording) {
          _stopVoiceRecording();
        }
      });
    }
  }

  Future<void> _onMicPointerUp() async {
    if (!_isVoiceRecording || _pttDownTime == null) return;
    final heldMs = DateTime.now().difference(_pttDownTime!).inMilliseconds;
    // Eğer kullanıcı 400ms'den uzun basılı tuttuysa (Bas-Konuş), parmağını çekince hemen gönder.
    // Eğer 400ms'den kısa dokunduysa (Dokun-Konuş), kayda devam etsin (tekrar dokununca veya 5 sn sonra gönderecek)!
    if (heldMs >= 400) {
      await _stopVoiceRecording();
    } else {
      _pttAutoStopTimer?.cancel();
      _pttAutoStopTimer = Timer(const Duration(seconds: 5), () {
        if (_isVoiceRecording) {
          _stopVoiceRecording();
        }
      });
    }
  }

  Future<void> _stopVoiceRecording() async {
    _pttAutoStopTimer?.cancel();
    _recordingTickTimer?.cancel();
    if (!_isVoiceRecording) return;
    setState(() {
      _isVoiceRecording = false;
      _recordingSeconds = 0;
    });
    await GameService.instance.stopVoicePushToTalk();
  }

  String _formatDuration(int totalSeconds) {
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
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
                'Masa hazırlanıyor...',
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
      backgroundColor: const Color(0xFF06140E),
      body: Stack(
        children: [
          // 1. ZYNGA 3D MAUN & ZÜMRÜT ÇUHA MASA ARKA PLAN GÖRSELİ (table_bg.jpg)
          Positioned.fill(
            child: Image.asset(
              'assets/images/table_bg.jpg',
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.15),
            ),
          ),

          // Hafif karanlık atmosferik çerçeve geçişi (okunabilirliği artırır)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.72),
                  ],
                  stops: const [0.0, 0.48, 1.0],
                ),
              ),
            ),
          ),

          // 2. ANA DİKEY ZYNGA MASA DÜZENİ
          SafeArea(
            child: Column(
              children: [
                // ÜST VIP BAR + MAÇ SÜRESİ & CANLI SAYAÇ BANNERI
                _buildZyngaTopBar(table, gs),

                // ORTA CASINO MASASI (Koltuklar, Altın Fişler, Gösterge Jokeri, Deste ve Atılan Kağıt)
                Expanded(
                  flex: 56,
                  child: _buildZyngaCasinoTableArea(
                    table: table,
                    seats: seats,
                    mySeatIdx: mySeatIdx,
                    mySeat: mySeat,
                    isPlaying: isPlaying,
                    isMyTurn: isMyTurn,
                    hasDrawn: hasDrawn,
                    gs: gs,
                  ),
                ),

                // ALT OYUNCU ELİ (TEK SIRA GENİŞ YELPAZE + 60 FPS SÜRÜKLEME + 4 ZYNGA BUTONU)
                Expanded(
                  flex: 44,
                  child: _buildZyngaBottomHandAndControls(
                    gs: gs,
                    table: table,
                    mySeat: mySeat,
                    mySeatIdx: mySeatIdx,
                    isMyTurn: isMyTurn,
                    hasDrawn: hasDrawn,
                    isPlaying: isPlaying,
                  ),
                ),
              ],
            ),
          ),

          // 3. AKTİF SES KAYDI GÖSTERGESİ (Konuşurken Ekran Üstünde Parlayan Telsiz Barı)
          if (_isVoiceRecording)
            Positioned(
              top: 98,
              left: 24,
              right: 24,
              child: Center(
                child: GestureDetector(
                  onTap: _stopVoiceRecording,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFDC2626), Color(0xFF991B1B)],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: const Color(0xFFFDE047),
                        width: 1.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withValues(alpha: 0.65),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.fiber_manual_record,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '🎙️ SES KAYDEDİLİYOR (${_recordingSeconds}s) • Göndermek İçin Dokun / Bırak',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 4. UÇAN EFEKT KATMANI
          ..._floatingEffects.map((eff) => _buildFloatingEffectOverlay(eff)),

          // 5. BİLGİ / HATA BİLDİRİMİ
          if (_toastBanner != null && !_isVoiceRecording)
            Positioned(
              top: 96,
              left: 20,
              right: 20,
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A2418).withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                      boxShadow: const [
                        BoxShadow(color: Colors.black87, blurRadius: 12),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.notifications_active,
                          color: Color(0xFFFBBF24),
                          size: 16,
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
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 6. EL SONU / 101 PUAN TABLOSU MODALI
          if (_showScoreboardModal || isRoundEnd)
            _buildScoreboardOverlay(table, mySeat, mySeatIdx, isRoundEnd),

          // 7. MAÇ SONU ŞAMPİYON EKRANI
          if (isFinished &&
              table.lastWinnerInfo != null &&
              !_dismissedWinnerModal)
            _buildMatchFinishedOverlay(table, mySeatIdx),

          // 8. SOHBET ÇEKMECESİ
          if (_showChatDrawer) _buildChatDrawer(gs),
        ],
      ),
    );
  }

  // ===========================================================================
  // 1. ZYNGA ÜST VIP BAR + TRAPEZOİD MAÇ SÜRESİ SAYACI (MATCH 09:05)
  // ===========================================================================
  Widget _buildZyngaTopBar(TableStateModel table, GameService gs) {
    final matchTimeStr = _formatDuration(table.matchElapsedSeconds);
    final isPlaying = table.status == 'playing';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E130C), Color(0xFF2D1B10), Color(0xFF1E130C)],
            ),
            border: Border(
              bottom: BorderSide(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.75),
                width: 1.5,
              ),
            ),
            boxShadow: const [
              BoxShadow(color: Colors.black87, blurRadius: 8),
            ],
          ),
          child: Row(
            children: [
              // Yuvarlak Altın Çerçeveli Geri Butonu (<)
              InkWell(
                onTap: _leaveTable,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3E2723), Color(0xFF1B0F0D)],
                    ),
                    border: Border.all(
                      color: const Color(0xFFD4AF37),
                      width: 1.6,
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Color(0xFFFDE047),
                    size: 15,
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // VIP Rozeti
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E3A8A), Color(0xFF0F172A)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFFD4AF37),
                    width: 1.4,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('👑', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 85),
                      child: Text(
                        table.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFDE047),
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),

              // Masa Ödül Havuzu (Pot) Rozeti
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.65),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🪙', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${table.pot > 0 ? table.pot : table.entryFee}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 5),

              // 101 Puan Tablosu Butonu
              InkWell(
                onTap: () {
                  SoundFx.playCardTap();
                  setState(() => _showScoreboardModal = !_showScoreboardModal);
                },
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFD4AF37)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.leaderboard,
                        color: Color(0xFFFDE047),
                        size: 13,
                      ),
                      SizedBox(width: 3),
                      Text(
                        '101',
                        style: TextStyle(
                          color: Color(0xFFFDE047),
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 5),

              // TELSİZ MİKROFON (Hem Basılı Tut hem Dokun-Konuş - Kesintisiz Listener!)
              Listener(
                onPointerDown: (_) => _onMicPointerDown(),
                onPointerUp: (_) => _onMicPointerUp(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: _isVoiceRecording
                        ? const LinearGradient(
                            colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
                          )
                        : const LinearGradient(
                            colors: [Color(0xFF15803D), Color(0xFF064E3B)],
                          ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _isVoiceRecording
                          ? Colors.white
                          : const Color(0xFFD4AF37),
                      width: 1.4,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isVoiceRecording ? Icons.mic : Icons.mic_none_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _isVoiceRecording ? 'CANLI' : 'Ses',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 5),

              // Ses Aç/Kapat & Sohbet İkonları
              InkWell(
                onTap: () async {
                  await SoundFx.setSoundEnabled(!SoundFx.soundEnabled);
                  if (SoundFx.soundEnabled) SoundFx.playCardTap();
                  setState(() {});
                },
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black54,
                    border: Border.all(color: const Color(0xFFD4AF37)),
                  ),
                  child: Icon(
                    SoundFx.soundEnabled ? Icons.volume_up : Icons.volume_off,
                    color: SoundFx.soundEnabled
                        ? const Color(0xFFFDE047)
                        : Colors.white38,
                    size: 15,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => setState(() => _showChatDrawer = !_showChatDrawer),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black54,
                    border: Border.all(color: const Color(0xFFD4AF37)),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline,
                    color: Color(0xFFFDE047),
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ZYNGA ALTIN TRAPEZOİD SÜRE BANDI ("MAÇ 09:05 • HAMLE 28s")
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3.5),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2B1911), Color(0xFF422719), Color(0xFF2B1911)],
            ),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(14),
            ),
            border: Border.all(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.8),
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 6),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.timer_outlined,
                color: Color(0xFFFDE047),
                size: 13,
              ),
              const SizedBox(width: 5),
              Text(
                isPlaying || table.roundNumber > 0
                    ? 'MAÇ SÜRESİ $matchTimeStr  •  EL #${table.roundNumber}'
                    : 'MASA BEKLİYOR (${table.entryFee} KREDİ)',
                style: const TextStyle(
                  color: Color(0xFFFDE047),
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.7,
                ),
              ),
              if (isPlaying) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: table.turnRemainingSeconds <= 5
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${table.turnRemainingSeconds} sn',
                    style: TextStyle(
                      color: table.turnRemainingSeconds <= 5
                          ? Colors.white
                          : Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 2. ZYNGA CASINO MASASI (MASA KENARI AVATARLARI + ORTA JOKER/DESTE/ATILAN)
  // ===========================================================================
  Widget _buildZyngaCasinoTableArea({
    required TableStateModel table,
    required List<SeatPlayerModel?> seats,
    required int mySeatIdx,
    required SeatPlayerModel? mySeat,
    required bool isPlaying,
    required bool isMyTurn,
    required bool hasDrawn,
    required GameService gs,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        // Koltukları masa etrafındaki 6 noktaya (Sol-Üst, Sağ-Üst, Sol-Orta, Sağ-Orta, Sol-Alt, Sağ-Alt) yerleştir
        final seatPositions = _calculateTableRimPositions(seats.length, w, h);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // ÜST ORTA: ALTIN FİŞ YIĞINI (POT GÖSTERGESİ)
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.7),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🪙🪙', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 5),
                      Text(
                        'ÖDÜL HAVUZU: ${table.pot} KREDİ',
                        style: const TextStyle(
                          color: Color(0xFFFDE047),
                          fontWeight: FontWeight.w900,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // MASA ORTASI: GÖSTERGE JOKERİ + KAPALI DESTE + ATILAN KAĞIT (veya Hazır Ol ekranı)
            Align(
              alignment: const Alignment(0, 0.08),
              child: _buildCenterTableFeltCards(
                table: table,
                isPlaying: isPlaying,
                isMyTurn: isMyTurn,
                hasDrawn: hasDrawn,
                mySeatIdx: mySeatIdx,
                mySeat: mySeat,
                gs: gs,
              ),
            ),

            // MASA KENARINDAKİ DÜairesel ZYNGA OYUNCU AVATARLARI VE CANLI SAYAÇ HALKALARI
            for (int i = 0; i < seats.length; i++)
              Positioned(
                left: seatPositions[i].dx,
                top: seatPositions[i].dy,
                child: _buildZyngaCircularSeatAvatar(
                  seat: seats[i],
                  seatIndex: i,
                  mySeatIdx: mySeatIdx,
                  table: table,
                  gs: gs,
                ),
              ),
          ],
        );
      },
    );
  }

  List<Offset> _calculateTableRimPositions(int count, double w, double h) {
    const double avatarWidth = 92.0;
    final double leftX = 6.0;
    final double rightX = w - avatarWidth - 6.0;

    if (count == 2) {
      return [
        Offset(leftX + 14, h * 0.08),
        Offset(rightX - 14, h * 0.08),
      ];
    } else if (count == 3) {
      return [
        Offset(leftX + 10, h * 0.06),
        Offset(rightX - 10, h * 0.06),
        Offset(leftX, h * 0.48),
      ];
    } else if (count == 4) {
      return [
        Offset(leftX + 10, h * 0.05),
        Offset(rightX - 10, h * 0.05),
        Offset(leftX, h * 0.48),
        Offset(rightX, h * 0.48),
      ];
    } else if (count == 5) {
      return [
        Offset(leftX + 12, h * 0.03),
        Offset(rightX - 12, h * 0.03),
        Offset(leftX, h * 0.36),
        Offset(rightX, h * 0.36),
        Offset(leftX + 6, h * 0.68),
      ];
    } else {
      return [
        Offset(leftX + 12, h * 0.03),
        Offset(rightX - 12, h * 0.03),
        Offset(leftX, h * 0.36),
        Offset(rightX, h * 0.36),
        Offset(leftX + 8, h * 0.68),
        Offset(rightX - 8, h * 0.68),
      ];
    }
  }

  /// Zynga UI Mockup'ındaki gibi Dairesel Avatar + Parlayan Geri Sayım Halkası + Alt Puan Etiketi
  Widget _buildZyngaCircularSeatAvatar({
    required SeatPlayerModel? seat,
    required int seatIndex,
    required int mySeatIdx,
    required TableStateModel table,
    required GameService gs,
  }) {
    final isEmpty = seat == null;
    final isMe = seatIndex == mySeatIdx && mySeatIdx != -1;
    final isCurrentTurn =
        table.status == 'playing' && table.currentTurnSeat == seatIndex;

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
        child: SizedBox(
          width: 92,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.55),
                  border: Border.all(
                    color: canSit
                        ? const Color(0xFFFACC15)
                        : Colors.white.withValues(alpha: 0.25),
                    width: canSit ? 2.0 : 1.2,
                  ),
                ),
                child: Icon(
                  canSit ? Icons.add_rounded : Icons.event_seat_outlined,
                  color: canSit ? const Color(0xFFFDE047) : Colors.white38,
                  size: 24,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24, width: 0.8),
                ),
                child: Text(
                  canSit ? 'OTUR #${seatIndex + 1}' : 'Boş #${seatIndex + 1}',
                  style: TextStyle(
                    color: canSit ? const Color(0xFFFDE047) : Colors.white54,
                    fontWeight: FontWeight.w800,
                    fontSize: 9.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final avatar = VipAvatar.fromKey(seat.avatar);
    final isSpeaking = gs.activeVoiceSpeakerUsername == seat.username;
    final progress = isCurrentTurn
        ? (table.turnRemainingSeconds / 30.0).clamp(0.0, 1.0)
        : 0.0;
    final ringColor = table.turnRemainingSeconds <= 5
        ? const Color(0xFFEF4444)
        : table.turnRemainingSeconds <= 12
            ? const Color(0xFFFACC15)
            : const Color(0xFF22C55E);

    return GestureDetector(
      onTap: () {
        if (!isMe && mySeatIdx != -1) {
          _showEffectPickerDialog(seat.userId, seat.username);
        }
      },
      child: SizedBox(
        width: 92,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Dairesel Avatar + 360 Derece Canlı Geri Sayım Halkası
            Stack(
              alignment: Alignment.center,
              children: [
                if (isCurrentTurn)
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: ringColor.withValues(alpha: 0.65),
                          blurRadius: 14,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 4.2,
                      backgroundColor: Colors.black45,
                      valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                    ),
                  ),
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        avatar.color.withValues(alpha: 0.55),
                        const Color(0xFF0F172A),
                      ],
                    ),
                    border: Border.all(
                      color: isSpeaking
                          ? const Color(0xFF22C55E)
                          : isMe
                              ? const Color(0xFFFACC15)
                              : const Color(0xFFD4AF37),
                      width: 2.0,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      avatar.emoji,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),

                // Elindeki Kağıt Sayısı Rozeti (Sağ Üst)
                if (table.status == 'playing' && !seat.isEliminated)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFD4AF37),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '${seat.cardCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                  ),

                // Konuşuyor İkonu
                if (isSpeaking)
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF10B981),
                      ),
                      child: const Icon(
                        Icons.volume_up,
                        color: Colors.white,
                        size: 11,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),

            // İsim ve Puan Etiketi (Zynga Stil Altın Çerçeveli Siyah Kapsül)
            Container(
              width: 90,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isCurrentTurn
                      ? ringColor
                      : const Color(0xFFD4AF37).withValues(alpha: 0.65),
                  width: 1.1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isMe ? '${seat.username} (Sen)' : seat.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isMe ? const Color(0xFFFDE047) : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🪙', style: TextStyle(fontSize: 9)),
                      const SizedBox(width: 3),
                      Text(
                        seat.isEliminated
                            ? 'YANDI (${seat.totalScore})'
                            : '${seat.totalScore}/101',
                        style: TextStyle(
                          color: seat.isEliminated || seat.totalScore >= 85
                              ? Colors.redAccent
                              : const Color(0xFFFDE047),
                          fontWeight: FontWeight.w900,
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Masa Ortası: Gösterge Jokeri (Sol) + Kapalı Deste (Sağ) + Atılan Kağıt (Alt Orta)
  Widget _buildCenterTableFeltCards({
    required TableStateModel table,
    required bool isPlaying,
    required bool isMyTurn,
    required bool hasDrawn,
    required int mySeatIdx,
    required SeatPlayerModel? mySeat,
    required GameService gs,
  }) {
    if (!isPlaying) {
      return Container(
        width: 230,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.75),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '👑 YUNAN YANIK VIP',
              style: TextStyle(
                color: Color(0xFFFDE047),
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              mySeatIdx == -1
                  ? 'Masadaki boş koltuklardan birine dokunarak oturun.'
                  : 'En az 2 oyuncu HAZIR olduğunda 10\'ar kağıt dağıtılır.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 10.5),
            ),
            if (mySeat != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    SoundFx.playCardTap();
                    gs.toggleReady();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mySeat.isReady
                        ? const Color(0xFF059669)
                        : const Color(0xFFD4AF37),
                    foregroundColor:
                        mySeat.isReady ? Colors.white : Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(
                    mySeat.isReady ? Icons.check_circle : Icons.play_arrow,
                    size: 16,
                  ),
                  label: Text(
                    mySeat.isReady ? 'HAZIRSINIZ' : 'HAZIR OL',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: () => gs.standUp(),
                child: const Padding(
                  padding: EdgeInsets.all(4.0),
                  child: Text(
                    'Koltuktan Kalk',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10.5,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final indicator = table.indicatorCard;
    final drawCount = table.drawPileCount;
    final discardTop = table.topDiscardCard;
    final canDrawNow = isMyTurn && !hasDrawn;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ÜST SIRA: SOLDA GÖSTERGE JOKERİ, SAĞDA 3D KAPALI DESTE (Tasarım Görseliyle Birebir!)
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 1. GÖSTERGE JOKERİ (Üstünde Altın Taç + Altında JOKER 7♥ Yazısı)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('👑', style: TextStyle(fontSize: 18, height: 1.0)),
                const SizedBox(height: 2),
                if (indicator != null)
                  PlayingCardWidget(
                    card: indicator,
                    wildRank: table.wildRank,
                    width: 60,
                    height: 86,
                  )
                else
                  const SizedBox(width: 60, height: 86),
                const SizedBox(height: 4),
                Text(
                  indicator != null
                      ? 'JOKER ${indicator.rankLabel}${indicator.suitSymbol}'
                      : 'JOKER',
                  style: const TextStyle(
                    color: Color(0xFFFDE047),
                    fontWeight: FontWeight.w900,
                    fontSize: 10.5,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ],
            ),

            const SizedBox(width: 22),

            // 2. 3D KAPALI DESTE (DESTE 54)
            GestureDetector(
              onTap: canDrawNow ? () => gs.drawCard() : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: canDrawNow
                          ? [
                              BoxShadow(
                                color: const Color(0xFF22C55E)
                                    .withValues(alpha: 0.8),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: CardBackWidget(
                      width: 60,
                      height: 86,
                      deckCount: drawCount,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    canDrawNow ? '👇 DESTE $drawCount' : 'DESTE $drawCount',
                    style: TextStyle(
                      color: canDrawNow
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFFFDE047),
                      fontWeight: FontWeight.w900,
                      fontSize: 10.5,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // ALT ORTA: ATILAN KAĞIT (ATILAN K♠)
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              discardTop != null
                  ? 'ATILAN ${discardTop.rankLabel}${discardTop.suitSymbol}'
                  : 'ATILAN KAĞIT',
              style: const TextStyle(
                color: Color(0xFFFDE047),
                fontWeight: FontWeight.w900,
                fontSize: 10,
                shadows: [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
            const SizedBox(height: 3),
            discardTop != null
                ? PlayingCardWidget(
                    card: discardTop,
                    wildRank: table.wildRank,
                    width: 58,
                    height: 82,
                  )
                : Container(
                    width: 58,
                    height: 82,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'BOŞ',
                        style: TextStyle(
                          color: Colors.white38,
                          fontWeight: FontWeight.bold,
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      ],
    );
  }

  // ===========================================================================
  // 3. ALT OYUNCU ELİ (TEK SIRA GENİŞ YELPAZE + 60 FPS SIFIR GECİKMELİ SÜRÜKLEME)
  // ===========================================================================
  Widget _buildZyngaBottomHandAndControls({
    required GameService gs,
    required TableStateModel table,
    required SeatPlayerModel? mySeat,
    required int mySeatIdx,
    required bool isMyTurn,
    required bool hasDrawn,
    required bool isPlaying,
  }) {
    final meldedIds = table.meldedCardIds;
    final canFinish = table.canFinishNow;
    final deadwoodPoints = table.currentHandPenalty;

    return Column(
      children: [
        // ÜST MİNİ DURUM BANDI (Elde Kalan Sayı & İpucu)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 3.5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: canFinish
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFD4AF37).withValues(alpha: 0.65),
                  ),
                ),
                child: Text(
                  canFinish
                      ? '✨ EL AÇMAYA HAZIR (0 CEZA)'
                      : 'Elde Ceza: $deadwoodPoints Puan',
                  style: TextStyle(
                    color: canFinish
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFFFDE047),
                    fontWeight: FontWeight.w900,
                    fontSize: 10.5,
                  ),
                ),
              ),
              const Text(
                '↔ Parmağınızla Sürükleyerek Dizin',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        // TEK SIRA GENİŞ KAVİSLİ YELPAZE KARTLAR (60 FPS SÜRÜKLEME)
        Expanded(
          child: _localHand.isEmpty
              ? Center(
                  child: Text(
                    mySeatIdx == -1
                        ? 'Oynamak için masadaki boş bir koltuğa dokunun'
                        : 'Yeni elin dağıtılması bekleniyor...',
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                )
              : _buildSingleArcSmoothFanHand(
                  table: table,
                  meldedIds: meldedIds,
                  lastDrawnCardId: gs.lastDrawnCardId,
                ),
        ),

        // ZYNGA STİLİ 4'LÜ ALT AKSİYON BUTONLARI
        // (DESTEDEN ÇEK | OTOMATİK DİZ | KAĞIDI AT | EL AÇ)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
          child: Row(
            children: [
              // 1. DESTEDEN ÇEK (Altın Buton)
              Expanded(
                child: _buildZynga3DButton(
                  label: 'DESTEDEN\nÇEK',
                  isGold: true,
                  enabled: isPlaying && isMyTurn && !hasDrawn,
                  glow: isPlaying && isMyTurn && !hasDrawn,
                  onTap: () => gs.drawCard(),
                ),
              ),
              const SizedBox(width: 6),

              // 2. OTOMATİK DİZ (Zümrüt Buton)
              Expanded(
                child: _buildZynga3DButton(
                  label: 'OTOMATİK\nDİZ',
                  isGold: false,
                  enabled: _localHand.isNotEmpty,
                  onTap: () {
                    SoundFx.playCardTap();
                    gs.reorderHand();
                  },
                ),
              ),
              const SizedBox(width: 6),

              // 3. KAĞIDI AT (Altın Buton)
              Expanded(
                child: _buildZynga3DButton(
                  label: 'KAĞIDI\nAT',
                  isGold: true,
                  enabled: isPlaying &&
                      isMyTurn &&
                      hasDrawn &&
                      _selectedCardId != null,
                  glow: isPlaying &&
                      isMyTurn &&
                      hasDrawn &&
                      _selectedCardId != null,
                  onTap: () {
                    if (_selectedCardId != null) {
                      final idToDiscard = _selectedCardId!;
                      setState(() {
                        _selectedCardId = null;
                        _localHand.removeWhere((c) => c.id == idToDiscard);
                      });
                      gs.discardCard(idToDiscard);
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),

              // 4. EL AÇ (Zümrüt Parlak Buton)
              Expanded(
                child: _buildZynga3DButton(
                  label: 'EL AÇ\nBİTİR',
                  isGold: false,
                  enabled: isPlaying && isMyTurn && canFinish,
                  glow: isPlaying && isMyTurn && canFinish,
                  onTap: () {
                    gs.declareFinish(
                      discardCardId:
                          _selectedCardId ?? table.winningDiscardCardId,
                    );
                    setState(() => _selectedCardId = null);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 60 FPS Sıfır Gecikmeli Tek Sıra Geniş Yelpaze Kart Dizilimi
  Widget _buildSingleArcSmoothFanHand({
    required TableStateModel table,
    required Set<String> meldedIds,
    required String? lastDrawnCardId,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        final count = _localHand.length;
        if (count == 0) return const SizedBox.shrink();

        // Kart boyutları: Dikey ekranda büyük ve çok net
        final double cardH = (maxH * 0.80).clamp(112.0, 146.0);
        final double cardW = (cardH * 0.69).clamp(76.0, 100.0);

        // Tek sırada tüm ekran genişliğine yayılan yelpaze adımı
        final double sideMargin = 10.0;
        final double availableSpan = maxW - (sideMargin * 2) - cardW;
        final double stepX = count > 1
            ? (availableSpan / (count - 1)).clamp(24.0, cardW * 0.82)
            : 0.0;
        final double totalWidth = cardW + stepX * (count - 1);
        final double startX = (maxW - totalWidth) / 2;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (details) {
            final localX = details.localPosition.dx;
            // Dokunulan X koordinatına en yakın üstteki kartı bul
            int hitIdx = -1;
            for (int i = count - 1; i >= 0; i--) {
              final left = startX + i * stepX;
              if (localX >= left && localX <= left + cardW) {
                hitIdx = i;
                break;
              }
            }
            hitIdx = hitIdx == -1
                ? ((localX - startX) / (stepX > 0 ? stepX : 1))
                    .round()
                    .clamp(0, count - 1)
                : hitIdx;

            SoundFx.playCardTap();
            setState(() {
              _draggingCardId = _localHand[hitIdx].id;
              _selectedCardId = _draggingCardId;
              _dragFingerX = localX;
            });
          },
          onHorizontalDragUpdate: (details) {
            if (_draggingCardId == null) return;
            final fingerX = details.localPosition.dx.clamp(0.0, maxW);
            final currentIdx =
                _localHand.indexWhere((c) => c.id == _draggingCardId);
            if (currentIdx == -1) return;

            final targetIdx = stepX > 0
                ? ((fingerX - startX - cardW * 0.35) / stepX)
                    .round()
                    .clamp(0, count - 1)
                : 0;

            setState(() {
              _dragFingerX = fingerX;
              if (targetIdx != currentIdx) {
                final moved = _localHand.removeAt(currentIdx);
                _localHand.insert(targetIdx, moved);
                HapticFeedback.selectionClick();
              }
            });
          },
          onHorizontalDragEnd: (_) {
            if (_draggingCardId == null) return;
            final orderedIds = _localHand.map((c) => c.id).toList();
            setState(() {
              _draggingCardId = null;
            });
            // Sadece parmak kalktığında sunucuya tek paket gönderilir -> 0 gecikme!
            GameService.instance.reorderHand(orderedCardIds: orderedIds);
          },
          child: SizedBox(
            width: maxW,
            height: maxH,
            child: Stack(
              clipBehavior: Clip.none,
              children: List.generate(count, (idx) {
                final card = _localHand[idx];
                final cardId = card.id;
                final isDragging = _draggingCardId == cardId;
                final isSelected = _selectedCardId == cardId;
                final isMelded = meldedIds.contains(cardId);
                final isNewlyDrawn = lastDrawnCardId == cardId;
                final isWinningDiscard = table.winningDiscardCardId == cardId;

                // Zynga tarzı yumuşak kavisli yelpaze açısı ve yüksekliği
                final double norm =
                    count > 1 ? (idx / (count - 1)) - 0.5 : 0.0; // -0.5 .. +0.5
                final double angle = isDragging ? 0.0 : norm * 0.28;
                final double curveY = (norm * norm) * 28.0;

                final double targetLeft = isDragging
                    ? (_dragFingerX - cardW / 2).clamp(2.0, maxW - cardW - 2.0)
                    : startX + (idx * stepX);
                final double targetTop =
                    (maxH - cardH - 12) + curveY - (isSelected ? 18 : 0);

                return AnimatedPositioned(
                  key: ValueKey(cardId),
                  duration: Duration(milliseconds: isDragging ? 0 : 120),
                  curve: Curves.easeOutCubic,
                  left: targetLeft,
                  top: targetTop,
                  child: GestureDetector(
                    onTap: () {
                      SoundFx.playCardTap();
                      setState(() {
                        if (_selectedCardId == cardId) {
                          // Seçili karta tekrar dokunulursa ve sıra bizdeyse doğrudan at!
                          if (table.status == 'playing' &&
                              table.currentTurnSeat ==
                                  table.seats.indexWhere(
                                    (s) =>
                                        s?.userId ==
                                        GameService.instance.currentUser?.id,
                                  ) &&
                              table.hasDrawnThisTurn) {
                            _selectedCardId = null;
                            _localHand.removeWhere((c) => c.id == cardId);
                            GameService.instance.discardCard(cardId);
                          } else {
                            _selectedCardId = null;
                          }
                        } else {
                          _selectedCardId = cardId;
                        }
                      });
                    },
                    child: Transform.rotate(
                      angle: angle,
                      child: Transform.scale(
                        scale: isDragging ? 1.08 : 1.0,
                        child: PlayingCardWidget(
                          card: card,
                          wildRank: table.wildRank,
                          width: cardW,
                          height: cardH,
                          isSelected: isSelected || isDragging,
                          isMelded: isMelded,
                          isNewlyDrawn: isNewlyDrawn,
                          isWinningDiscardCandidate: isWinningDiscard,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }

  /// Zynga UI Mockup'ındaki 3D Altın ve Zümrüt Çerçeveli Aksiyon Butonları
  Widget _buildZynga3DButton({
    required String label,
    required bool isGold,
    required bool enabled,
    required VoidCallback onTap,
    bool glow = false,
  }) {
    final List<Color> gradientColors = !enabled
        ? [const Color(0xFF1F2937), const Color(0xFF111827)]
        : isGold
            ? [
                const Color(0xFFFDE047),
                const Color(0xFFD97706),
                const Color(0xFF92400E),
              ]
            : [
                const Color(0xFF10B981),
                const Color(0xFF047857),
                const Color(0xFF064E3B),
              ];

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 46,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: gradientColors,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled ? const Color(0xFFFDE047) : Colors.white24,
            width: glow ? 2.2 : 1.4,
          ),
          boxShadow: [
            if (glow)
              BoxShadow(
                color: (isGold
                        ? const Color(0xFFFACC15)
                        : const Color(0xFF10B981))
                    .withValues(alpha: 0.65),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            const BoxShadow(
              color: Colors.black87,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: !enabled
                  ? Colors.white38
                  : isGold
                      ? const Color(0xFF1C1917)
                      : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              height: 1.1,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 4. PROFESYONEL 101 PUAN TABLOSU & YENİDEN GİRİŞ (RE-BUY) MODALI
  // ===========================================================================
  Widget _buildScoreboardOverlay(
    TableStateModel table,
    SeatPlayerModel? mySeat,
    int mySeatIdx,
    bool isRoundEnd,
  ) {
    final gs = GameService.instance;
    final seatedPlayers = table.seats.whereType<SeatPlayerModel>().toList();
    final showdownMap = {
      for (final s in table.lastShowdown) s.userId: s,
    };
    final myShowdown = mySeat != null ? showdownMap[mySeat.userId] : null;

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
                            ? 'EL #${table.roundNumber} SONUCU (${table.turnRemainingSeconds}s)'
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
                if (isRoundEnd &&
                    mySeat != null &&
                    myShowdown != null &&
                    myShowdown.canRebuy) ...[
                  const SizedBox(height: 12),
                  SizedBox(
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
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 5. MAÇ SONU ŞAMPİYON OVERLAY
  // ===========================================================================
  Widget _buildMatchFinishedOverlay(
    TableStateModel table,
    int mySeatIdx,
  ) {
    final winner = table.lastWinnerInfo!;
    final winnerName = winner['username'] ?? 'Şampiyon';
    final prize = winner['prizeWon'] ?? 0;
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
  // 6. EFEKT GÖNDERME VE SOHBET ÇEKMECESİ
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
              '$emoji  ${eff['senderUsername'] ?? eff['fromUsername']} ➔ ${eff['effectName'] ?? ''}',
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
