import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Zynga Poker & Batak HD seviyesinde GPU hızlandırmalı Vektörel İskambil Çizim Motoru
class VectorCardPainter extends CustomPainter {
  final int rank; // 1: A, 2..10, 11: J, 12: Q, 13: K, 0: Joker
  final String suit; // 'S': Maça, 'H': Kupa, 'D': Karo, 'C': Sinek, 'J': Joker
  final bool isPhysicalJoker;
  final bool showAsWild;
  final bool isSelected;
  final bool isWinningDiscardCandidate;

  VectorCardPainter({
    required this.rank,
    required this.suit,
    this.isPhysicalJoker = false,
    this.showAsWild = false,
    this.isSelected = false,
    this.isWinningDiscardCandidate = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. KART GÖVDESİ & CASINO FİLDİŞİ DOKUSU
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular((w * 0.12).clamp(5.0, 10.0)),
    );

    // Hafif zengin gölge
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: isSelected ? 0.35 : 0.18)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, isSelected ? 6 : 2.5);
    canvas.drawRRect(rrect.shift(Offset(0, isSelected ? 4 : 1.5)), shadowPaint);

    // Kart Kağıdı Dolgusu (Casino ivory fildişi)
    final cardBgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFF9FAFB), Color(0xFFF3F4F6)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRRect(rrect, cardBgPaint);

    // Kart Kenar Çizgisi (Border)
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 2.0 : 1.0
      ..color = isSelected
          ? const Color(0xFFF59E0B)
          : (showAsWild
              ? const Color(0xFFF59E0B)
              : const Color(0xFFD1D5DB).withValues(alpha: 0.85));
    canvas.drawRRect(rrect, borderPaint);

    // 2. RENKLER
    final bool isRed = suit == 'H' || suit == 'D';
    final Color suitColor = isPhysicalJoker
        ? const Color(0xFF7C3AED)
        : (isRed ? const Color(0xFFDC2626) : const Color(0xFF1E293B));

    if (isPhysicalJoker) {
      _paintJoker(canvas, w, h);
      return;
    }

    // 3. KÖŞE İNDEKSLERİ (SOL ÜST & SAĞ ALT - TERS SİMETRİK)
    _paintCorner(canvas, w, h, suitColor, isTop: true);
    if (h >= 55) {
      _paintCorner(canvas, w, h, suitColor, isTop: false);
    }

    // 4. MERKEZ DESENİ (AS, RESİMLİ KARTLAR VEYA PİPLER)
    _paintCenterArt(canvas, w, h, suitColor);
  }

  void _paintCorner(Canvas canvas, double w, double h, Color color, {required bool isTop}) {
    canvas.save();
    if (!isTop) {
      canvas.translate(w, h);
      canvas.rotate(math.pi);
    }

    final double padX = (w * 0.08).clamp(3.0, 6.0);
    final double padY = (h * 0.05).clamp(2.5, 5.0);

    // Sayı / Harf
    final label = _getRankLabel();
    final double fontSize = (w * 0.22).clamp(9.5, 15.0);
    final textSpan = TextSpan(
      text: label,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        letterSpacing: rank == 10 ? -1.0 : -0.3,
        height: 1.0,
      ),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, Offset(padX, padY));

    // Köşedeki küçük sembol
    final double suitY = padY + tp.height + 1.2;
    final double cornerSuitSize = (w * 0.15).clamp(6.5, 10.0);
    _drawSuitVector(
      canvas,
      suit,
      Offset(padX + tp.width / 2, suitY + cornerSuitSize / 2),
      cornerSuitSize,
      color,
    );

    canvas.restore();
  }

  void _paintCenterArt(Canvas canvas, double w, double h, Color color) {
    final center = Offset(w / 2, h / 2);

    // AS (A) - Lüks Casino Amblemi
    if (rank == 1) {
      final double aceSize = (w * 0.42).clamp(20.0, 38.0);
      _drawSuitVector(canvas, suit, center, aceSize, color);
      return;
    }

    // RESİMLİ KARTLAR (J, Q, K) - Kraliyet Rozeti
    if (rank >= 11 && rank <= 13) {
      _drawRoyalMedallion(canvas, w, h, center, color);
      return;
    }

    // 2..10 SAYI KARTLARI (Kusursuz Oransal Pip Matrisi)
    _drawPipMatrix(canvas, w, h, color);
  }

  void _drawRoyalMedallion(Canvas canvas, double w, double h, Offset center, Color color) {
    final double mw = (w * 0.52).clamp(22.0, 42.0);
    final double mh = (h * 0.58).clamp(30.0, 60.0);

    final rect = Rect.fromCenter(center: center, width: mw, height: mh);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(mw * 0.18));

    // Arka plan altın çerçeveli minyatür
    final bgPaint = Paint()..color = color.withValues(alpha: 0.05);
    canvas.drawRRect(rrect, bgPaint);

    final strokePaint = Paint()
      ..color = const Color(0xFFD4AF37).withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(rrect, strokePaint);

    // Merkez Harfi (J, Q, K)
    final label = _getRankLabel();
    final double fontSize = (mw * 0.50).clamp(12.0, 22.0);
    final textSpan = TextSpan(
      text: label,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        height: 1.0,
      ),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));

    // Üstte ve altta minik takım sembolü
    final double miniSize = (mw * 0.28).clamp(6.0, 10.0);
    _drawSuitVector(canvas, suit, Offset(center.dx, rect.top + miniSize * 0.9), miniSize, color);
    _drawSuitVector(canvas, suit, Offset(center.dx, rect.bottom - miniSize * 0.9), miniSize, color);
  }

  void _drawPipMatrix(Canvas canvas, double w, double h, Color color) {
    final double pipSize = (w * 0.19).clamp(8.0, 13.0);

    // Güvenli iç çizim alanı (köşe indekslerine asla değmez!)
    final double leftCol = w * 0.33;
    final double midCol = w * 0.50;
    final double rightCol = w * 0.67;

    final double topRow = h * 0.25;
    final double upperMidRow = h * 0.38;
    final double centerRow = h * 0.50;
    final double lowerMidRow = h * 0.62;
    final double bottomRow = h * 0.75;

    void draw(double x, double y, {bool inverted = false}) {
      _drawSuitVector(canvas, suit, Offset(x, y), pipSize, color, inverted: inverted);
    }

    switch (rank) {
      case 2:
        draw(midCol, topRow);
        draw(midCol, bottomRow, inverted: true);
        break;
      case 3:
        draw(midCol, topRow);
        draw(midCol, centerRow);
        draw(midCol, bottomRow, inverted: true);
        break;
      case 4:
        draw(leftCol, topRow);
        draw(rightCol, topRow);
        draw(leftCol, bottomRow, inverted: true);
        draw(rightCol, bottomRow, inverted: true);
        break;
      case 5:
        draw(leftCol, topRow);
        draw(rightCol, topRow);
        draw(midCol, centerRow);
        draw(leftCol, bottomRow, inverted: true);
        draw(rightCol, bottomRow, inverted: true);
        break;
      case 6:
        draw(leftCol, topRow);
        draw(rightCol, topRow);
        draw(leftCol, centerRow);
        draw(rightCol, centerRow);
        draw(leftCol, bottomRow, inverted: true);
        draw(rightCol, bottomRow, inverted: true);
        break;
      case 7:
        draw(leftCol, topRow);
        draw(rightCol, topRow);
        draw(midCol, upperMidRow);
        draw(leftCol, centerRow);
        draw(rightCol, centerRow);
        draw(leftCol, bottomRow, inverted: true);
        draw(rightCol, bottomRow, inverted: true);
        break;
      case 8:
        draw(leftCol, topRow);
        draw(rightCol, topRow);
        draw(midCol, upperMidRow);
        draw(leftCol, centerRow);
        draw(rightCol, centerRow);
        draw(midCol, lowerMidRow, inverted: true);
        draw(leftCol, bottomRow, inverted: true);
        draw(rightCol, bottomRow, inverted: true);
        break;
      case 9:
        draw(leftCol, topRow);
        draw(rightCol, topRow);
        draw(leftCol, upperMidRow);
        draw(rightCol, upperMidRow);
        draw(midCol, centerRow);
        draw(leftCol, lowerMidRow, inverted: true);
        draw(rightCol, lowerMidRow, inverted: true);
        draw(leftCol, bottomRow, inverted: true);
        draw(rightCol, bottomRow, inverted: true);
        break;
      case 10:
        draw(leftCol, topRow);
        draw(rightCol, topRow);
        draw(midCol, h * 0.32);
        draw(leftCol, upperMidRow);
        draw(rightCol, upperMidRow);
        draw(leftCol, lowerMidRow, inverted: true);
        draw(rightCol, lowerMidRow, inverted: true);
        draw(midCol, h * 0.68, inverted: true);
        draw(leftCol, bottomRow, inverted: true);
        draw(rightCol, bottomRow, inverted: true);
        break;
      default:
        draw(midCol, centerRow);
    }
  }

  void _paintJoker(Canvas canvas, double w, double h) {
    final center = Offset(w / 2, h / 2);
    final double starSize = (w * 0.35).clamp(16.0, 28.0);
    final starPaint = Paint()..color = const Color(0xFFF59E0B);

    final path = Path();
    for (int i = 0; i < 5; i++) {
      final double rExt = starSize;
      final double rInt = starSize * 0.45;
      final double aExt = (i * 72 - 90) * math.pi / 180;
      final double aInt = (i * 72 + 36 - 90) * math.pi / 180;
      if (i == 0) {
        path.moveTo(center.dx + rExt * math.cos(aExt), center.dy + rExt * math.sin(aExt));
      } else {
        path.lineTo(center.dx + rExt * math.cos(aExt), center.dy + rExt * math.sin(aExt));
      }
      path.lineTo(center.dx + rInt * math.cos(aInt), center.dy + rInt * math.sin(aInt));
    }
    path.close();
    canvas.drawPath(path, starPaint);

    // JOKER Yazısı
    final textSpan = const TextSpan(
      text: 'JOKER',
      style: TextStyle(
        color: Color(0xFF7C3AED),
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
      ),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy + starSize * 1.1));
  }

  /// Gerçek Vektörel İskambil Sembolü Çizimi (Maça, Kupa, Karo, Sinek)
  void _drawSuitVector(
    Canvas canvas,
    String suitKey,
    Offset center,
    double size,
    Color color, {
    bool inverted = false,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (inverted) canvas.rotate(math.pi);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final s = size / 24.0; // 24x24 normalize standart vektör grid'i
    final path = Path();

    switch (suitKey) {
      case 'S': // MAÇA (Spades ♠)
        path.moveTo(0, -11 * s);
        path.cubicTo(-4 * s, -6 * s, -10 * s, -1 * s, -10 * s, 4 * s);
        path.cubicTo(-10 * s, 8 * s, -6 * s, 10 * s, -1 * s, 7 * s);
        path.cubicTo(-2 * s, 10 * s, -4 * s, 11 * s, -6 * s, 11 * s);
        path.lineTo(6 * s, 11 * s);
        path.cubicTo(4 * s, 11 * s, 2 * s, 10 * s, 1 * s, 7 * s);
        path.cubicTo(6 * s, 10 * s, 10 * s, 8 * s, 10 * s, 4 * s);
        path.cubicTo(10 * s, -1 * s, 4 * s, -6 * s, 0, -11 * s);
        break;

      case 'H': // KUPA (Hearts ♥)
        path.moveTo(0, 10 * s);
        path.cubicTo(-5 * s, 5 * s, -11 * s, 0 * s, -11 * s, -5 * s);
        path.cubicTo(-11 * s, -9.5 * s, -6.5 * s, -11 * s, -2 * s, -7.5 * s);
        path.lineTo(0, -5 * s);
        path.lineTo(2 * s, -7.5 * s);
        path.cubicTo(6.5 * s, -11 * s, 11 * s, -9.5 * s, 11 * s, -5 * s);
        path.cubicTo(11 * s, 0 * s, 5 * s, 5 * s, 0, 10 * s);
        break;

      case 'D': // KARO (Diamonds ♦)
        path.moveTo(0, -11.5 * s);
        path.lineTo(8.5 * s, 0);
        path.lineTo(0, 11.5 * s);
        path.lineTo(-8.5 * s, 0);
        path.close();
        break;

      case 'C': // SİNEK (Clubs ♣)
        // Üst daire
        path.addOval(Rect.fromCircle(center: Offset(0, -5 * s), radius: 4.8 * s));
        // Sol daire
        path.addOval(Rect.fromCircle(center: Offset(-5.2 * s, 1.5 * s), radius: 4.8 * s));
        // Sağ daire
        path.addOval(Rect.fromCircle(center: Offset(5.2 * s, 1.5 * s), radius: 4.8 * s));
        // Merkez dolgu
        path.addRect(Rect.fromLTWH(-2 * s, -3 * s, 4 * s, 6 * s));
        // Ayak / Gövde
        final stem = Path()
          ..moveTo(-1 * s, 2 * s)
          ..lineTo(-5 * s, 11 * s)
          ..lineTo(5 * s, 11 * s)
          ..lineTo(1 * s, 2 * s)
          ..close();
        path.addPath(stem, Offset.zero);
        break;
    }

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  String _getRankLabel() {
    switch (rank) {
      case 1:
        return 'A';
      case 11:
        return 'J';
      case 12:
        return 'Q';
      case 13:
        return 'K';
      default:
        return rank.toString();
    }
  }

  @override
  bool shouldRepaint(covariant VectorCardPainter old) {
    return old.rank != rank ||
        old.suit != suit ||
        old.isPhysicalJoker != isPhysicalJoker ||
        old.showAsWild != showAsWild ||
        old.isSelected != isSelected ||
        old.isWinningDiscardCandidate != isWinningDiscardCandidate;
  }
}
