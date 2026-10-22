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

    // RESİMLİ KARTLAR (J, Q, K) - Çift Başlı Otantik Kraliyet Portresi
    if (rank >= 11 && rank <= 13) {
      _drawRoyalCourtFigure(canvas, w, h, center, color);
      return;
    }

    // 2..10 SAYI KARTLARI (Kusursuz Oransal Pip Matrisi)
    _drawPipMatrix(canvas, w, h, color);
  }

  void _drawRoyalCourtFigure(Canvas canvas, double w, double h, Offset center, Color color) {
    final double mw = (w * 0.54).clamp(24.0, 48.0);
    final double mh = (h * 0.62).clamp(34.0, 72.0);

    final rect = Rect.fromCenter(center: center, width: mw, height: mh);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4.0));

    // 1. Minyatür Portre Çerçevesi ve Arka Planı
    final bgPaint = Paint()..color = const Color(0xFFFAF7EE);
    canvas.drawRRect(rrect, bgPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFFD4AF37)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(rrect, borderPaint);

    // İç ince süs çizgisi
    final innerRRect = RRect.fromRectAndRadius(
      rect.deflate(1.8),
      const Radius.circular(2.5),
    );
    final innerBorderPaint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    canvas.drawRRect(innerRRect, innerBorderPaint);

    // Ortadan geçen yatay zarif bölücü kuşak (Sash)
    final double halfH = mh / 2;
    final dividerPaint = Paint()
      ..color = const Color(0xFFD4AF37).withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawLine(
      Offset(rect.left + 2, center.dy),
      Offset(rect.right - 2, center.dy),
      dividerPaint,
    );

    // Kuşak ortasındaki küçük kraliyet baklava motifi
    final diamondPath = Path()
      ..moveTo(center.dx, center.dy - 3)
      ..lineTo(center.dx + 4, center.dy)
      ..lineTo(center.dx, center.dy + 3)
      ..lineTo(center.dx - 4, center.dy)
      ..close();
    canvas.drawPath(diamondPath, Paint()..color = const Color(0xFFD4AF37));

    // 2. ÇİFT BAŞLI PORTRE ÇİZİMİ (ÜST DÜZ & ALT 180° TERS)
    _drawHalfCourtFigure(canvas, mw, halfH, center, color, isTop: true);
    _drawHalfCourtFigure(canvas, mw, halfH, center, color, isTop: false);
  }

  void _drawHalfCourtFigure(
    Canvas canvas,
    double mw,
    double halfH,
    Offset center,
    Color color, {
    required bool isTop,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (!isTop) {
      canvas.rotate(math.pi);
    }

    final double s = (mw / 36.0).clamp(0.65, 1.35);

    // 1. OMUZLAR & KRALİYET BORNOZU / YELKASI (Robe & Mantle)
    final robePath = Path();
    robePath.moveTo(-mw * 0.44, 0);
    robePath.lineTo(-mw * 0.40, -halfH * 0.40);
    robePath.cubicTo(
      -mw * 0.28, -halfH * 0.60,
      -mw * 0.12, -halfH * 0.58,
      -mw * 0.08, -halfH * 0.52,
    );
    robePath.lineTo(0, -halfH * 0.32);
    robePath.lineTo(mw * 0.08, -halfH * 0.52);
    robePath.cubicTo(
      mw * 0.12, -halfH * 0.58,
      mw * 0.28, -halfH * 0.60,
      mw * 0.40, -halfH * 0.40,
    );
    robePath.lineTo(mw * 0.44, 0);
    robePath.close();

    final robeColor = (suit == 'H' || suit == 'D')
        ? const Color(0xFFDC2626).withValues(alpha: 0.12)
        : const Color(0xFF1E293B).withValues(alpha: 0.12);
    canvas.drawPath(robePath, Paint()..color = robeColor);
    canvas.drawPath(
      robePath,
      Paint()
        ..color = const Color(0xFFD4AF37).withValues(alpha: 0.70)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // 2. YÜZ & BAŞ (Head & Face)
    final headY = -halfH * 0.65;
    final headR = 6.2 * s;
    final facePaint = Paint()..color = const Color(0xFFFFF7ED);
    canvas.drawCircle(Offset(0, headY), headR, facePaint);
    canvas.drawCircle(
      Offset(0, headY),
      headR,
      Paint()
        ..color = color.withValues(alpha: 0.60)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7,
    );

    // Saçlar
    final hairPaint = Paint()..color = color.withValues(alpha: 0.75);
    canvas.drawCircle(Offset(-headR * 0.85, headY + 1 * s), 2.8 * s, hairPaint);
    canvas.drawCircle(Offset(headR * 0.85, headY + 1 * s), 2.8 * s, hairPaint);

    // Gözler
    final eyePaint = Paint()..color = color;
    canvas.drawCircle(Offset(-2.0 * s, headY - 0.8 * s), 0.75 * s, eyePaint);
    canvas.drawCircle(Offset(2.0 * s, headY - 0.8 * s), 0.75 * s, eyePaint);

    // 3. FİGÜRE ÖZGÜ ÇİZİMLER (J / Q / K)
    if (rank == 13) {
      // PAPAZ / KRAL (KING - K)
      final beardPath = Path();
      beardPath.moveTo(-3.2 * s, headY + 2.2 * s);
      beardPath.cubicTo(-2.0 * s, headY + 5.8 * s, 2.0 * s, headY + 5.8 * s, 3.2 * s, headY + 2.2 * s);
      beardPath.lineTo(0, headY + 6.6 * s);
      beardPath.close();
      canvas.drawPath(beardPath, Paint()..color = color.withValues(alpha: 0.85));

      final crownY = headY - headR;
      final crownPath = Path()
        ..moveTo(-headR * 0.95, crownY + 1.5 * s)
        ..lineTo(-headR * 0.80, crownY - 5.5 * s)
        ..lineTo(-headR * 0.35, crownY - 1.5 * s)
        ..lineTo(0, crownY - 7.5 * s)
        ..lineTo(headR * 0.35, crownY - 1.5 * s)
        ..lineTo(headR * 0.80, crownY - 5.5 * s)
        ..lineTo(headR * 0.95, crownY + 1.5 * s)
        ..close();
      canvas.drawPath(crownPath, Paint()..color = const Color(0xFFF59E0B));
      canvas.drawPath(
        crownPath,
        Paint()
          ..color = const Color(0xFFB45309)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
      canvas.drawCircle(Offset(0, crownY - 3.5 * s), 1.2 * s, Paint()..color = const Color(0xFFDC2626));

      // Sağ elde Kraliyet Kılıcı
      final swordX = mw * 0.30;
      final swordPath = Path()
        ..moveTo(swordX, -halfH * 0.85)
        ..lineTo(swordX + 1.2 * s, -halfH * 0.15)
        ..lineTo(swordX - 1.2 * s, -halfH * 0.15)
        ..close();
      canvas.drawPath(swordPath, Paint()..color = const Color(0xFF94A3B8));
      canvas.drawRect(
        Rect.fromCenter(center: Offset(swordX, -halfH * 0.15), width: 6.5 * s, height: 1.5 * s),
        Paint()..color = const Color(0xFFD4AF37),
      );

    } else if (rank == 12) {
      // KIZ / KRALİÇE (QUEEN - Q)
      canvas.drawArc(
        Rect.fromCenter(center: Offset(0, headY + 2.2 * s), width: 3.2 * s, height: 2.0 * s),
        0.2,
        math.pi - 0.4,
        false,
        Paint()
          ..color = const Color(0xFFDC2626)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );

      final crownY = headY - headR;
      final tiaraPath = Path()
        ..moveTo(-headR * 0.90, crownY + 1.5 * s)
        ..cubicTo(-headR * 0.5, crownY - 5.0 * s, headR * 0.5, crownY - 5.0 * s, headR * 0.90, crownY + 1.5 * s)
        ..lineTo(headR * 0.60, crownY - 0.5 * s)
        ..lineTo(0, crownY - 6.0 * s)
        ..lineTo(-headR * 0.60, crownY - 0.5 * s)
        ..close();
      canvas.drawPath(tiaraPath, Paint()..color = const Color(0xFFF59E0B));
      canvas.drawPath(
        tiaraPath,
        Paint()
          ..color = const Color(0xFFB45309)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7,
      );
      for (double px in [-4.0 * s, 0, 4.0 * s]) {
        canvas.drawCircle(Offset(px, crownY - 2.5 * s), 0.9 * s, Paint()..color = Colors.white);
      }

      // Sağ elde Kraliyet Çiçeği / Asası
      final flowerX = mw * 0.28;
      final flowerY = -halfH * 0.50;
      canvas.drawLine(
        Offset(flowerX, flowerY + 6 * s),
        Offset(flowerX, 0),
        Paint()
          ..color = const Color(0xFFD4AF37)
          ..strokeWidth = 1.0,
      );
      canvas.drawCircle(Offset(flowerX, flowerY), 2.6 * s, Paint()..color = const Color(0xFFE11D48));
      canvas.drawCircle(Offset(flowerX, flowerY), 1.0 * s, Paint()..color = const Color(0xFFFEF08A));

    } else {
      // VALET / ŞÖVALYE (JACK - J)
      canvas.drawArc(
        Rect.fromCenter(center: Offset(0, headY + 2.0 * s), width: 4.0 * s, height: 1.5 * s),
        0.1,
        math.pi - 0.2,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );

      final capY = headY - headR * 0.6;
      final capPath = Path()
        ..moveTo(-headR * 1.10, capY + 1.0 * s)
        ..cubicTo(-headR * 0.8, capY - 6.5 * s, headR * 0.5, capY - 7.5 * s, headR * 1.05, capY - 1.5 * s)
        ..lineTo(headR * 0.75, capY + 1.5 * s)
        ..close();
      canvas.drawPath(capPath, Paint()..color = const Color(0xFF2563EB));
      canvas.drawPath(
        capPath,
        Paint()
          ..color = const Color(0xFF1D4ED8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
      final featherPath = Path()
        ..moveTo(-headR * 0.70, capY - 3.0 * s)
        ..cubicTo(-headR * 1.30, capY - 8.0 * s, -headR * 0.90, capY - 11.0 * s, -headR * 0.30, capY - 7.0 * s);
      canvas.drawPath(
        featherPath,
        Paint()
          ..color = const Color(0xFFF59E0B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );

      // Sağ elde Mızrak
      final spearX = mw * 0.30;
      canvas.drawLine(
        Offset(spearX, -halfH * 0.80),
        Offset(spearX, 0),
        Paint()
          ..color = const Color(0xFF94A3B8)
          ..strokeWidth = 1.1,
      );
      final spearHead = Path()
        ..moveTo(spearX, -halfH * 0.85)
        ..lineTo(spearX + 3.0 * s, -halfH * 0.70)
        ..lineTo(spearX, -halfH * 0.74)
        ..lineTo(spearX - 3.0 * s, -halfH * 0.70)
        ..close();
      canvas.drawPath(spearHead, Paint()..color = const Color(0xFF64748B));
    }

    // Sol üstte minik Takım Sembolü (Suit Vector)
    final miniSuitX = -mw * 0.28;
    final miniSuitY = -halfH * 0.72;
    _drawSuitVector(canvas, suit, Offset(miniSuitX, miniSuitY), 5.5 * s, color);

    canvas.restore();
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
