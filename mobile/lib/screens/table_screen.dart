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
  // 3 Sıralı Dikey Istaka Durumu (_localRows[0], _localRows[1], _localRows[2])
  List<List<CardModel>> _localRows = [[], [], []];
  String? _selectedCardId;
  String? _draggingCardId;
  Offset _dragLocalPos = Offset.zero;

  bool _showScoreboardModal = false;
  bool _showChatDrawer = false;
  bool _dismissedWinnerModal = false;
  String? _lastSeenWinnerId;

  // El Sonu Şeffaf Animasyonlu Gösterim (İlk 10 sn Açan El + Saat Yönünde Sırayla Ceza Açılışı)
  Timer? _showdownTicker;
  int _showdownElapsedMs = 0;
  int _lastAnimatedShowdownRound = -1;

  // Sayıya Göre Sırala mod değişimi (false = Sayı Sırası 1-2-3..K, true = Renk/Seri Sırası)
  bool _sortBySuitMode = false;

  // Canlı Sayaç (Sunucu + Yerel Saniyelik Akıcı Senkronizasyon)
  Timer? _localSecondTicker;
  int _lastBeepSecond = -1;

  String? _toastBanner;
  Timer? _toastTimer;
  final List<Map<String, dynamic>> _floatingEffects = [];
  final Map<String, String> _seatSpeechBubbles = {}; // userId -> son mesaj
  Map<String, dynamic>? _activeFlyingCardAnim;

  StreamSubscription<String>? _toastSub;
  StreamSubscription<Map<String, dynamic>>? _effectSub;
  StreamSubscription<Map<String, dynamic>>? _cardAnimSub;
  StreamSubscription<Map<String, dynamic>>? _chatSub;
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
    _syncLocalRowsFromServer();

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
      final senderUid = eff['senderUserId']?.toString();
      final key = eff['effectKey']?.toString() ?? '';
      const emojiMap = {
        'bomb': '💣💥',
        'tomato': '🍅💦',
        'rose': '🌹✨',
        'clap': '👏🎉',
        'laugh': '😂🔥',
        'cry': '😭💧',
      };
      final emoji = emojiMap[key] ?? '✨';
      setState(() {
        _floatingEffects.add(eff);
        if (senderUid != null && senderUid.isNotEmpty) {
          _seatSpeechBubbles[senderUid] = emoji;
        }
      });
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) {
          setState(() {
            _floatingEffects.remove(eff);
            if (senderUid != null && _seatSpeechBubbles[senderUid] == emoji) {
              _seatSpeechBubbles.remove(senderUid);
            }
          });
        }
      });
    });

    _cardAnimSub = gs.cardAnimStreamController.stream.listen((anim) {
      if (!mounted) return;
      final type = anim['type']?.toString();
      if (type == 'draw' || type == 'discard') {
        setState(() => _activeFlyingCardAnim = anim);
        Future.delayed(const Duration(milliseconds: 420), () {
          if (mounted && _activeFlyingCardAnim == anim) {
            setState(() => _activeFlyingCardAnim = null);
          }
        });
      } else if (type == 'round_ended') {
        _startShowdownAnimationTimer(reset: true);
      }
    });

    _chatSub = gs.chatStreamController.stream.listen((msg) {
      if (!mounted) return;
      final uid = msg['userId']?.toString() ?? '';
      final text = msg['message']?.toString() ?? '';
      if (uid.isNotEmpty && text.isNotEmpty) {
        setState(() => _seatSpeechBubbles[uid] = text);
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted && _seatSpeechBubbles[uid] == text) {
            setState(() => _seatSpeechBubbles.remove(uid));
          }
        });
      }
    });
  }

  @override
  void dispose() {
    GameService.instance.removeListener(_onGameUpdate);
    _localSecondTicker?.cancel();
    _showdownTicker?.cancel();
    _toastSub?.cancel();
    _effectSub?.cancel();
    _cardAnimSub?.cancel();
    _chatSub?.cancel();
    _toastTimer?.cancel();
    _chatCtrl.dispose();
    super.dispose();
  }

  void _startShowdownAnimationTimer({bool reset = false}) {
    final table = GameService.instance.activeTable;
    if (table == null || table.status != 'round_summary') {
      _showdownTicker?.cancel();
      _showdownTicker = null;
      return;
    }

    if (reset || _lastAnimatedShowdownRound != table.roundNumber) {
      _lastAnimatedShowdownRound = table.roundNumber;
      _showdownElapsedMs = table.showdownElapsedMs;
    }

    _showdownTicker?.cancel();
    _showdownTicker = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final t = GameService.instance.activeTable;
      if (t == null || t.status != 'round_summary') {
        timer.cancel();
        return;
      }
      setState(() {
        _showdownElapsedMs += 100;
      });
    });
  }

  List<CardModel> get _allLocalCards =>
      [..._localRows[0], ..._localRows[1], ..._localRows[2]];

  List<List<String>> get _currentRowIds =>
      _localRows.map((r) => r.map((c) => c.id).toList()).toList();

  void _syncLocalRowsFromServer() {
    final table = GameService.instance.activeTable;
    if (table == null) {
      _localRows = [[], [], []];
      return;
    }

    final serverCards = table.myHand;
    if (serverCards.isEmpty) {
      _localRows = [[], [], []];
      return;
    }

    final currentIds = _allLocalCards.map((c) => c.id).toSet();
    final serverIds = serverCards.map((c) => c.id).toSet();

    // Kullanıcı şu anda parmağıyla kart sürüklüyorsa ve eldeki kart kümesi değişmediyse sırayı bozma
    if (_draggingCardId != null &&
        currentIds.length == serverIds.length &&
        currentIds.containsAll(serverIds)) {
      return;
    }

    final cardMap = {for (final c in serverCards) c.id: c};
    final seen = <String>{};
    final nextRows = <List<CardModel>>[[], [], []];

    // Önce sunucudan gelen (veya yerel korunan) 3 sıra dizilimini uygula
    final sourceRowIds = table.myHandRows.any((r) => r.isNotEmpty)
        ? table.myHandRows
        : _currentRowIds;

    for (int r = 0; r < 3; r++) {
      final ids = r < sourceRowIds.length ? sourceRowIds[r] : <String>[];
      for (final id in ids) {
        final c = cardMap[id];
        if (c != null && !seen.contains(id)) {
          nextRows[r].add(c);
          seen.add(id);
        }
      }
    }

    // Henüz bir sıraya yerleşmemiş kağıtları (ör. yeni çekilen 11. kağıt) en uygun sıraya yerleştir
    for (final c in serverCards) {
      if (!seen.contains(c.id)) {
        int targetRow = 2;
        if (nextRows[0].length < 4) {
          targetRow = 0;
        } else if (nextRows[1].length < 3) {
          targetRow = 1;
        } else {
          targetRow = 2;
        }
        nextRows[targetRow].add(c);
        seen.add(c.id);
      }
    }

    _localRows = nextRows;
  }

  void _onGameUpdate() {
    if (!mounted) return;
    final table = GameService.instance.activeTable;
    _syncLocalRowsFromServer();

    if (table != null && table.status == 'round_summary') {
      if (_showdownTicker == null || !_showdownTicker!.isActive) {
        _startShowdownAnimationTimer();
      }
    } else {
      _showdownTicker?.cancel();
      _showdownTicker = null;
    }

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

  Future<void> _confirmAndLeaveTable() async {
    final gs = GameService.instance;
    final table = gs.activeTable;
    final myId = gs.currentUser?.id;
    final isSeatedInActiveMatch = table != null &&
        (table.status == 'playing' || table.status == 'round_summary') &&
        table.seats.any((s) => s?.userId == myId && !s!.isEliminated);

    if (isSeatedInActiveMatch) {
      final shouldLeave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0E2F21),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFFDE047)),
              SizedBox(width: 8),
              Text(
                'Masadan Kalk',
                style: TextStyle(
                  color: Color(0xFFFDE047),
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          content: const Text(
            'Devam eden oyundan kalkarsanız yatırdığınız giriş kredisini kaybedersiniz ve koltuğunuz boşaltılır.\n\nMasadan kalkmak istediğinize emin misiniz?',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Devam Et', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Masadan Kalk', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (shouldLeave != true) return;

      await gs.stopContinuousMic();
      gs.forfeitMatch();
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    await gs.stopContinuousMic();
    gs.leaveCurrentTable();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _tryDiscardCardWithConfirmation(
    CardModel card,
    TableStateModel table,
  ) async {
    // Yardımsız modda yerdeki gösterge jokerini otomatik söylemek yardım sayılacağından sadece Yardımlı modda veya fiziksel Jokerde uyar!
    final shouldWarnWild =
        card.isPhysicalJoker || (table.isAssisted && card.isWild(table.wildRank));
    if (shouldWarnWild) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0E2F21),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFF59E0B), width: 1.8),
          ),
          title: const Text(
            '🃏 Joker Kağıdı Atıyorsunuz!',
            style: TextStyle(
              color: Color(0xFFFDE047),
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          content: Text(
            'Seçtiğiniz ${card.rankLabel}${card.suitSymbol} kağıdı bu elin JOKER (Wild) kağıdıdır. Yere atmak istediğinize emin misiniz?',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Evet, Jokeri At'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() {
      _selectedCardId = null;
      for (final row in _localRows) {
        row.removeWhere((c) => c.id == card.id);
      }
    });
    GameService.instance.discardCard(card.id);
  }

  Future<void> _handleDeclareFinishTap(TableStateModel table) async {
    final gs = GameService.instance;
    final String? candidateDiscardId =
        _selectedCardId ?? table.winningDiscardCardId;

    if (!table.isAssisted) {
      // Yardımsız (Usta) Modda El Açma Onayı ve Yanma Uyarısı!
      if (candidateDiscardId == null && _allLocalCards.length == 11) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ Yardımsız modda el açmak için önce yere atacağınız 11. kağıda dokunarak seçin!',
            ),
            backgroundColor: Color(0xFFB45309),
          ),
        );
        return;
      }

      final discardCardObj = _allLocalCards
          .cast<CardModel?>()
          .firstWhere((c) => c?.id == candidateDiscardId, orElse: () => null);
      final discardLabel = discardCardObj != null
          ? '${discardCardObj.rankLabel}${discardCardObj.suitSymbol}'
          : 'Seçili kağıt';

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1F1212),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFEF4444), width: 2),
          ),
          title: const Text(
            '🔥 Yardımsız Mod — El Açma Onayı',
            style: TextStyle(
              color: Color(0xFFFDE047),
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          content: Text(
            'Yere atılacak kağıt: $discardLabel\n'
            'Kalan 10 kağıdınız 3 sıradaki diziliminize göre masaya açılacaktır.\n\n'
            '⚠️ DİKKAT: Eğer 3 sıradaki diziliminiz geçerli per oluşturmuyorsa DİREKT YANMIŞ SAYILIRSINIZ (101+) ve bu maç için tekrar para yatırıp dahil olma (Re-buy) hakkınızı KAYBEDERSİNİZ!\n\n'
            'Elinizi açmayı onaylıyor musunuz?',
            style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Kontrol Edeyim', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'ELİM DOĞRU, AÇ!',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    gs.declareFinish(
      discardCardId: candidateDiscardId,
      rowCardIds: _currentRowIds,
    );
    setState(() => _selectedCardId = null);
  }

  /// 3 Sıradaki tüm kağıtları TEK BİR BÜTÜN EL olarak sıralar ve 3 sıraya (4 - 3 - 3/4) temizce dağıtır
  void _handleSortHandButtonTap(TableStateModel table) {
    SoundFx.playCardTap();
    final gs = GameService.instance;
    if (table.isAssisted) {
      gs.reorderHand();
      return;
    }

    final allCards = _allLocalCards;
    if (allCards.isEmpty) return;

    const suitOrder = <String, int>{
      'spades': 0,
      'hearts': 1,
      'clubs': 2,
      'diamonds': 3,
      'joker': 4,
    };

    final sorted = List<CardModel>.from(allCards);
    if (!_sortBySuitMode) {
      // 1. Mod: Sayı Sırası (A, 2, 3 .. 10, J, Q, K, Joker) — Aynı sayılar yan yana
      sorted.sort((a, b) {
        if (a.isPhysicalJoker != b.isPhysicalJoker) {
          return a.isPhysicalJoker ? 1 : -1;
        }
        if (a.rank != b.rank) return a.rank.compareTo(b.rank);
        return (suitOrder[a.suit] ?? 9).compareTo(suitOrder[b.suit] ?? 9);
      });
    } else {
      // 2. Mod: Renk / Seri Sırası (♠, ♥, ♣, ♦ içinde 1-2-3..K)
      sorted.sort((a, b) {
        if (a.isPhysicalJoker != b.isPhysicalJoker) {
          return a.isPhysicalJoker ? 1 : -1;
        }
        final sa = suitOrder[a.suit] ?? 9;
        final sb = suitOrder[b.suit] ?? 9;
        if (sa != sb) return sa.compareTo(sb);
        return a.rank.compareTo(b.rank);
      });
    }

    _sortBySuitMode = !_sortBySuitMode;

    // 10 veya 11 kağıdı 3 sıraya (1. sıra: 4, 2. sıra: 3, 3. sıra: kalan 3 veya 4) tek bütün olarak dağıt
    final row0End = math.min(4, sorted.length);
    final row1End = math.min(7, sorted.length);
    setState(() {
      _selectedCardId = null;
      _localRows = [
        sorted.sublist(0, row0End),
        sorted.sublist(row0End, row1End),
        sorted.sublist(row1End),
      ];
    });

    gs.reorderHand(
      orderedCardIds: sorted.map((c) => c.id).toList(),
      rowCardIds: _currentRowIds,
    );
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
                onPressed: () {
                  gs.leaveCurrentTable();
                  Navigator.of(context).pop();
                },
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _confirmAndLeaveTable();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF06140E),
        body: Stack(
          children: [
            // 1. ZYNGA 3D MAUN & ZÜMRÜT ÇUHA MASA ARKA PLAN GÖRSELİ
            Positioned.fill(
              child: Image.asset(
                'assets/images/table_bg.jpg',
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.2),
              ),
            ),

            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.45),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.82),
                    ],
                    stops: const [0.0, 0.42, 1.0],
                  ),
                ),
              ),
            ),

            // 2. ANA DİKEY ZYNGA MASA DÜZENİ (ÜST MASA + ALT 3 SIRALI DİKEY ISTAKA)
            SafeArea(
              child: Column(
                children: [
                  _buildZyngaTopBar(table, gs),

                  // BİLGİ / HATA BİLDİRİMİ (Üst barın altına yerleştirildi, sayaç ve skor asla kapanmaz)
                  if (_toastBanner != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A2418).withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFF59E0B)),
                            boxShadow: const [
                              BoxShadow(color: Colors.black87, blurRadius: 10),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.notifications_active,
                                color: Color(0xFFFBBF24),
                                size: 15,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _toastBanner!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // ORTA CASINO MASASI (Saat Yönünde Koltuklar, Pot, Gösterge Jokeri, Deste ve Atılan Kağıt)
                  Expanded(
                    flex: 46,
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

                  // ALT OYUNCU ELİ: 3 SIRALI DİKEY ISTAKA + 60 FPS SÜRÜKLEME + 4 ZYNGA BUTONU
                  Expanded(
                    flex: 54,
                    child: _buildThreeRowBottomHandAndControls(
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

            // 3. UÇAN EFEKT KATMANI
            ..._floatingEffects.map((eff) => _buildFloatingEffectOverlay(eff)),



            // 5. EL SONU ŞEFFAF ANİMASYONLU GÖSTERİM (10 SN AÇAN EL + SAAT YÖNÜNDE CEZA AÇILIŞI)
            if (isRoundEnd && !_showScoreboardModal)
              _buildAnimatedShowdownStage(table, mySeat, mySeatIdx),

            // 6. TAM 101 PUAN TABLOSU MODALI
            if (_showScoreboardModal)
              _buildScoreboardOverlay(table, mySeat, mySeatIdx, isRoundEnd),

            // 7. MAÇ SONU ŞAMPİYON EKRANI
            if (isFinished &&
                table.lastWinnerInfo != null &&
                !_dismissedWinnerModal)
              _buildMatchFinishedOverlay(table, mySeatIdx),

            // 8. SOHBET ÇEKMECESİ (+ HIZLI SOHBET KALIPLARI)
            if (_showChatDrawer) _buildChatDrawer(gs),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 1. ZYNGA ÜST VIP BAR + MOD ROZETİ + PUBG TARZI CANLI SES (DİNLE / KONUŞ)
  // ===========================================================================
  Widget _buildZyngaTopBar(TableStateModel table, GameService gs) {
    final matchTimeStr = _formatDuration(table.matchElapsedSeconds);
    final isPlaying = table.status == 'playing';
    final isMicOn = gs.isVoiceMicOn;
    final isListenOn = gs.isVoiceListenOn;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
              InkWell(
                onTap: _confirmAndLeaveTable,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3E2723), Color(0xFF1B0F0D)],
                    ),
                    border: Border.all(
                      color: const Color(0xFFD4AF37),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Color(0xFFFDE047),
                    size: 14,
                  ),
                ),
              ),
              const SizedBox(width: 5),

              // Masa Adı & Yardımlı/Yardımsız Mod Rozeti
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: table.isAssisted
                        ? const [Color(0xFF1E3A8A), Color(0xFF0F172A)]
                        : const [Color(0xFF991B1B), Color(0xFF450A0A)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFFD4AF37),
                    width: 1.3,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      table.isAssisted ? '✨' : '🔥',
                      style: const TextStyle(fontSize: 11),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      table.isAssisted ? 'Yardımlı' : 'Yardımsız',
                      style: const TextStyle(
                        color: Color(0xFFFDE047),
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),

              // Masa Ödül Havuzu (Pot) Rozeti
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
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
                      const Text('🪙', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          '${table.pot > 0 ? table.pot : table.entryFee}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // 101 Puan Tablosu Butonu
              InkWell(
                onTap: () {
                  SoundFx.playCardTap();
                  setState(() => _showScoreboardModal = !_showScoreboardModal);
                },
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
                        size: 12,
                      ),
                      SizedBox(width: 2),
                      Text(
                        '101',
                        style: TextStyle(
                          color: Color(0xFFFDE047),
                          fontWeight: FontWeight.w900,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // PUBG TARZI HOPARLÖR (DİNLE AÇIK / KAPALI)
              InkWell(
                onTap: () {
                  gs.toggleVoiceListen();
                  setState(() {});
                },
                borderRadius: BorderRadius.circular(18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: isListenOn
                        ? const Color(0xFF065F46)
                        : Colors.black54,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isListenOn
                          ? const Color(0xFF34D399)
                          : Colors.white38,
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isListenOn
                            ? Icons.headset_rounded
                            : Icons.headset_off_rounded,
                        color: isListenOn
                            ? const Color(0xFFFDE047)
                            : Colors.white54,
                        size: 14,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Dinle',
                        style: TextStyle(
                          color: isListenOn ? Colors.white : Colors.white54,
                          fontWeight: FontWeight.w900,
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // PUBG TARZI SÜREKLİ MİKROFON (KONUŞ CANLI / KAPALI)
              InkWell(
                onTap: () async {
                  await gs.toggleContinuousMic();
                  setState(() {});
                },
                borderRadius: BorderRadius.circular(18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: isMicOn
                        ? const LinearGradient(
                            colors: [Color(0xFF16A34A), Color(0xFF15803D)],
                          )
                        : const LinearGradient(
                            colors: [Color(0xFF334155), Color(0xFF1E293B)],
                          ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isMicOn
                          ? const Color(0xFF86EFAC)
                          : const Color(0xFFD4AF37),
                      width: 1.3,
                    ),
                    boxShadow: isMicOn
                        ? [
                            BoxShadow(
                              color: const Color(0xFF22C55E)
                                  .withValues(alpha: 0.55),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                        color: isMicOn ? Colors.white : Colors.white70,
                        size: 14,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        isMicOn ? 'Konuş' : 'Kapalı',
                        style: TextStyle(
                          color: isMicOn ? Colors.white : Colors.white70,
                          fontWeight: FontWeight.w900,
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // OYUN SESİ AÇ / KAPA (MUTE) BUTONU
              InkWell(
                onTap: () {
                  final enabled = SoundFx.toggleSound();
                  setState(() {});
                  gs.toastStreamController.add(
                    enabled ? '🔊 Oyun sesleri açıldı' : '🔇 Oyun sesleri kapatıldı',
                  );
                },
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: SoundFx.soundEnabled
                        ? const Color(0xFF064E3B)
                        : Colors.black54,
                    border: Border.all(
                      color: SoundFx.soundEnabled
                          ? const Color(0xFF34D399)
                          : Colors.white38,
                      width: 1.2,
                    ),
                  ),
                  child: Icon(
                    SoundFx.soundEnabled
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    color: SoundFx.soundEnabled
                        ? const Color(0xFFFDE047)
                        : Colors.white54,
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

        // ZYNGA ALTIN TRAPEZOİD SÜRE BANDI
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
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
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.timer_outlined,
                color: Color(0xFFFDE047),
                size: 12,
              ),
              const SizedBox(width: 5),
              Text(
                isPlaying || table.roundNumber > 0
                    ? 'MAÇ $matchTimeStr  •  EL #${table.roundNumber}'
                    : '${table.name} (${table.entryFee} 🪙)',
                style: const TextStyle(
                  color: Color(0xFFFDE047),
                  fontWeight: FontWeight.w900,
                  fontSize: 10.5,
                  letterSpacing: 0.5,
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
                      fontSize: 10,
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
  // 2. ZYNGA CASINO MASASI (SAAT YÖNÜNDE GÖRECELİ KOLTUKLAR + ORTA DESTE/JOKER)
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

        // Koltukları yerel oyuncuya göre saat yönünde döndür (ben her zaman sol-alt / kendi bakış açımda)
        final seatPositions =
            _calculateRelativeSeatPositions(seats.length, mySeatIdx, w, h);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // MASA ORTASI: GÖSTERGE JOKERİ + KAPALI DESTE + ATILAN KAĞIT
            Align(
              alignment: const Alignment(0, 0.05),
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

            // SAAT YÖNÜNDE YERLEŞTİRİLMİŞ OYUNCU AVATARLARI
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

            // UÇAN KART ANİMASYONU (Çekilen veya Atılan Kart)
            if (_activeFlyingCardAnim != null)
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.6, end: 1.0),
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutBack,
                  builder: (context, val, _) {
                    return Transform.scale(
                      scale: val,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFDE047)),
                        ),
                        child: Text(
                          _activeFlyingCardAnim!['type'] == 'draw'
                              ? '🃏 Desteden Kağıt Çekildi'
                              : '🃏 Yere Kağıt Atıldı',
                          style: const TextStyle(
                            color: Color(0xFFFDE047),
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  /// Yerel oyuncuyu (mySeatIdx) her zaman sol-alta koyup diğer koltukları saat yönünde (Sol-Üst -> Sağ-Üst -> Sağ-Orta -> Sağ-Alt) dizer
  List<Offset> _calculateRelativeSeatPositions(
    int count,
    int mySeatIdx,
    double w,
    double h,
  ) {
    const double avatarWidth = 76.0;
    final double leftX = 6.0;
    final double rightX = w - avatarWidth - 6.0;

    // Saat yönünde ekran etrafındaki koltuk koordinatları (0. indeks yerel oyuncunun koltuğu)
    List<Offset> clockwiseSlots;
    if (count == 2) {
      clockwiseSlots = [
        Offset(leftX + 2, h * 0.65), // Sen (Sol-Alt - ortadaki gösterge kartına asla değmez)
        Offset((w - avatarWidth) / 2, h * 0.02), // Rakip (Üst-Orta)
      ];
    } else if (count == 3) {
      clockwiseSlots = [
        Offset(leftX + 2, h * 0.65), // 0: Sen (Sol-Alt)
        Offset(leftX + 4, h * 0.03), // 1: Sol-Üst
        Offset(rightX - 4, h * 0.03), // 2: Sağ-Üst
      ];
    } else if (count == 4) {
      clockwiseSlots = [
        Offset(leftX + 2, h * 0.65), // 0: Sen (Sol-Alt)
        Offset(leftX + 4, h * 0.03), // 1: Sol-Üst
        Offset(rightX - 4, h * 0.03), // 2: Sağ-Üst
        Offset(rightX - 2, h * 0.65), // 3: Sağ-Alt
      ];
    } else if (count == 5) {
      clockwiseSlots = [
        Offset(leftX + 2, h * 0.66), // 0: Sen
        Offset(leftX + 2, h * 0.32), // 1: Sol-Orta
        Offset(leftX + 10, h * 0.02), // 2: Sol-Üst
        Offset(rightX - 10, h * 0.02), // 3: Sağ-Üst
        Offset(rightX - 2, h * 0.52), // 4: Sağ-Alt
      ];
    } else {
      clockwiseSlots = [
        Offset(leftX + 2, h * 0.66), // 0: Sen
        Offset(leftX + 2, h * 0.34), // 1: Sol-Orta
        Offset(leftX + 10, h * 0.02), // 2: Sol-Üst
        Offset(rightX - 10, h * 0.02), // 3: Sağ-Üst
        Offset(rightX - 2, h * 0.34), // 4: Sağ-Orta
        Offset(rightX - 2, h * 0.66), // 5: Sağ-Alt
      ];
    }

    final anchor = mySeatIdx >= 0 ? mySeatIdx : 0;
    final result = List<Offset>.filled(count, Offset.zero);
    for (int seatIdx = 0; seatIdx < count; seatIdx++) {
      final rel = (seatIdx - anchor + count) % count;
      result[seatIdx] = clockwiseSlots[rel];
    }
    return result;
  }

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
    final isDealer =
        table.status == 'playing' && table.dealerSeat == seatIndex;

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
          width: 76,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 46,
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
                  size: 22,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
                    fontSize: 9,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final avatar = VipAvatar.fromKey(seat.avatar);
    final isSpeaking = gs.activeSpeakingUserIds.contains(seat.userId) ||
        gs.activeVoiceSpeakerUsername == seat.username;
    final maxDur = math.max(1, table.turnDurationSeconds);
    final progress = isCurrentTurn
        ? (table.turnRemainingSeconds / maxDur).clamp(0.0, 1.0)
        : 0.0;
    final ringColor = table.turnRemainingSeconds <= 5
        ? const Color(0xFFEF4444)
        : table.turnRemainingSeconds <= 12
            ? const Color(0xFFFACC15)
            : const Color(0xFF22C55E);
    final speechBubble = _seatSpeechBubbles[seat.userId];

    return GestureDetector(
      onTap: () {
        if (!isMe && mySeatIdx != -1) {
          _showEffectPickerDialog(seat.userId, seat.username);
        }
      },
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (speechBubble != null)
              Container(
                margin: const EdgeInsets.only(bottom: 3),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                constraints: const BoxConstraints(maxWidth: 100),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 4),
                  ],
                ),
                child: Text(
                  speechBubble,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w800,
                    fontSize: 9.5,
                    height: 1.15,
                  ),
                ),
              ),
            Stack(
              alignment: Alignment.center,
              children: [
                if (isCurrentTurn)
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: ringColor.withValues(alpha: 0.65),
                          blurRadius: 12,
                          spreadRadius: 1.5,
                        ),
                      ],
                    ),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: progress, end: progress),
                      duration: const Duration(milliseconds: 900),
                      builder: (context, val, _) => CircularProgressIndicator(
                        value: val,
                        strokeWidth: 3.8,
                        backgroundColor: Colors.black45,
                        valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                      ),
                    ),
                  ),
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        avatar.color.withValues(alpha: 0.55),
                        const Color(0xFF0F172A),
                      ],
                    ),
                    border: Border.all(
                      color: !seat.isConnected
                          ? Colors.grey
                          : isSpeaking
                              ? const Color(0xFF22C55E)
                              : isMe
                                  ? const Color(0xFFFACC15)
                                  : const Color(0xFFD4AF37),
                      width: isSpeaking ? 2.6 : 2.0,
                    ),
                    boxShadow: isSpeaking
                        ? [
                            BoxShadow(
                              color: const Color(0xFF22C55E)
                                  .withValues(alpha: 0.75),
                              blurRadius: 10,
                              spreadRadius: 1.5,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      avatar.emoji,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),

                // Canlı Konuşma Rozeti (Sol Üst)
                if (isSpeaking)
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Container(
                      width: 17,
                      height: 17,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF16A34A),
                        border: Border.all(color: Colors.white, width: 1.2),
                      ),
                      child: const Icon(
                        Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 10.5,
                      ),
                    ),
                  ),

                // Dağıtan (Dealer 'D') Rozeti (Sol Alt)
                if (isDealer)
                  Positioned(
                    left: 0,
                    bottom: 0,
                    child: Container(
                      width: 17,
                      height: 17,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFACC15),
                        border: Border.all(color: Colors.black, width: 1),
                      ),
                      child: const Center(
                        child: Text(
                          'D',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                            fontSize: 9.5,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Bağlantı Kopuk Rozeti
                if (!seat.isConnected)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.redAccent,
                      ),
                      child: const Icon(
                        Icons.wifi_off_rounded,
                        color: Colors.white,
                        size: 10,
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
                        vertical: 1,
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
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Container(
              width: 100,
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: isCurrentTurn
                      ? ringColor
                      : const Color(0xFFD4AF37).withValues(alpha: 0.65),
                  width: 1.0,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    seat.isBot
                        ? '🤖 ${seat.username}'
                        : isMe
                            ? '${seat.username} (Sen)'
                            : seat.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isMe ? const Color(0xFFFDE047) : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 9.5,
                    ),
                  ),
                  Text(
                    seat.isEliminated
                        ? (seat.forfeitedRebuy ? 'Hatalı Açtı' : 'YANDI (${seat.totalScore})')
                        : '${seat.totalScore}/101',
                    style: TextStyle(
                      color: seat.isEliminated || seat.totalScore >= 85
                          ? Colors.redAccent
                          : const Color(0xFFFDE047),
                      fontWeight: FontWeight.w900,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Masa Ortası: Gösterge Jokeri (Sol) + Kapalı Deste (Orta) + Atılan Kağıt (Sağ - Yan Yana Kompakt)
  Widget _buildCenterTableFeltCards({
    required TableStateModel table,
    required bool isPlaying,
    required bool isMyTurn,
    required bool hasDrawn,
    required int mySeatIdx,
    required SeatPlayerModel? mySeat,
    required GameService gs,
  }) {
    if (!isPlaying && table.status != 'round_summary') {
      final seatedPlayers = table.seats.whereType<SeatPlayerModel>().toList();
      final seatedCount = seatedPlayers.length;
      final readyCount = seatedPlayers.where((s) => s.isReady).length;

      return Container(
        width: 230,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.8),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              table.isAssisted ? '✨ Yardımlı Mod' : '🔥 Yardımsız Mod',
              style: const TextStyle(
                color: Color(0xFFFDE047),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              mySeatIdx == -1
                  ? 'Oynamak için boş bir koltuğa dokunun.\nKoltuk: $seatedCount/${table.maxPlayers}'
                  : 'En az 2 oyuncu olmalı.\nKoltuk: $seatedCount/${table.maxPlayers}  •  Hazır: $readyCount/$seatedCount',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 10.5, height: 1.3),
            ),
            if (mySeat != null) ...[
              const SizedBox(height: 8),
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
                    padding: const EdgeInsets.symmetric(vertical: 8),
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
              if ((table.hostUsername.isEmpty ||
                      table.hostUsername == gs.currentUser?.username ||
                      mySeatIdx == 0) &&
                  seatedCount >= 2 &&
                  readyCount == seatedCount) ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      SoundFx.playCardTap();
                      gs.startGame(table.id);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.rocket_launch, size: 16),
                    label: const Text(
                      'OYUNU BAŞLAT',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
              if (table.hostUsername.isEmpty ||
                  table.hostUsername == gs.currentUser?.username ||
                  mySeatIdx == 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (seatedCount < table.maxPlayers)
                      InkWell(
                        onTap: () => gs.addBot(table.id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFF67E8F9)
                                    .withValues(alpha: 0.5)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('🤖', style: TextStyle(fontSize: 11)),
                              SizedBox(width: 4),
                              Text(
                                'Bot Oyuncu Ekle',
                                style: TextStyle(
                                  color: Color(0xFF67E8F9),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (table.seats.any((s) => s != null && s.isBot)) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () {
                          final bot = table.seats
                              .firstWhere((s) => s != null && s.isBot);
                          if (bot != null) {
                            gs.removeBot(table.id, bot.seatIndex);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.redAccent.withValues(alpha: 0.5)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.close,
                                  color: Colors.redAccent, size: 11),
                              SizedBox(width: 3),
                              Text(
                                'Bot Çıkar',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              InkWell(
                onTap: () {
                  gs.standUp();
                  gs.leaveCurrentTable();
                  if (mounted) Navigator.of(context).pop();
                },
                child: const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Masadan Kalk & Lobiye Dön',
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 1. GÖSTERGE JOKERİ
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (indicator != null)
                PlayingCardWidget(
                  card: indicator,
                  wildRank: table.wildRank,
                  showWildHints: true,
                  width: 52,
                  height: 74,
                )
              else
                const SizedBox(width: 52, height: 74),
              const SizedBox(height: 3),
              Text(
                indicator != null
                    ? 'GÖSTERGE ${indicator.rankLabel}${indicator.suitSymbol}'
                    : 'GÖSTERGE',
                style: const TextStyle(
                  color: Color(0xFFFDE047),
                  fontWeight: FontWeight.w900,
                  fontSize: 9.5,
                  shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                ),
              ),
            ],
          ),

          const SizedBox(width: 12),

          // 2. 3D KAPALI DESTE
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
                              blurRadius: 14,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: CardBackWidget(
                    width: 52,
                    height: 74,
                    deckCount: drawCount,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  canDrawNow ? '👇 ÇEK ($drawCount)' : 'DESTE $drawCount',
                  style: TextStyle(
                    color: canDrawNow
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFFFDE047),
                    fontWeight: FontWeight.w900,
                    fontSize: 9.5,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 4),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // 3. ATILAN KAĞIT (Tıklanınca Atılan Kağıtlar Geçmişini Açar)
          GestureDetector(
            onTap: () => _showDiscardHistorySheet(table),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                discardTop != null
                    ? PlayingCardWidget(
                        card: discardTop,
                        wildRank: table.wildRank,
                        showWildHints: table.isAssisted,
                        width: 52,
                        height: 74,
                      )
                    : Container(
                        width: 52,
                        height: 74,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: const Color(0xFFD4AF37).withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            'ATILAN',
                            style: TextStyle(
                              color: Colors.white38,
                              fontWeight: FontWeight.bold,
                              fontSize: 8.5,
                            ),
                          ),
                        ),
                      ),
                const SizedBox(height: 3),
                Text(
                  discardTop != null
                      ? 'ATILAN ${discardTop.rankLabel}${discardTop.suitSymbol}'
                      : 'ATILAN',
                  style: const TextStyle(
                    color: Color(0xFFFDE047),
                    fontWeight: FontWeight.w900,
                    fontSize: 9.5,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDiscardHistorySheet(TableStateModel table) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A2418),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final history = table.discardHistory.reversed.toList();
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🗑️ Yere Atılan Son Kağıtlar',
                style: TextStyle(
                  color: Color(0xFFFDE047),
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 12),
              history.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Bu elde henüz yere kağıt atılmadı.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : SizedBox(
                      height: 92,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: history.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, idx) => PlayingCardWidget(
                          card: history[idx],
                          wildRank: table.wildRank,
                          showWildHints: table.isAssisted,
                          width: 60,
                          height: 86,
                        ),
                      ),
                    ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // 3. ALT OYUNCU ELİ: 3 SIRALI DİKEY ISTAKA + 60 FPS SÜRÜKLEME (SATIR İÇİ & SATIRLAR ARASI)
  // ===========================================================================
  Widget _buildThreeRowBottomHandAndControls({
    required GameService gs,
    required TableStateModel table,
    required SeatPlayerModel? mySeat,
    required int mySeatIdx,
    required bool isMyTurn,
    required bool hasDrawn,
    required bool isPlaying,
  }) {
    final isAssisted = table.isAssisted;
    final meldedIds = isAssisted ? table.meldedCardIds : <String>{};
    final canFinish = isAssisted
        ? table.canFinishNow
        : (_allLocalCards.length == 11 && hasDrawn);
    final deadwoodPoints = table.currentHandPenalty;
    final selectedCard = _selectedCardId != null
        ? _allLocalCards
            .cast<CardModel?>()
            .firstWhere((c) => c?.id == _selectedCardId, orElse: () => null)
        : null;

    return Column(
      children: [
        // SADE VE PROFESYONEL ÜST DURUM BANDI (Gereksiz taşan yazılar kaldırıldı)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: !isAssisted
                        ? const Color(0xFFEF4444)
                        : canFinish
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFD4AF37).withValues(alpha: 0.65),
                  ),
                ),
                child: Text(
                  !isAssisted
                      ? '🔥 Yardımsız Mod'
                      : canFinish
                          ? '✨ El Açmaya Hazır'
                          : 'Ceza: $deadwoodPoints Puan',
                  style: TextStyle(
                    color: !isAssisted
                        ? const Color(0xFFFCA5A5)
                        : canFinish
                            ? const Color(0xFF4ADE80)
                            : const Color(0xFFFDE047),
                    fontWeight: FontWeight.w900,
                    fontSize: 10.5,
                  ),
                ),
              ),
              if (selectedCard != null)
                Text(
                  'Seçili: ${selectedCard.rankLabel}${selectedCard.suitSymbol}',
                  style: const TextStyle(
                    color: Color(0xFFFDE047),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
        ),

        // 3 SIRALI DİKEY ISTAKA ALANI
        Expanded(
          child: _allLocalCards.isEmpty
              ? Center(
                  child: Text(
                    mySeatIdx == -1
                        ? 'Oynamak için masadaki boş bir koltuğa dokunun'
                        : 'Tüm koltuklar hazır olduğunda el dağıtılır...',
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                )
              : _buildThreeRowInteractiveRack(
                  table: table,
                  meldedIds: meldedIds,
                  lastDrawnCardId: gs.lastDrawnCardId,
                  isMyTurn: isMyTurn,
                  hasDrawn: hasDrawn,
                ),
        ),

        // 4'LÜ ALT AKSİYON BUTONLARI
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 5),
          child: Row(
            children: [
              // 1. DESTEDEN ÇEK
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

              // 2. OTOMATİK DİZ / SIRALA
              Expanded(
                child: _buildZynga3DButton(
                  label: isAssisted ? 'OTOMATİK\nPER DİZ' : 'SAYIYA GÖRE\nSIRALA',
                  isGold: false,
                  enabled: _allLocalCards.isNotEmpty,
                  onTap: () => _handleSortHandButtonTap(table),
                ),
              ),
              const SizedBox(width: 6),

              // 3. KAĞIDI AT
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
                      final card = _allLocalCards
                          .cast<CardModel?>()
                          .firstWhere((c) => c?.id == _selectedCardId, orElse: () => null);
                      if (card != null) {
                        _tryDiscardCardWithConfirmation(card, table);
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),

              // 4. EL AÇ / BİTİR
              Expanded(
                child: _buildZynga3DButton(
                  label: 'EL AÇ\nBİTİR',
                  isGold: false,
                  enabled: isPlaying && isMyTurn && canFinish,
                  glow: isPlaying && isMyTurn && canFinish,
                  onTap: () => _handleDeclareFinishTap(table),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Dikey Ekranda 3 Sıralı (1. Sıra, 2. Sıra, 3. Sıra) Sürükle-Bırak Istaka
  Widget _buildThreeRowInteractiveRack({
    required TableStateModel table,
    required Set<String> meldedIds,
    required String? lastDrawnCardId,
    required bool isMyTurn,
    required bool hasDrawn,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        final rowH = (maxH / 3.0).clamp(68.0, 120.0);
        final cardH = (rowH * 0.90).clamp(62.0, 108.0);
        final cardW = (cardH * 0.70).clamp(44.0, 76.0);

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (details) {
            final pos = details.localPosition;
            final hit = _hitTestCardAtPosition(pos, maxW, rowH, cardW, cardH);
            if (hit == null) return;

            SoundFx.playCardTap();
            setState(() {
              _draggingCardId = hit.id;
              _dragLocalPos = pos;
            });
          },
          onPanUpdate: (details) {
            if (_draggingCardId == null) return;
            final pos = details.localPosition;
            final targetRow = (pos.dy / rowH).floor().clamp(0, 2);
            _moveDraggedCardToRowSlot(
              _draggingCardId!,
              targetRow,
              pos.dx,
              maxW,
              cardW,
            );

            setState(() {
              _dragLocalPos = pos;
            });
          },
          onPanEnd: (_) {
            if (_draggingCardId == null) return;
            setState(() {
              _draggingCardId = null;
            });

            GameService.instance.reorderHand(
              orderedCardIds: _allLocalCards.map((c) => c.id).toList(),
              rowCardIds: _currentRowIds,
            );
          },
          child: SizedBox(
            width: maxW,
            height: maxH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 3 SIRANIN AHŞAP/ALTIN RAF ÇİZGİLERİ VE SIRA NUMARALARI
                for (int r = 0; r < 3; r++)
                  Positioned(
                    left: 8,
                    right: 8,
                    top: r * rowH + 2,
                    height: rowH - 4,
                    child: GestureDetector(
                      onTap: () {
                        // Seçili bir kart varsa ve kullanıcı başka bir sıranın boşluğuna dokunursa o sıraya taşı!
                        if (_selectedCardId != null) {
                          _moveCardToRowEnd(_selectedCardId!, r);
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              const Color(0xFF0A261A).withValues(alpha: 0.55),
                              const Color(0xFF1F120B).withValues(alpha: 0.78),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFD4AF37).withValues(alpha: 0.42),
                            width: 1.1,
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 7),
                            child: Text(
                              '${r + 1}.\nSIRA',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: const Color(0xFFD4AF37)
                                    .withValues(alpha: 0.45),
                                fontWeight: FontWeight.w900,
                                fontSize: 8.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // HER SIRADAKİ KARTLARI YERLEŞTİR
                for (int r = 0; r < 3; r++)
                  ..._buildRowCardsWidgets(
                    rowIdx: r,
                    rowCards: _localRows[r],
                    maxW: maxW,
                    rowH: rowH,
                    cardW: cardW,
                    cardH: cardH,
                    table: table,
                    meldedIds: meldedIds,
                    lastDrawnCardId: lastDrawnCardId,
                    isMyTurn: isMyTurn,
                    hasDrawn: hasDrawn,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildRowCardsWidgets({
    required int rowIdx,
    required List<CardModel> rowCards,
    required double maxW,
    required double rowH,
    required double cardW,
    required double cardH,
    required TableStateModel table,
    required Set<String> meldedIds,
    required String? lastDrawnCardId,
    required bool isMyTurn,
    required bool hasDrawn,
  }) {
    final count = rowCards.length;
    if (count == 0) return const [];

    final double leftPadding = 34.0;
    final double rightPadding = 14.0;
    final double usableW = maxW - leftPadding - rightPadding;
    final double stepX = count > 1
        ? ((usableW - cardW) / (count - 1)).clamp(26.0, cardW + 8.0)
        : 0.0;
    final double totalRowW = cardW + stepX * (count - 1);
    final double startX =
        leftPadding + ((usableW - totalRowW) / 2).clamp(0.0, usableW);
    final double baseTop = rowIdx * rowH + (rowH - cardH) / 2;

    return List.generate(count, (idx) {
      final card = rowCards[idx];
      final cardId = card.id;
      final isDragging = _draggingCardId == cardId;
      final isSelected = _selectedCardId == cardId;
      final isMelded = meldedIds.contains(cardId);
      final isNewlyDrawn = lastDrawnCardId == cardId;
      final isWinningDiscard =
          table.isAssisted && table.winningDiscardCardId == cardId;

      final double left = isDragging
          ? (_dragLocalPos.dx - cardW / 2).clamp(4.0, maxW - cardW - 4.0)
          : startX + idx * stepX;
      final double top = isDragging
          ? (_dragLocalPos.dy - cardH / 2).clamp(-40.0, rowH * 3 - cardH)
          : baseTop - (isSelected ? 8.0 : 0.0);

      return AnimatedPositioned(
        key: ValueKey(cardId),
        duration: Duration(milliseconds: isDragging ? 0 : 120),
        curve: Curves.easeOutCubic,
        left: left,
        top: top,
        child: GestureDetector(
          onTap: () {
            SoundFx.playCardTap();
            setState(() {
              _selectedCardId = (_selectedCardId == cardId) ? null : cardId;
            });
          },
          child: Transform.scale(
            scale: isDragging ? 1.06 : 1.0,
            child: PlayingCardWidget(
              card: card,
              wildRank: table.wildRank,
              showWildHints: table.isAssisted,
              width: cardW,
              height: cardH,
              isSelected: isSelected,
              isMelded: isMelded,
              isNewlyDrawn: isNewlyDrawn,
              isWinningDiscardCandidate: isWinningDiscard,
            ),
          ),
        ),
      );
    });
  }

  CardModel? _hitTestCardAtPosition(
    Offset pos,
    double maxW,
    double rowH,
    double cardW,
    double cardH,
  ) {
    final int r = (pos.dy / rowH).floor().clamp(0, 2);
    final rowCards = _localRows[r];
    if (rowCards.isEmpty) return null;

    final count = rowCards.length;
    const double leftPadding = 34.0;
    const double rightPadding = 14.0;
    final double usableW = maxW - leftPadding - rightPadding;
    final double stepX = count > 1
        ? ((usableW - cardW) / (count - 1)).clamp(26.0, cardW + 8.0)
        : 0.0;
    final double totalRowW = cardW + stepX * (count - 1);
    final double startX =
        leftPadding + ((usableW - totalRowW) / 2).clamp(0.0, usableW);

    for (int i = count - 1; i >= 0; i--) {
      final left = startX + i * stepX;
      if (pos.dx >= left && pos.dx <= left + cardW) {
        return rowCards[i];
      }
    }

    final approxIdx = stepX > 0
        ? ((pos.dx - startX) / stepX).round().clamp(0, count - 1)
        : 0;
    return rowCards[approxIdx];
  }

  void _moveDraggedCardToRowSlot(
    String cardId,
    int targetRow,
    double fingerX,
    double maxW,
    double cardW,
  ) {
    CardModel? movingCard;
    int fromRow = -1;
    int fromIdx = -1;

    for (int r = 0; r < 3; r++) {
      final idx = _localRows[r].indexWhere((c) => c.id == cardId);
      if (idx != -1) {
        fromRow = r;
        fromIdx = idx;
        movingCard = _localRows[r][idx];
        break;
      }
    }
    if (movingCard == null) return;

    final destRowList = _localRows[targetRow];
    final countAfter =
        fromRow == targetRow ? destRowList.length : destRowList.length + 1;
    const double leftPadding = 34.0;
    const double rightPadding = 14.0;
    final double usableW = maxW - leftPadding - rightPadding;
    final double stepX = countAfter > 1
        ? ((usableW - cardW) / (countAfter - 1)).clamp(26.0, cardW + 8.0)
        : 0.0;
    final double totalRowW = cardW + stepX * (countAfter - 1);
    final double startX =
        leftPadding + ((usableW - totalRowW) / 2).clamp(0.0, usableW);

    final int targetIdx = stepX > 0
        ? ((fingerX - startX - cardW * 0.35) / stepX)
            .round()
            .clamp(0, countAfter - 1)
        : 0;

    if (fromRow == targetRow && fromIdx == targetIdx) return;

    _localRows[fromRow].removeAt(fromIdx);
    final clampedInsert = targetIdx.clamp(0, _localRows[targetRow].length);
    _localRows[targetRow].insert(clampedInsert, movingCard);
    HapticFeedback.selectionClick();
  }

  void _moveCardToRowEnd(String cardId, int targetRow) {
    CardModel? movingCard;
    for (int r = 0; r < 3; r++) {
      final idx = _localRows[r].indexWhere((c) => c.id == cardId);
      if (idx != -1) {
        movingCard = _localRows[r].removeAt(idx);
        break;
      }
    }
    if (movingCard == null) return;
    setState(() {
      _localRows[targetRow].add(movingCard!);
    });
    GameService.instance.reorderHand(
      orderedCardIds: _allLocalCards.map((c) => c.id).toList(),
      rowCardIds: _currentRowIds,
    );
  }

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
        height: 44,
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
              fontSize: 10.5,
              height: 1.1,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 4. ŞEFFAF ANİMASYONLU EL SONU GÖSTERİMİ (10 SN AÇAN EL + SAAT YÖNÜNDE CEZA AÇILIŞI)
  // ===========================================================================
  Widget _buildAnimatedShowdownStage(
    TableStateModel table,
    SeatPlayerModel? mySeat,
    int mySeatIdx,
  ) {
    final gs = GameService.instance;
    final showdown = table.lastShowdown;
    if (showdown.isEmpty) return const SizedBox.shrink();

    final opener = showdown.first;
    final hasLeadShowcase = opener.isFinisher || opener.isFalseDeclarer;
    final isStage1OpenerShowcase =
        hasLeadShowcase && _showdownElapsedMs < 10000;
    final stage1RemainingSec =
        ((10000 - _showdownElapsedMs) / 1000).ceil().clamp(0, 10);

    final myShowdown = mySeat != null
        ? showdown
            .cast<ShowdownPlayerResultModel?>()
            .firstWhere((s) => s?.userId == mySeat.userId, orElse: () => null)
        : null;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.86),
        padding: const EdgeInsets.fromLTRB(12, 24, 12, 16),
        child: SafeArea(
          child: Column(
            children: [
              // ÜST BAŞLIK & AŞAMA GÖSTERGESİ
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: opener.isFalseDeclarer
                        ? const [Color(0xFF991B1B), Color(0xFF450A0A)]
                        : const [Color(0xFF065F46), Color(0xFF064E3B)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFDE047), width: 1.6),
                ),
                child: Row(
                  children: [
                    Text(
                      opener.isFalseDeclarer ? '🚨' : '👑',
                      style: const TextStyle(fontSize: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isStage1OpenerShowcase
                                ? (opener.isFalseDeclarer
                                    ? '${opener.username} HATALI EL AÇTI! ($stage1RemainingSec sn)'
                                    : '${opener.username} EL AÇTI! ($stage1RemainingSec sn Masada Açık)')
                                : '🔄 CEZA PUANLARI SIRAYLA AÇILIYOR (${table.turnRemainingSeconds}s)',
                            style: const TextStyle(
                              color: Color(0xFFFDE047),
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isStage1OpenerShowcase
                                ? 'Açılan el 10 saniye boyunca masadaki tüm oyunculara şeffaf gösterilir.'
                                : 'Kalan oyuncuların elleri soldan sağa sırayla açılıp cezaları toplama ekleniyor.',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _showScoreboardModal = true),
                      icon: const Icon(
                        Icons.table_chart_outlined,
                        color: Color(0xFFFDE047),
                        size: 16,
                      ),
                      label: const Text(
                        'Tablo',
                        style: TextStyle(
                          color: Color(0xFFFDE047),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 1. AÇAN OYUNCUNUN MASADAKİ 10 KAĞITLIK VİTRİNİ (Her zaman en üstte büyük ve net)
              if (hasLeadShowcase)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF144530), Color(0xFF092318)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: opener.isFalseDeclarer
                          ? Colors.redAccent
                          : const Color(0xFFFACC15),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            opener.isFalseDeclarer
                                ? '🚨 ${opener.username} — Hatalı Açılan El (Direkt Yandı & Re-buy İptal!)'
                                : '✨ ${opener.username} — Açılan El (0 Ceza Puanı)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 12.5,
                            ),
                          ),
                          if (isStage1OpenerShowcase)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFACC15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$stage1RemainingSec sn',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(right: 18),
                        child: Row(
                          children: [
                            for (final meld in opener.melds) ...[
                              Container(
                                margin: const EdgeInsets.only(right: 10),
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: Colors.black38,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFF22C55E),
                                  ),
                                ),
                                child: Row(
                                  children: meld
                                      .map(
                                        (c) => Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 1.5,
                                          ),
                                          child: PlayingCardWidget(
                                            card: c,
                                            wildRank: table.wildRank,
                                            width: 46,
                                            height: 66,
                                            isMelded: true,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ],
                            if (opener.unmelded.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade900.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.redAccent),
                                ),
                                child: Row(
                                  children: opener.unmelded
                                      .map(
                                        (c) => Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 1.5,
                                          ),
                                          child: PlayingCardWidget(
                                            card: c,
                                            wildRank: table.wildRank,
                                            width: 46,
                                            height: 66,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 10),

              // 2. SAAT YÖNÜNDE SIRAYLA AÇILAN DİĞER OYUNCULARIN ELLERİ VE CEZA PUANLARI
              Expanded(
                child: ListView.builder(
                  itemCount: showdown.length,
                  itemBuilder: (context, idx) {
                    if (hasLeadShowcase && idx == 0) {
                      return const SizedBox.shrink();
                    }
                    final sd = showdown[idx];
                    final isRevealedYet =
                        _showdownElapsedMs >= sd.revealStartMs;
                    final isCurrentlyRevealing = isRevealedYet &&
                        _showdownElapsedMs <
                            (sd.revealStartMs + sd.revealDurationMs);

                    return AnimatedOpacity(
                      duration: const Duration(milliseconds: 450),
                      opacity: isRevealedYet ? 1.0 : 0.32,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: isCurrentlyRevealing
                              ? const Color(0xFF1A3A2A)
                              : const Color(0xFF0A2016),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isCurrentlyRevealing
                                ? const Color(0xFFFACC15)
                                : sd.burnedThisRound
                                    ? Colors.redAccent
                                    : Colors.white24,
                            width: isCurrentlyRevealing ? 2.0 : 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '🪑 Koltuk #${sd.seatIndex + 1} • ${sd.username}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    if (isCurrentlyRevealing) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFACC15),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'AÇILIYOR',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 9,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (isRevealedYet)
                                  TweenAnimationBuilder<double>(
                                    tween: Tween(
                                      begin: 0,
                                      end: sd.roundPenalty.toDouble(),
                                    ),
                                    duration: const Duration(milliseconds: 900),
                                    builder: (context, val, _) {
                                      final animPen = val.round();
                                      final animTot =
                                          sd.previousScore + animPen;
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '+$animPen Ceza',
                                            style: TextStyle(
                                              color: animPen == 0
                                                  ? const Color(0xFF4ADE80)
                                                  : const Color(0xFFF87171),
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            'Toplam: $animTot/101 ${sd.burnedThisRound ? "🔥 YANDI" : ""}',
                                            style: TextStyle(
                                              color: sd.burnedThisRound
                                                  ? Colors.redAccent
                                                  : const Color(0xFFFDE047),
                                              fontWeight: FontWeight.w800,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  )
                                else
                                  const Text(
                                    '⏳ Sırası Bekleniyor...',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (isRevealedYet)
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.only(right: 18),
                                child: Row(
                                  children: [
                                    if (sd.unmelded.isNotEmpty)
                                      Container(
                                        margin:
                                            const EdgeInsets.only(right: 8),
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade900
                                              .withValues(alpha: 0.35),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                        child: Row(
                                          children: sd.unmelded
                                              .map(
                                                (c) => Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 1.5,
                                                  ),
                                                  child: PlayingCardWidget(
                                                    card: c,
                                                    wildRank: table.wildRank,
                                                    width: 40,
                                                    height: 58,
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      ),
                                    for (final meld in sd.melds)
                                      Container(
                                        margin:
                                            const EdgeInsets.only(right: 8),
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black26,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                            color: const Color(0xFF22C55E)
                                                .withValues(alpha: 0.6),
                                          ),
                                        ),
                                        child: Row(
                                          children: meld
                                              .map(
                                                (c) => Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 1.5,
                                                  ),
                                                  child: PlayingCardWidget(
                                                    card: c,
                                                    wildRank: table.wildRank,
                                                    width: 40,
                                                    height: 58,
                                                    isMelded: true,
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // 3. YANAN OYUNCU İÇİN RE-BUY BUTONU VEYA HATALI EL AÇMA CEZASI UYARISI
              if (myShowdown != null && myShowdown.forfeitedRebuy)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent),
                  ),
                  child: const Text(
                    '🚫 Yardımsız modda hatalı el açtığınız için direkt elendiniz ve bu oyunda yeniden giriş (Re-buy) hakkınızı kaybettiniz.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                    ),
                  ),
                )
              else if (myShowdown != null && myShowdown.canRebuy)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => gs.rebuyIntoMatch(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
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
          ),
        ),
      ),
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
    final seatedPlayers = table.seats.whereType<SeatPlayerModel>().toList();
    final showdownMap = {
      for (final s in table.lastShowdown) s.userId: s,
    };
    final myShowdown = mySeat != null ? showdownMap[mySeat.userId] : null;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.84),
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
                            ? 'EL #${table.roundNumber} PUAN TABLOSU (${table.turnRemainingSeconds}s)'
                            : '101 CEZA PUAN ÇİZELGESİ',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () =>
                          setState(() => _showScoreboardModal = false),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12),
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
                                  if (s.forfeitedRebuy)
                                    const Text(
                                      '🚫 Hatalı El Açtı (Re-buy İptal)',
                                      style: TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 10,
                                      ),
                                    )
                                  else if (rebuyCount > 0)
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
                    myShowdown.canRebuy &&
                    !myShowdown.forfeitedRebuy) ...[
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
  // 6. MAÇ SONU ŞAMPİYON OVERLAY
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
  // 7. EFEKT GÖNDERME VE SOHBET ÇEKMECESİ (+ HIZLI SOHBET KALIPLARI)
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
      top: 140,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.2, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
          builder: (context, val, _) => Transform.scale(
            scale: val,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFFDE047), width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black87, blurRadius: 16),
                  ],
                ),
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 34, height: 1.0),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatDrawer(GameService gs) {
    const quickPhrases = [
      'İyi oyunlar! 👋',
      'Bol şans! 🍀',
      'Hızlı oynayalım ⏱️',
      'Güzel eldi! 👏',
      'Eyvah yandık! 🔥',
    ];

    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: 295,
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
                      onPressed: () => setState(() => _showChatDrawer = false),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              // Hızlı Sohbet Kalıpları
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: quickPhrases.map((phrase) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        backgroundColor: const Color(0xFF143D2B),
                        label: Text(
                          phrase,
                          style: const TextStyle(
                            color: Color(0xFFFDE047),
                            fontSize: 11,
                          ),
                        ),
                        onPressed: () {
                          gs.sendChatMessage(phrase);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Divider(color: Colors.white12, height: 12),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: gs.tableChatMessages.length,
                  itemBuilder: (context, idx) {
                    final m = gs.tableChatMessages[idx];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${m['username']}: ',
                              style: const TextStyle(
                                color: Color(0xFFFBBF24),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            TextSpan(
                              text: '${m['message']}',
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
                        maxLength: 80,
                        buildCounter: (context,
                                {required currentLength,
                                required isFocused,
                                maxLength}) =>
                            null,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Mesaj yaz (maks 80 karakter)...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white10,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (val) {
                          if (val.trim().isNotEmpty) {
                            gs.sendChatMessage(val.trim());
                            _chatCtrl.clear();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: () {
                        if (_chatCtrl.text.trim().isNotEmpty) {
                          gs.sendChatMessage(_chatCtrl.text.trim());
                          _chatCtrl.clear();
                        }
                      },
                      icon: const Icon(Icons.send, color: Color(0xFFFBBF24)),
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
