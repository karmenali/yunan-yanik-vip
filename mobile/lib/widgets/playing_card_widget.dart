import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/game_models.dart';

/// Zynga Poker / Bicycle Casino Standartlarında Temiz, Okunaklı İskambil Kağıdı Bileşeni
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

    final Color suitColor = isPhysicalJoker
        ? const Color(0xFF6D28D9)
        : (card.suit == 'hearts' || card.suit == 'diamonds')
            ? const Color(0xFFDC2626)
            : const Color(0xFF111827);

    // Çerçeve rengi ve kalınlığı
    Color borderColor = const Color(0xFFD6D3C9);
    double borderWidth = 1.1;

    if (isSelected) {
      borderColor = const Color(0xFFF59E0B);
      borderWidth = 2.2;
    } else if (isWinningDiscardCandidate) {
      borderColor = const Color(0xFFEF4444);
      borderWidth = 2.0;
    } else if (isMelded) {
      borderColor = const Color(0xFF10B981);
      borderWidth = 1.9;
    } else if (isIndicatorWild) {
      borderColor = const Color(0xFFD97706);
      borderWidth = 1.6;
    } else if (isNewlyDrawn) {
      borderColor = const Color(0xFF38BDF8);
      borderWidth = 1.7;
    }

    final double radius = (width * 0.13).clamp(6.0, 11.0);
    final double rankFontSize = (width * 0.27).clamp(11.0, 20.0);
    final double cornerSuitSize = (width * 0.21).clamp(9.0, 15.0);
    final double centerArtSize = (width * 0.44).clamp(16.0, 34.0);

    final Widget cardBody = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isSelected
              ? const [Color(0xFFFFFBEB), Color(0xFFFEF3C7)]
              : isPhysicalJoker
                  ? const [Color(0xFFFAF5FF), Color(0xFFF3E8FF)]
                  : isIndicatorWild
                      ? const [Color(0xFFFFFBEB), Color(0xFFFEF9C3)]
                      : const [Color(0xFFFCFBF9), Color(0xFFF4F1EA)],
        ),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? const Color(0xFFF59E0B).withValues(alpha: 0.42)
                : isMelded
                    ? const Color(0xFF10B981).withValues(alpha: 0.25)
                    : Colors.black.withValues(alpha: 0.36),
            blurRadius: isSelected ? 8 : 4,
            offset: Offset(0, isSelected ? 3 : 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: Stack(
          children: [
            // İnce klasik iç çerçeve
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all((width * 0.055).clamp(2.5, 4.5)),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular((radius - 3).clamp(3.0, 8.0)),
                    border: Border.all(
                      color: suitColor.withValues(alpha: 0.08),
                      width: 0.8,
                    ),
                  ),
                ),
              ),
            ),

            // SOL ÜST KÖŞE İNDEKSİ (Sayı + Sembol)
            Positioned(
              top: (height * 0.045).clamp(2.5, 5.0),
              left: (width * 0.075).clamp(3.5, 6.0),
              child: _buildCornerIndex(
                isPhysicalJoker: isPhysicalJoker,
                suitColor: suitColor,
                rankFontSize: rankFontSize,
                cornerSuitSize: cornerSuitSize,
              ),
            ),

            // SAĞ ALT KÖŞE TERS İNDEKS (Gerçek İskambil Kağıdı Simetrisi)
            if (height >= 64)
              Positioned(
                bottom: (height * 0.045).clamp(2.5, 5.0),
                right: (width * 0.075).clamp(3.5, 6.0),
                child: Transform.rotate(
                  angle: math.pi,
                  child: _buildCornerIndex(
                    isPhysicalJoker: isPhysicalJoker,
                    suitColor: suitColor,
                    rankFontSize: rankFontSize * 0.85,
                    cornerSuitSize: cornerSuitSize * 0.85,
                  ),
                ),
              ),

            // ORTA İSKAMBİL SANATI (A, J/Q/K, Sayı veya Joker)
            Center(
              child: _buildCenterCardArt(
                isPhysicalJoker: isPhysicalJoker,
                suitColor: suitColor,
                centerArtSize: centerArtSize,
              ),
            ),

            // YARDIMLI MODDA GÖSTERGE JOKERİ TAÇ İŞARETİ (Yardımsız modda asla görünmez!)
            if (showAsWild && (isPhysicalJoker || showWildHints))
              Positioned(
                top: 3,
                right: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isPhysicalJoker
                        ? const Color(0xFF6D28D9)
                        : const Color(0xFFD97706),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isPhysicalJoker ? 'JKR' : '👑',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: (width * 0.125).clamp(6.5, 8.5),
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                ),
              ),

            // YARDIMLI MODDA PER ONAY NOKTASI
            if (isMelded && !showAsWild)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: (width * 0.13).clamp(6.0, 9.0),
                  height: (width * 0.13).clamp(6.0, 9.0),
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
              ),

            // YARDIMLI MODDA "BU KAĞIDI ATARSAN BİTERSİN" İŞARETİ
            if (isWinningDiscardCandidate)
              Positioned(
                bottom: 3,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(4),
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
      ),
    );

    if (onTap == null) return cardBody;
    return GestureDetector(onTap: onTap, child: cardBody);
  }

  Widget _buildCornerIndex({
    required bool isPhysicalJoker,
    required Color suitColor,
    required double rankFontSize,
    required double cornerSuitSize,
  }) {
    if (isPhysicalJoker) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'J',
            style: TextStyle(
              color: suitColor,
              fontSize: rankFontSize * 0.92,
              fontWeight: FontWeight.w900,
              height: 0.95,
            ),
          ),
          Text(
            '★',
            style: TextStyle(
              color: const Color(0xFFD97706),
              fontSize: cornerSuitSize * 0.9,
              height: 0.95,
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          card.rankLabel,
          style: TextStyle(
            color: suitColor,
            fontSize: rankFontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: card.rank == 10 ? -1.1 : -0.3,
            height: 0.95,
          ),
        ),
        Text(
          card.suitSymbol,
          style: TextStyle(
            color: suitColor,
            fontSize: cornerSuitSize,
            fontWeight: FontWeight.bold,
            height: 0.95,
          ),
        ),
      ],
    );
  }

  Widget _buildCenterCardArt({
    required bool isPhysicalJoker,
    required Color suitColor,
    required double centerArtSize,
  }) {
    if (isPhysicalJoker) {
      return Container(
        width: centerArtSize * 1.15,
        height: centerArtSize * 1.15,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFFD97706)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
              blurRadius: 4,
            ),
          ],
        ),
        child: Center(
          child: Text(
            '🃏',
            style: TextStyle(fontSize: centerArtSize * 0.68, height: 1.0),
          ),
        ),
      );
    }

    // Kraliyet kağıtları (J, Q, K) için şık çerçeveli madalyon
    if (card.rank >= 11 && card.rank <= 13) {
      final String crownIcon = card.rank == 13
          ? '♔'
          : card.rank == 12
              ? '♕'
              : '♘';
      return Container(
        width: centerArtSize * 1.12,
        height: centerArtSize * 1.28,
        decoration: BoxDecoration(
          color: suitColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.55),
            width: 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              crownIcon,
              style: TextStyle(
                color: const Color(0xFFB45309),
                fontSize: centerArtSize * 0.52,
                height: 0.95,
              ),
            ),
            Text(
              card.suitSymbol,
              style: TextStyle(
                color: suitColor,
                fontSize: centerArtSize * 0.56,
                height: 1.0,
              ),
            ),
          ],
        ),
      );
    }

    // As (A) için özel rozetli büyük sembol
    if (card.rank == 1) {
      return Container(
        width: centerArtSize * 1.15,
        height: centerArtSize * 1.15,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: suitColor.withValues(alpha: 0.06),
          border: Border.all(
            color: suitColor.withValues(alpha: 0.18),
            width: 1.0,
          ),
        ),
        child: Center(
          child: Text(
            card.suitSymbol,
            style: TextStyle(
              color: suitColor,
              fontSize: centerArtSize * 0.78,
              height: 1.0,
            ),
          ),
        ),
      );
    }

    // 2..10 sayı kağıtları için ferah, göz yormayan klasik merkez sembolü
    return Text(
      card.suitSymbol,
      style: TextStyle(
        color: suitColor.withValues(alpha: 0.85),
        fontSize: centerArtSize * 0.86,
        height: 1.0,
      ),
    );
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
