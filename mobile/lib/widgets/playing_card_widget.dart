import 'package:flutter/material.dart';
import '../models/game_models.dart';

class PlayingCardWidget extends StatelessWidget {
  final CardModel card;
  final int wildRank;
  final bool isSelected;
  final bool isMelded;
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
    this.isWinningDiscardCandidate = false,
    this.width = 66,
    this.height = 96,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool wild = card.isWild(wildRank);
    final Color suitColor = card.suitColor;

    Color borderColor = const Color(0xFFD4AF37).withValues(alpha: 0.45);
    double borderWidth = 1.4;
    if (isSelected) {
      borderColor = const Color(0xFFFACC15);
      borderWidth = 3.0;
    } else if (isWinningDiscardCandidate) {
      borderColor = const Color(0xFFEF4444);
      borderWidth = 2.6;
    } else if (isMelded) {
      borderColor = const Color(0xFF10B981);
      borderWidth = 2.4;
    } else if (wild) {
      borderColor = const Color(0xFFA855F7);
      borderWidth = 2.2;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
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
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? const Color(0xFFFACC15).withValues(alpha: 0.55)
                  : isMelded
                      ? const Color(0xFF10B981).withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.45),
              blurRadius: isSelected ? 12 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Sol üst sayı ve sembol
            Positioned(
              top: 4,
              left: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    card.isPhysicalJoker ? '★' : card.rankLabel,
                    style: TextStyle(
                      color: suitColor,
                      fontWeight: FontWeight.w900,
                      fontSize: width * 0.23,
                      height: 1.0,
                    ),
                  ),
                  Text(
                    card.suitSymbol,
                    style: TextStyle(
                      color: suitColor,
                      fontSize: width * 0.21,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
            ),

            // Orta büyük sembol
            Center(
              child: Text(
                card.suitSymbol,
                style: TextStyle(
                  color: suitColor.withValues(alpha: 0.88),
                  fontSize: width * 0.44,
                ),
              ),
            ),

            // Sağ alt ters sayı
            Positioned(
              bottom: 4,
              right: 5,
              child: Text(
                card.isPhysicalJoker ? 'JKR' : card.rankLabel,
                style: TextStyle(
                  color: suitColor.withValues(alpha: 0.7),
                  fontWeight: FontWeight.bold,
                  fontSize: width * 0.17,
                ),
              ),
            ),

            // Joker veya Gösterge Jokeri rozeti
            if (wild)
              Positioned(
                top: 2,
                right: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'JOKER',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 7.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

            // Per rozeti
            if (isMelded)
              Positioned(
                bottom: 2,
                left: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'PER',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 7.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CardBackWidget extends StatelessWidget {
  final double width;
  final double height;
  final String? badgeText;

  const CardBackWidget({
    super.key,
    this.width = 66,
    this.height = 96,
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
          colors: [Color(0xFF064E3B), Color(0xFF022C22)],
        ),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFD4AF37), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            margin: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.45),
                width: 1,
              ),
            ),
            child: const Center(
              child: Text(
                '⚜️',
                style: TextStyle(fontSize: 22),
              ),
            ),
          ),
          if (badgeText != null)
            Positioned(
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD4AF37), width: 0.8),
                ),
                child: Text(
                  badgeText!,
                  style: const TextStyle(
                    color: Color(0xFFFDE047),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
