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
    this.width = 76,
    this.height = 112,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool wild = card.isWild(wildRank);
    final bool isRed = !card.isPhysicalJoker && (card.suit == 'H' || card.suit == 'D');
    final Color mainColor = card.isPhysicalJoker
        ? const Color(0xFF6D28D9)
        : isRed
            ? const Color(0xFFDC2626)
            : const Color(0xFF0F172A);

    Color borderColor = const Color(0xFFCBD5E1);
    double borderWidth = 1.6;

    if (isSelected) {
      borderColor = const Color(0xFFFACC15);
      borderWidth = 3.2;
    } else if (isNewlyDrawn) {
      borderColor = const Color(0xFF38BDF8);
      borderWidth = 3.0;
    } else if (isWinningDiscardCandidate) {
      borderColor = const Color(0xFFEF4444);
      borderWidth = 2.8;
    } else if (isMelded) {
      borderColor = const Color(0xFF10B981);
      borderWidth = 2.6;
    } else if (wild) {
      borderColor = const Color(0xFFD97706);
      borderWidth = 2.4;
    }

    Widget cardBody = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: wild
              ? [const Color(0xFFFFFBEB), const Color(0xFFFEF3C7)]
              : [Colors.white, const Color(0xFFF8FAFC)],
        ),
        borderRadius: BorderRadius.circular(width * 0.13),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? const Color(0xFFFACC15).withValues(alpha: 0.65)
                : isNewlyDrawn
                    ? const Color(0xFF38BDF8).withValues(alpha: 0.65)
                    : Colors.black.withValues(alpha: 0.55),
            blurRadius: (isSelected || isNewlyDrawn) ? 14 : 7,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.11),
        child: Stack(
          children: [
            // Sol Üst Köşe: Çok net, büyük sayı ve altında sembol (Batak HD tarzı)
            Positioned(
              top: width * 0.05,
              left: width * 0.07,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    card.isPhysicalJoker ? 'JKR' : card.rankLabel,
                    style: TextStyle(
                      color: mainColor,
                      fontWeight: FontWeight.w900,
                      fontSize: card.isPhysicalJoker ? width * 0.18 : width * 0.30,
                      height: 0.95,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    card.suitSymbol,
                    style: TextStyle(
                      color: mainColor,
                      fontSize: width * 0.25,
                      height: 0.95,
                    ),
                  ),
                ],
              ),
            ),

            // Orta Büyük Sembol
            Align(
              alignment: const Alignment(0.15, 0.18),
              child: Text(
                card.suitSymbol,
                style: TextStyle(
                  color: mainColor.withValues(alpha: 0.92),
                  fontSize: width * 0.48,
                  height: 1.0,
                ),
              ),
            ),

            // Sağ Alt Köşe Küçük Sayı
            Positioned(
              bottom: width * 0.05,
              right: width * 0.07,
              child: Text(
                card.isPhysicalJoker ? '★' : card.rankLabel,
                style: TextStyle(
                  color: mainColor.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w900,
                  fontSize: width * 0.19,
                  height: 1.0,
                ),
              ),
            ),

            // JOKER Rozeti (Fiziksel Joker veya Gösterge Jokeri)
            if (wild)
              Positioned(
                top: 3,
                right: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFD97706), Color(0xFFB45309)],
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '👑 JOKER',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: (width * 0.105).clamp(7.0, 10.0),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),

            // Yeni Çekilen Kart Rozeti
            if (isNewlyDrawn)
              Positioned(
                top: wild ? 18 : 3,
                right: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '✨ YENİ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: (width * 0.105).clamp(7.0, 10.0),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),

            // PER Rozeti
            if (isMelded)
              Positioned(
                bottom: 3,
                left: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '✓ PER',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: (width * 0.105).clamp(7.0, 10.0),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // Yeni çekilen kağıt için akıcı yukarıdan el içine kayma (slide + scale) animasyonu
    if (isNewlyDrawn) {
      cardBody = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutBack,
        builder: (context, val, child) {
          return Transform.translate(
            offset: Offset(0, -45 * (1.0 - val)),
            child: Transform.scale(
              scale: 0.8 + (0.2 * val),
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

class CardBackWidget extends StatelessWidget {
  final double width;
  final double height;
  final String? badgeText;

  const CardBackWidget({
    super.key,
    this.width = 76,
    this.height = 112,
    this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF991B1B), Color(0xFF450A0A)],
        ),
        borderRadius: BorderRadius.circular(width * 0.13),
        border: Border.all(color: const Color(0xFFFDE047), width: 2.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            margin: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(width * 0.09),
              border: Border.all(
                color: const Color(0xFFFDE047).withValues(alpha: 0.45),
                width: 1.2,
              ),
            ),
            child: Center(
              child: Text(
                '⚜️',
                style: TextStyle(fontSize: width * 0.34),
              ),
            ),
          ),
          if (badgeText != null)
            Positioned(
              bottom: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDE047), width: 1),
                ),
                child: Text(
                  badgeText!,
                  style: const TextStyle(
                    color: Color(0xFFFDE047),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
