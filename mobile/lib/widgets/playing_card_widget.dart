import 'package:flutter/material.dart';
import '../models/game_models.dart';
import 'vector_card_renderer.dart';

/// Zynga Poker / Bicycle Casino Standartlarında Vektörel İskambil Kağıdı Bileşeni
class PlayingCardWidget extends StatelessWidget {
  final CardModel card;
  final int wildRank;
  final bool showWildHints; // Yardımsız modda false olur; gösterge jokerini normal kağıt gibi gösterir
  final bool isSelected;
  final bool isMelded;
  final bool isNewlyDrawn;
  final bool isWinningDiscardCandidate;
  final double width;
  final double height;
  final VoidCallback? onTap;

  const PlayingCardWidget({
    super.key,
    required this.card,
    required this.wildRank,
    this.showWildHints = true,
    this.isSelected = false,
    this.isMelded = false,
    this.isNewlyDrawn = false,
    this.isWinningDiscardCandidate = false,
    this.width = 62,
    this.height = 90,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPhysicalJoker = card.isPhysicalJoker;
    // Yardımsız modda (showWildHints == false) sadece gerçek fiziksel Joker kağıdı Joker görünümündedir;
    // Gösterge kağıdıyla aynı sayıdaki kağıtlar normal iskambil kağıdı olarak çizilir (kopya/ipucu verilmez!)
    final bool isIndicatorWild =
        showWildHints && !isPhysicalJoker && wildRank > 0 && card.rank == wildRank;
    final bool showAsWild = isPhysicalJoker || isIndicatorWild;

    String normalizedSuit = card.suit.toUpperCase();
    if (normalizedSuit.startsWith('SPADE')) {
      normalizedSuit = 'S';
    } else if (normalizedSuit.startsWith('HEART')) {
      normalizedSuit = 'H';
    } else if (normalizedSuit.startsWith('DIAMOND')) {
      normalizedSuit = 'D';
    } else if (normalizedSuit.startsWith('CLUB')) {
      normalizedSuit = 'C';
    } else if (normalizedSuit.isNotEmpty) {
      normalizedSuit = normalizedSuit[0];
    } else {
      normalizedSuit = 'S';
    }

    final cardBody = SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          // 1. GPU Hızlandırmalı Kusursuz Vektörel Kart Gövdesi (Zynga / Batak HD Standartı)
          Positioned.fill(
            child: CustomPaint(
              size: Size(width, height),
              painter: VectorCardPainter(
                rank: card.rank,
                suit: normalizedSuit,
                isPhysicalJoker: isPhysicalJoker,
                showAsWild: showAsWild,
                isSelected: isSelected,
                isWinningDiscardCandidate: isWinningDiscardCandidate,
              ),
            ),
          ),

          // 2. Yeni Çekilen Kağıt Mavi Vurgusu
          if (isNewlyDrawn)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular((width * 0.12).clamp(5.0, 10.0)),
                    border: Border.all(color: const Color(0xFF38BDF8), width: 2.0),
                  ),
                ),
              ),
            ),

          // 3. Yardımlı Modda Per Onay Noktası (Sağ üst yeşil nokta)
          if (isMelded && !showAsWild)
            Positioned(
              top: 3.5,
              right: 3.5,
              child: IgnorePointer(
                child: Container(
                  width: (width * 0.13).clamp(6.0, 9.0),
                  height: (width * 0.13).clamp(6.0, 9.0),
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 4. Yardımlı Modda Joker Yıldız İpucu (Sağ üst altın yıldız)
          if (isIndicatorWild)
            Positioned(
              top: 2,
              right: 3,
              child: IgnorePointer(
                child: Text(
                  '★',
                  style: TextStyle(
                    color: const Color(0xFFD97706),
                    fontSize: (width * 0.15).clamp(8.0, 12.0),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          // 5. Yardımlı Modda "AT & AÇ" Rozeti (Kullanıcı bu kağıdı atarsa açabilecekse)
          if (isWinningDiscardCandidate)
            Positioned(
              bottom: 3,
              left: 2,
              right: 2,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    'AT & AÇ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: (width * 0.12).clamp(6.5, 8.5),
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (onTap == null) return cardBody;
    return GestureDetector(onTap: onTap, child: cardBody);
  }
}

/// Lüks Kraliyet Laciverti & Altın Filigranlı Kapalı İskambil Sırtı
class CardBackWidget extends StatelessWidget {
  final double width;
  final double height;
  final int? deckCount;
  final VoidCallback? onTap;

  const CardBackWidget({
    super.key,
    this.width = 58,
    this.height = 84,
    this.deckCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double radius = (width * 0.13).clamp(6.0, 11.0);

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (deckCount != null && deckCount! > 2)
            Positioned(
              left: 3,
              top: 3,
              child: _buildSingleBack(radius, darken: 0.25),
            ),
          if (deckCount != null && deckCount! > 1)
            Positioned(
              left: 1.5,
              top: 1.5,
              child: _buildSingleBack(radius, darken: 0.12),
            ),
          _buildSingleBack(radius, showCount: deckCount != null),
        ],
      ),
    );
  }

  Widget _buildSingleBack(
    double radius, {
    double darken = 0.0,
    bool showCount = false,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: const Color(0xFFF8FAFC),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(2.5),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular((radius - 2.5).clamp(4.0, 9.0)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(const Color(0xFF1E3A8A), Colors.black, darken)!,
              Color.lerp(const Color(0xFF0F172A), Colors.black, darken)!,
            ],
          ),
          border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.75),
            width: 1.0,
          ),
        ),
        child: Center(
          child: showCount && deckCount != null
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFD4AF37),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '$deckCount',
                    style: const TextStyle(
                      color: Color(0xFFFDE047),
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                )
              : Container(
                  width: width * 0.46,
                  height: width * 0.46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.65),
                      width: 1.1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '♠',
                      style: TextStyle(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.85),
                        fontSize: (width * 0.24).clamp(10.0, 16.0),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
