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

/// Orijinal Bicycle Kırmızı & Altın Filigranlı Otantik Casino İskambil Sırtı
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
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Katmanlı 3D deste efekti (Alttaki kart gölgeleri)
          if (deckCount != null && deckCount! > 2)
            Positioned(
              left: 3,
              top: 3,
              child: _buildBackPainter(darken: 0.28),
            ),
          if (deckCount != null && deckCount! > 1)
            Positioned(
              left: 1.5,
              top: 1.5,
              child: _buildBackPainter(darken: 0.14),
            ),
          _buildBackPainter(darken: 0.0),

          // Deste kart sayısı göstergesi rozeti
          if (deckCount != null)
            Positioned.fill(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFD4AF37),
                      width: 1.2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '$deckCount',
                    style: const TextStyle(
                      color: Color(0xFFFDE047),
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBackPainter({double darken = 0.0}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular((width * 0.12).clamp(5.0, 10.0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 5,
            offset: const Offset(0, 2.5),
          ),
        ],
      ),
      child: CustomPaint(
        size: Size(width, height),
        painter: ClassicCardBackPainter(
          darken: darken,
          isRed: true,
        ),
      ),
    );
  }
}

/// Gerçek Casino Deste Arkası Çizim Motoru (Bicycle Crimson Red & Diamond Lattice)
class ClassicCardBackPainter extends CustomPainter {
  final double darken;
  final bool isRed;

  const ClassicCardBackPainter({
    this.darken = 0.0,
    this.isRed = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final radius = (w * 0.12).clamp(5.0, 10.0);

    // 1. Dış Beyaz Casino Emniyet Kenarlığı
    final outerRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(radius),
    );
    final whitePaint = Paint()..color = const Color(0xFFFBFBFA);
    canvas.drawRRect(outerRRect, whitePaint);

    final outerBorderPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(outerRRect, outerBorderPaint);

    // 2. İç Kırmızı / Bordo Lake Alan
    final margin = (w * 0.06).clamp(2.5, 4.5);
    final innerRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(margin, margin, w - margin * 2, h - margin * 2),
      Radius.circular(radius - 1.5),
    );

    final baseRed = isRed ? const Color(0xFF991B1B) : const Color(0xFF1E3A8A);
    final darkRed = isRed ? const Color(0xFF6B1111) : const Color(0xFF0F172A);
    final c1 = Color.lerp(baseRed, Colors.black, darken)!;
    final c2 = Color.lerp(darkRed, Colors.black, darken)!;

    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [c1, c2],
      ).createShader(Rect.fromLTWH(margin, margin, w - margin * 2, h - margin * 2));
    canvas.drawRRect(innerRRect, bgPaint);

    // Altın iç çerçeve çizgisi
    final goldBorderPaint = Paint()
      ..color = const Color(0xFFD4AF37).withValues(alpha: 0.75 * (1.0 - darken * 0.5))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawRRect(innerRRect, goldBorderPaint);

    // 3. Geometrik İskambil Baklava / Kafes Dokusu (Diamond Cross-Hatch)
    canvas.save();
    canvas.clipRRect(innerRRect);

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12 * (1.0 - darken * 0.5))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    final step = (w * 0.14).clamp(6.0, 10.0);
    for (double d = -h; d < w + h; d += step) {
      canvas.drawLine(Offset(d, 0), Offset(d + h, h), linePaint);
      canvas.drawLine(Offset(d, h), Offset(d + h, 0), linePaint);
    }

    // 4. Merkez Klasik Çift Simetrik Madalyon
    final center = Offset(w / 2, h / 2);
    final medR = (w * 0.22).clamp(10.0, 18.0);

    // Madalyon dış halkası
    final medRingPaint = Paint()
      ..color = const Color(0xFFD4AF37).withValues(alpha: 0.85 * (1.0 - darken * 0.5))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, medR, medRingPaint);
    canvas.drawCircle(
      center,
      medR * 0.82,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill,
    );

    // Madalyon içi altın maça / filigran motifi
    final spadePaint = Paint()..color = const Color(0xFFD4AF37).withValues(alpha: 0.90);
    final ss = medR * 0.55;
    final path = Path()
      ..moveTo(center.dx, center.dy - ss)
      ..cubicTo(center.dx - ss * 0.5, center.dy - ss * 0.2, center.dx - ss, center.dy + ss * 0.2, center.dx - ss * 0.5, center.dy + ss * 0.6)
      ..cubicTo(center.dx - ss * 0.2, center.dy + ss * 0.7, center.dx - ss * 0.1, center.dy + ss * 0.6, center.dx, center.dy + ss * 0.4)
      ..cubicTo(center.dx + ss * 0.1, center.dy + ss * 0.6, center.dx + ss * 0.2, center.dy + ss * 0.7, center.dx + ss * 0.5, center.dy + ss * 0.6)
      ..cubicTo(center.dx + ss, center.dy + ss * 0.2, center.dx + ss * 0.5, center.dy - ss * 0.2, center.dx, center.dy - ss);
    path.moveTo(center.dx - ss * 0.2, center.dy + ss * 0.8);
    path.lineTo(center.dx + ss * 0.2, center.dy + ss * 0.8);
    path.lineTo(center.dx, center.dy + ss * 0.4);
    path.close();
    canvas.drawPath(path, spadePaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ClassicCardBackPainter oldDelegate) {
    return oldDelegate.darken != darken || oldDelegate.isRed != isRed;
  }
}
