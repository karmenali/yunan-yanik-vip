import 'package:flutter/services.dart';

class SoundFx {
  static bool soundEnabled = true;

  /// Son 5 saniye geri sayım sesli ve titreşimli uyarısı
  static Future<void> playCountdownBeep({bool urgent = false}) async {
    if (!soundEnabled) return;
    try {
      await SystemSound.play(SystemSoundType.alert);
      await SystemSound.play(SystemSoundType.click);
      if (urgent) {
        await HapticFeedback.heavyImpact();
      } else {
        await HapticFeedback.mediumImpact();
      }
    } catch (_) {}
  }

  /// Kağıt çekme / atma sesi
  static Future<void> playCardTap() async {
    if (!soundEnabled) return;
    try {
      await SystemSound.play(SystemSoundType.click);
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Zafer / El açma / Efekt uyarısı
  static Future<void> playCelebration() async {
    if (!soundEnabled) return;
    try {
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.vibrate();
    } catch (_) {}
  }
}
