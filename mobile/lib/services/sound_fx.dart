import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SoundFx {
  static bool soundEnabled = true;
  static bool voiceEnabled = true;

  static final AudioPlayer _sfxPlayer = AudioPlayer();
  static final AudioPlayer _voicePlayer = AudioPlayer();
  static final AudioRecorder _recorder = AudioRecorder();
  static bool _isRecording = false;

  static bool get isRecording => _isRecording;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    soundEnabled = prefs.getBool('sound_enabled') ?? true;
    voiceEnabled = prefs.getBool('voice_enabled') ?? true;
    await _sfxPlayer.setReleaseMode(ReleaseMode.stop);
    await _voicePlayer.setReleaseMode(ReleaseMode.stop);
    await _voicePlayer.setVolume(1.0);
  }

  static Future<void> setSoundEnabled(bool val) async {
    soundEnabled = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sound_enabled', val);
  }

  static Future<void> setVoiceEnabled(bool val) async {
    voiceEnabled = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_enabled', val);
  }

  /// Harici ses dosyasına ihtiyaç duymadan bellek içinde 16-bit PCM WAV ses dalgası üretir.
  static Uint8List _generateToneWav({
    required double startFreq,
    required double endFreq,
    required int durationMs,
    double volume = 0.55,
  }) {
    const int sampleRate = 22050;
    final int numSamples = ((sampleRate * durationMs) / 1000).round();
    final int dataSize = numSamples * 2; // 16-bit mono
    final int fileSize = 36 + dataSize;

    final ByteData buffer = ByteData(44 + dataSize);

    void writeString(int offset, String s) {
      for (int i = 0; i < s.length; i++) {
        buffer.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeString(0, 'RIFF');
    buffer.setUint32(4, fileSize, Endian.little);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little); // PCM
    buffer.setUint16(20, 1, Endian.little); // Format = 1
    buffer.setUint16(22, 1, Endian.little); // Mono
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little);
    buffer.setUint16(32, 2, Endian.little);
    buffer.setUint16(34, 16, Endian.little);
    writeString(36, 'data');
    buffer.setUint32(40, dataSize, Endian.little);

    double phase = 0;
    for (int i = 0; i < numSamples; i++) {
      final double progress = i / numSamples;
      final double freq = startFreq + (endFreq - startFreq) * progress;
      final double envelope = math.sin(progress * math.pi);
      phase += (2 * math.pi * freq) / sampleRate;
      final double sample = math.sin(phase) * volume * envelope;
      final int pcmVal = (sample * 32767).round().clamp(-32768, 32767);
      buffer.setInt16(44 + i * 2, pcmVal, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  /// Son 5 saniye geri sayım sesli "Bip" uyarısı
  static Future<void> playCountdownBeep({bool urgent = false}) async {
    if (!soundEnabled) return;
    try {
      final wav = _generateToneWav(
        startFreq: urgent ? 1240 : 880,
        endFreq: urgent ? 1320 : 880,
        durationMs: urgent ? 140 : 100,
        volume: 0.75,
      );
      await _sfxPlayer.stop();
      await _sfxPlayer.play(BytesSource(wav));
      if (urgent) {
        await HapticFeedback.heavyImpact();
      } else {
        await HapticFeedback.mediumImpact();
      }
    } catch (_) {}
  }

  /// Telsiz konuşma başlangıç bip sesi
  static Future<void> playPttStartBeep() async {
    try {
      final wav = _generateToneWav(
        startFreq: 680,
        endFreq: 1020,
        durationMs: 85,
        volume: 0.55,
      );
      await _sfxPlayer.stop();
      await _sfxPlayer.play(BytesSource(wav));
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Telsiz konuşma bitiş / gönderim bip sesi
  static Future<void> playPttEndBeep() async {
    try {
      final wav = _generateToneWav(
        startFreq: 980,
        endFreq: 620,
        durationMs: 90,
        volume: 0.55,
      );
      await _sfxPlayer.stop();
      await _sfxPlayer.play(BytesSource(wav));
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// Kağıt seçme / dizme sesi
  static Future<void> playCardTap() async {
    if (!soundEnabled) return;
    try {
      final wav = _generateToneWav(
        startFreq: 520,
        endFreq: 680,
        durationMs: 40,
        volume: 0.35,
      );
      await _sfxPlayer.stop();
      await _sfxPlayer.play(BytesSource(wav));
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Desteden kağıt çekme ("Şırak") sesi
  static Future<void> playCardDraw() async {
    if (!soundEnabled) return;
    try {
      final wav = _generateToneWav(
        startFreq: 340,
        endFreq: 760,
        durationMs: 95,
        volume: 0.5,
      );
      await _sfxPlayer.stop();
      await _sfxPlayer.play(BytesSource(wav));
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// Yere kağıt atma sesi
  static Future<void> playCardDiscard() async {
    if (!soundEnabled) return;
    try {
      final wav = _generateToneWav(
        startFreq: 620,
        endFreq: 280,
        durationMs: 90,
        volume: 0.5,
      );
      await _sfxPlayer.stop();
      await _sfxPlayer.play(BytesSource(wav));
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// El açma / kazanma zafer sesi
  static Future<void> playCelebration() async {
    if (!soundEnabled) return;
    try {
      final wav = _generateToneWav(
        startFreq: 523.25, // C5
        endFreq: 1046.50, // C6
        durationMs: 280,
        volume: 0.65,
      );
      await _sfxPlayer.stop();
      await _sfxPlayer.play(BytesSource(wav));
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  // ==========================================
  // 🎙️ BAS-KONUŞ & DOKUN-KONUŞ (16kHz PCM WAV - SIFIR GECİKME)
  // ==========================================

  static Future<bool> startPttRecording() async {
    if (!voiceEnabled) return false;
    if (_isRecording) return true;
    try {
      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) return false;

      await playPttStartBeep();

      final tempDir = await getTemporaryDirectory();
      final filePath =
          '${tempDir.path}/ptt_${DateTime.now().millisecondsSinceEpoch}.wav';

      // WAV (16-bit PCM, 16kHz Mono) tüm Android cihazlarda 0 ms kodek gecikmesiyle çalışır
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: filePath,
      );
      _isRecording = true;
      return true;
    } catch (_) {
      _isRecording = false;
      return false;
    }
  }

  static Future<String?> stopPttRecordingAndGetBase64() async {
    if (!_isRecording) return null;
    _isRecording = false;
    try {
      final path = await _recorder.stop();
      await playPttEndBeep();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          await file.delete().catchError((_) => file);
          // Geçerli bir WAV ses kaydı (44 byte başlık + en az 800 byte ses verisi)
          if (bytes.length > 800) {
            return base64Encode(bytes);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> playIncomingVoiceBase64(String base64Audio) async {
    if (!voiceEnabled || base64Audio.isEmpty) return;
    try {
      final bytes = base64Decode(base64Audio);
      if (bytes.length <= 44) return;
      await _voicePlayer.stop();
      await _voicePlayer.setVolume(1.0);
      // WAV baytlarını doğrudan RAM'den (BytesSource) anında çalar!
      await _voicePlayer.play(BytesSource(bytes));
    } catch (_) {
      // Fallback: Cihaz BytesSource desteklemezse geçici dosyadan çal
      try {
        final bytes = base64Decode(base64Audio);
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(
          '${tempDir.path}/rx_${DateTime.now().millisecondsSinceEpoch}.wav',
        );
        await tempFile.writeAsBytes(bytes, flush: true);
        await _voicePlayer.play(DeviceFileSource(tempFile.path));
      } catch (_) {}
    }
  }
}
