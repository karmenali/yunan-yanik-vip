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
    final double rankFontSize = (width * 0.22).clamp(9.0, 15.0);
    final double cornerSuitSize = (width * 0.14).clamp(6.5, 10.5);
    final double centerArtSize = (width * 0.34).clamp(13.0, 22.0);

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
              top: (height * 0.050).clamp(2.5, 5.0),
              left: (width * 0.080).clamp(3.0, 6.0),
              child: _buildCornerIndex(
                isPhysicalJoker: isPhysicalJoker,
                suitColor: suitColor,
                rankFontSize: rankFontSize,
                cornerSuitSize: cornerSuitSize,
              ),
            ),

            // SAĞ ALT KÖŞE TERS İNDEKS (Gerçek İskambil Kağıdı Simetrisi)
            if (height >= 60)
              Positioned(
                bottom: (height * 0.050).clamp(2.5, 5.0),
                right: (width * 0.080).clamp(3.0, 6.0),
                child: Transform.rotate(
                  angle: math.pi,
                  child: _buildCornerIndex(
                    isPhysicalJoker: isPhysicalJoker,
                    suitColor: suitColor,
                    rankFontSize: rankFontSize * 0.90,
                    cornerSuitSize: cornerSuitSize * 0.90,
                  ),
                ),
              ),

            // ORTA İSKAMBİL SANATI (A, J/Q/K, Sayı veya Joker)
            // Tam matematiksel merkezde konumlandırıldı
            Align(
              alignment: Alignment.center,
              child: _buildCenterCardArt(
                isPhysicalJoker: isPhysicalJoker,
                suitColor: suitColor,
                centerArtSize: centerArtSize,
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
      final double jokerLetterSize = (width * 0.125).clamp(5.8, 8.8);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '★',
            style: TextStyle(
              color: const Color(0xFFD97706),
              fontSize: jokerLetterSize * 1.15,
              fontWeight: FontWeight.w900,
              height: 0.9,
            ),
          ),
          Text(
            'J\nO\nK\nE\nR',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFFB91C1C),
              fontSize: jokerLetterSize,
              fontWeight: FontWeight.w900,
              height: 0.92,
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
            letterSpacing: card.rank == 10 ? -0.8 : -0.2,
            height: 1.0,
          ),
        ),
        SizedBox(height: (height * 0.015).clamp(1.0, 2.0)),
        Text(
          card.suitSymbol,
          style: TextStyle(
            color: suitColor,
            fontSize: cornerSuitSize,
            fontWeight: FontWeight.bold,
            height: 1.0,
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
      return SizedBox(
        width: width * 0.66,
        height: height * 0.72,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Image.asset(
            'assets/images/joker_art.jpg',
            fit: BoxFit.contain,
          ),
        ),
      );
    }

    // Kraliyet kağıtları (J, Q, K) için gerçekçi, şık casino madalyonu
    if (card.rank >= 11 && card.rank <= 13) {
      final String courtLetter = card.rankLabel; // "J", "Q", "K"
      return Container(
        width: (centerArtSize * 0.95).clamp(16.0, 26.0),
        height: (centerArtSize * 1.30).clamp(22.0, 36.0),
        decoration: BoxDecoration(
          color: suitColor.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.65),
            width: 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              card.suitSymbol,
              style: TextStyle(
                color: suitColor,
                fontSize: (centerArtSize * 0.30).clamp(6.0, 10.0),
                height: 1.0,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              courtLetter,
              style: TextStyle(
                color: suitColor,
                fontSize: (centerArtSize * 0.52).clamp(10.0, 16.0),
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              card.suitSymbol,
              style: TextStyle(
                color: suitColor,
                fontSize: (centerArtSize * 0.30).clamp(6.0, 10.0),
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
        width: (centerArtSize * 1.10).clamp(18.0, 30.0),
        height: (centerArtSize * 1.10).clamp(18.0, 30.0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: suitColor.withValues(alpha: 0.06),
          border: Border.all(
            color: suitColor.withValues(alpha: 0.22),
            width: 1.0,
          ),
        ),
        child: Center(
          child: Text(
            card.suitSymbol,
            style: TextStyle(
              color: suitColor,
              fontSize: (centerArtSize * 0.72).clamp(13.0, 22.0),
              height: 1.0,
            ),
          ),
        ),
      );
    }

    // 2..10 sayı kağıtları için gerçekçi iskambil pip (nokta) simetrik dizilimi
    return _buildMultiPipLayout(
      rank: card.rank,
      suitSymbol: card.suitSymbol,
      suitColor: suitColor,
      centerArtSize: centerArtSize,
    );
  }

  /// 2..10 arası kağıtlar için klasik iskambil destesi pip desen dağılımı
  Widget _buildMultiPipLayout({
    required int rank,
    required String suitSymbol,
    required Color suitColor,
    required double centerArtSize,
  }) {
    final double pipSize = (centerArtSize * 0.40).clamp(7.5, 12.0);
    final pipStyle = TextStyle(
      color: suitColor.withValues(alpha: 0.90),
      fontSize: pipSize,
      height: 1.0,
      fontWeight: FontWeight.bold,
    );

    final pip = Text(suitSymbol, style: pipStyle);
    final invPip = Transform.rotate(angle: math.pi, child: pip);

    if (rank == 2) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [pip, invPip],
      );
    } else if (rank == 3) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [pip, pip, invPip],
      );
    } else if (rank == 4) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip, invPip]),
          Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip, invPip]),
        ],
      );
    } else if (rank == 5) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip, invPip]),
          Center(child: pip),
          Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip, invPip]),
        ],
      );
    } else if (rank == 6) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip, pip, invPip]),
          Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip, pip, invPip]),
        ],
      );
    } else if (rank == 7) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip, pip, invPip]),
          Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [const SizedBox(height: 6), pip],
          ),
          Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip, pip, invPip]),
        ],
      );
    } else if (rank == 8) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip, pip, invPip]),
          Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip, invPip]),
          Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip, pip, invPip]),
        ],
      );
    } else if (rank == 9) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip, pip, invPip, invPip]),
          Center(child: pip),
          Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip, pip, invPip, invPip]),
        ],
      );
    } else if (rank == 10) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip, pip, invPip, invPip]),
          Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip, invPip]),
          Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip, pip, invPip, invPip]),
        ],
      );
    }

    return pip;
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
