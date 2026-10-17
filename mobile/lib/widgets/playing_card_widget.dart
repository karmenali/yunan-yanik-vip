import 'package:flutter/material.dart';
import '../models/game_models.dart';

class PlayingCardWidget extends StatelessWidget {
  final CardModel card;
  final int wildRank;
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
    this.isSelected = false,
    this.isMelded = false,
    this.isNewlyDrawn = false,
    this.isWinningDiscardCandidate = false,
    this.width = 80,
    this.height = 116,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool wild = card.isWild(wildRank);
    final bool isRed =
        !card.isPhysicalJoker && (card.suit == 'H' || card.suit == 'D');
    final Color mainColor = card.isPhysicalJoker
        ? const Color(0xFF7C3AED)
        : isRed
            ? const Color(0xFFD91B24)
            : const Color(0xFF111827);

    Color borderColor = const Color(0xFFD1D5DB);
    double borderWidth = 1.5;

    if (isSelected) {
      borderColor = const Color(0xFFFACC15);
      borderWidth = 3.0;
    } else if (isNewlyDrawn) {
      borderColor = const Color(0xFF38BDF8);
      borderWidth = 2.8;
    } else if (isWinningDiscardCandidate) {
      borderColor = const Color(0xFFEF4444);
      borderWidth = 2.6;
    } else if (isMelded) {
      borderColor = const Color(0xFFF59E0B);
      borderWidth = 2.4;
    } else if (wild) {
      borderColor = const Color(0xFFD97706);
      borderWidth = 2.2;
    }

    Widget cardBody = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: wild
              ? [const Color(0xFFFFFBEB), const Color(0xFFFEF3C7)]
              : [const Color(0xFFFFFFFF), const Color(0xFFF3F4F6)],
        ),
        borderRadius: BorderRadius.circular(width * 0.12),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? const Color(0xFFFACC15).withValues(alpha: 0.7)
                : isMelded
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.45)
                    : Colors.black.withValues(alpha: 0.65),
            blurRadius: isSelected ? 14 : 8,
            offset: const Offset(-2, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.105),
        child: Stack(
          children: [
            // İç İnce Çerçeve (Zynga Poker İskambil Estetiği)
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.all(3.5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(width * 0.08),
                  border: Border.all(
                    color: wild
                        ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
                        : Colors.black.withValues(alpha: 0.06),
                    width: 0.8,
                  ),
                ),
              ),
            ),

            // SOL ÜST KÖŞE: Yelpazede üst üste bindiğinde %100 okunan keskin Sayı + Sembol şeridi
            Positioned(
              top: width * 0.055,
              left: width * 0.075,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    card.isPhysicalJoker ? 'JKR' : card.rankLabel,
                    style: TextStyle(
                      color: mainColor,
                      fontWeight: FontWeight.w900,
                      fontSize: card.isPhysicalJoker
                          ? width * 0.19
                          : (card.rank == 10 ? width * 0.29 : width * 0.32),
                      height: 0.95,
                      letterSpacing: card.rank == 10 ? -1.4 : -0.5,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    card.suitSymbol,
                    style: TextStyle(
                      color: mainColor,
                      fontSize: width * 0.27,
                      height: 0.95,
                    ),
                  ),
                ],
              ),
            ),

            // ORTA-SAĞ BÜYÜK İSKAMBİL SEMBOLÜ (Kraliyet / Zynga Stili)
            Align(
              alignment: const Alignment(0.28, 0.22),
              child: Text(
                card.isPhysicalJoker ? '🃏' : card.suitSymbol,
                style: TextStyle(
                  color: mainColor.withValues(alpha: 0.92),
                  fontSize: width * 0.50,
                  height: 1.0,
                ),
              ),
            ),

            // SAĞ ALT KÖŞE TERS SAYI
            Positioned(
              bottom: width * 0.05,
              right: width * 0.07,
              child: Transform.rotate(
                angle: 3.14159,
                child: Text(
                  card.isPhysicalJoker ? '★' : card.rankLabel,
                  style: TextStyle(
                    color: mainColor.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w900,
                    fontSize: width * 0.18,
                    height: 1.0,
                  ),
                ),
              ),
            ),

            // JOKER TACI ROZETİ
            if (wild)
              Positioned(
                top: 3,
                right: 3,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF59E0B), Color(0xFFB45309)],
                    ),
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: const [
                      BoxShadow(color: Colors.black38, blurRadius: 3),
                    ],
                  ),
                  child: Text(
                    '👑 JKR',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: (width * 0.105).clamp(7.0, 9.5),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),

            // YENİ ÇEKİLEN KAĞIT PARILTI ROZETİ
            if (isNewlyDrawn)
              Positioned(
                top: wild ? 18 : 3,
                right: 3,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'YENİ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: (width * 0.10).clamp(7.0, 9.0),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),

            // PER ŞERİDİ (Altın-Zümrüt İnce Alt Bant)
            if (isMelded)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFD97706).withValues(alpha: 0.95),
                        const Color(0xFFF59E0B).withValues(alpha: 0.95),
                      ],
                    ),
                  ),
                  child: Text(
                    '✓ PER',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: (width * 0.105).clamp(7.0, 9.5),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (isNewlyDrawn) {
      cardBody = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutBack,
        builder: (context, val, child) {
          return Transform.translate(
            offset: Offset(0, -36 * (1.0 - val)),
            child: Transform.scale(
              scale: 0.85 + (0.15 * val),
              child: child,
            ),
          );
        },
        child: cardBody,
      );
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: cardBody,
      );
    }
    return cardBody;
  }
}

/// Zynga UI tasarımındaki gibi 3 boyutlu katmanlı kırmızı-altın Kapalı Deste görünümü
class CardBackWidget extends StatelessWidget {
  final double width;
  final double height;
  final String? badgeText;
  final int? deckCount;

  const CardBackWidget({
    super.key,
    this.width = 76,
    this.height = 112,
    this.badgeText,
    this.deckCount,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width + 6,
      height: height + 8,
      child: Stack(
        children: [
          // 3D Alt Deste Katmanları (Kalın kağıt yığını efekti)
          Positioned(
            left: 5,
            top: 6,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(width * 0.12),
                border: Border.all(color: Colors.black45, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.65),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 2.5,
            top: 3,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(width * 0.12),
                border: Border.all(color: Colors.black38, width: 1),
              ),
            ),
          ),
          // En Üstteki Kraliyet Kırmızı & Altın İşlemeli Sırt Kartı
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFB91C1C),
                    Color(0xFF7F1D1D),
                    Color(0xFF450A0A),
                  ],
                ),
                borderRadius: BorderRadius.circular(width * 0.12),
                border: Border.all(color: const Color(0xFFFDE047), width: 2.0),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Altın Filigran Çerçeve
                  Container(
                    margin: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(width * 0.08),
                      border: Border.all(
                        color: const Color(0xFFFDE047).withValues(alpha: 0.65),
                        width: 1.3,
                      ),
                    ),
                  ),
                  // Ortadaki Altın Madalyon (Kalan Kağıt Sayısı)
                  Container(
                    width: width * 0.54,
                    height: width * 0.54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Color(0xFF991B1B), Color(0xFF450A0A)],
                      ),
                      border: Border.all(
                        color: const Color(0xFFFACC15),
                        width: 1.8,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        deckCount != null ? '$deckCount' : (badgeText ?? '⚜️'),
                        style: TextStyle(
                          color: const Color(0xFFFDE047),
                          fontWeight: FontWeight.w900,
                          fontSize: width * 0.24,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
