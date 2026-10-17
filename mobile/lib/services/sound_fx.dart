import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SoundFx {
  static bool soundEnabled = true;
  static bool voiceEnabled = true;

  static final AudioPlayer _sfxPlayer = AudioPlayer();
  static final AudioPlayer _voicePlayer = AudioPlayer();
  static final AudioRecorder _recorder = AudioRecorder();
  static bool _isRecording = false;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    soundEnabled = prefs.getBool('sound_enabled') ?? true;
    voiceEnabled = prefs.getBool('voice_enabled') ?? true;
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

  /// Bellek içinde 16-bit PCM WAV ses dalgası üretir (Harici ses dosyasına ihtiyaç duymaz)
  static Uint8List _generateToneWav({
    required double startFreq,
    required double endFreq,
    required int durationMs,
    double volume = 0.55,
  }) {
    const int sampleRate = 22050;
    final int numSamples = ((sampleRate * durationMs) / 1000).round();
    final int dataSize = numSamples * 2;
    final ByteData buffer = ByteData(44 + dataSize);

    // RIFF başlığı
    void writeString(int offset, String s) {
      for (int i = 0; i < s.length; i++) {
        buffer.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeString(0, 'RIFF');
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little); // PCM
    buffer.setUint16(20, 1, Endian.little); // Format = 1
    buffer.setUint16(22, 1, Endian.little); // Tek kanal (Mono)
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
      // Yumuşak zarf (Attack & Decay)
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
        volume: 0.7,
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

  /// Kağıt seçme / dizme sesi
  static Future<void> playCardTap() async {
    if (!soundEnabled) return;
    try {
      final wav = _generateToneWav(
        startFreq: 520,
        endFreq: 680,
        durationMs: 45,
        volume: 0.35,
      );
      await _sfxPlayer.stop();
      await _sfxPlayer.play(BytesSource(wav));
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Desteden kağıt çekme akıcı ses efekti
  static Future<void> playCardDraw() async {
    if (!soundEnabled) return;
    try {
      final wav = _generateToneWav(
        startFreq: 380,
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
        startFreq: 660,
        endFreq: 320,
        durationMs: 80,
        volume: 0.5,
      );
      await _sfxPlayer.stop();
      await _sfxPlayer.play(BytesSource(wav));
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Zafer / El açma / Efekt uyarısı
  static Future<void> playCelebration() async {
    if (!soundEnabled) return;
    try {
      final wav = _generateToneWav(
        startFreq: 523.25,
        endFreq: 1046.5,
        durationMs: 240,
        volume: 0.65,
      );
      await _sfxPlayer.stop();
      await _sfxPlayer.play(BytesSource(wav));
      await HapticFeedback.vibrate();
    } catch (_) {}
  }

  // ==========================================
  // 🎙️ BAS-KONUŞ (WALKIE-TALKIE) SES KAYIT VE OYNATMA
  // ==========================================

  static Future<bool> startPttRecording() async {
    if (!voiceEnabled || _isRecording) return false;
    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        return false;
      }

      if (await _recorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final filePath =
            '${tempDir.path}/ptt_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 32000,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: filePath,
        );
        _isRecording = true;
        await HapticFeedback.mediumImpact();
        return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<String?> stopPttRecordingAndGetBase64() async {
    if (!_isRecording) return null;
    _isRecording = false;
    try {
      final path = await _recorder.stop();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          await file.delete().catchError((_) => file);
          if (bytes.length > 100) {
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
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/rx_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
      await tempFile.writeAsBytes(bytes, flush: true);
      await _voicePlayer.stop();
      await _voicePlayer.play(DeviceFileSource(tempFile.path));
    } catch (_) {}
  }
}
