import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

/// Zynga / PUBG Mobile Standartlarında Oyun Ses Efektleri + Kesintisiz Canlı Sesli Sohbet (Live Voice Stream) Motoru
class SoundFx {
  static bool soundEnabled = true;
  static bool voiceListenEnabled = true; // 🔊 Hoparlör (Dinle: Açık / Kapalı)
  static bool voiceMicEnabled = false; // 🎙️ Mikrofon (Sürekli Konuş: Açık / Kapalı)

  static bool get voiceEnabled => voiceListenEnabled;
  static Future<void> setVoiceEnabled(bool enabled) async {
    setVoiceListenEnabled(enabled);
  }

  static final AudioPlayer _sfxPlayer = AudioPlayer();
  static final AudioPlayer _voicePlayerA = AudioPlayer();
  static final AudioPlayer _voicePlayerB = AudioPlayer();
  static bool _usePlayerA = true;
  static final List<Uint8List> _incomingVoiceQueue = [];
  static bool _isPlayingVoiceQueue = false;

  static final AudioRecorder _recorder = AudioRecorder();
  static StreamSubscription<Uint8List>? _micStreamSub;
  static final List<int> _pcmAccumulator = [];
  static bool _wasSpeakingInLastFrame = false;
  static int _silentFramesCount = 0;
  static String? _currentRecordingPath;

  static final Map<String, Uint8List> _wavCache = {};

  static Future<void> init() async {
    try {
      await _sfxPlayer.setReleaseMode(ReleaseMode.stop);
      await _voicePlayerA.setReleaseMode(ReleaseMode.stop);
      await _voicePlayerB.setReleaseMode(ReleaseMode.stop);
    } catch (_) {}
  }

  static Future<void> setSoundEnabled(bool enabled) async {
    soundEnabled = enabled;
  }

  static bool toggleSound() {
    soundEnabled = !soundEnabled;
    return soundEnabled;
  }

  static void playCardDraw() {
    playCardSlide();
  }

  static void playCardSlide() {
    if (!soundEnabled) return;
    HapticFeedback.selectionClick();
    _playAcousticSfx('card_slide', _generateCardSlideWav);
  }

  static void playCardDiscard() {
    if (!soundEnabled) return;
    HapticFeedback.mediumImpact();
    _playAcousticSfx('card_discard', _generateCardDiscardWav);
  }

  static void playCardTap() {
    if (!soundEnabled) return;
    HapticFeedback.lightImpact();
    _playAcousticSfx('card_tap', _generateCardTapWav);
  }

  static void playCountdownBeep({bool urgent = false}) {
    if (!soundEnabled) return;
    HapticFeedback.lightImpact();
    _playAcousticSfx(
      urgent ? 'tick_urgent' : 'tick_normal',
      () => _generateTickWav(urgent: urgent),
    );
  }

  static void playCelebration() {
    if (!soundEnabled) return;
    HapticFeedback.heavyImpact();
    _playAcousticSfx('celebration', _generateCelebrationWav);
  }

  // ===========================================================================
  // 🎙️ PUBG TARZI KESİNTİSİZ CANLI SESLİ SOHBET (CONTINUOUS LIVE VOICE STREAM)
  // ===========================================================================

  /// Mikrofonu sürekli açık (Hands-Free) modda başlatır.
  /// Gürültü engelleme (Noise Suppress), Eko engelleme (Echo Cancel) ve Otomatik Kazanç (Auto Gain) aktiftir.
  static Future<bool> startContinuousVoiceStream({
    required void Function(String? audioBase64, bool isSpeaking) onVoicePacket,
  }) async {
    try {
      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) {
        voiceMicEnabled = false;
        return false;
      }

      await stopContinuousVoiceStream();
      _pcmAccumulator.clear();
      _wasSpeakingInLastFrame = false;
      _silentFramesCount = 0;

      const sampleRate = 16000;
      // Yaklaşık 400ms'lik PCM16 mono ses paketi (16000 * 2 byte * 0.40 = 12800 byte)
      const chunkByteSize = 12800;

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: true,
        ),
      );

      voiceMicEnabled = true;

      _micStreamSub = stream.listen(
        (Uint8List data) {
          if (!voiceMicEnabled) return;
          _pcmAccumulator.addAll(data);

          while (_pcmAccumulator.length >= chunkByteSize) {
            final frameBytes = Uint8List.fromList(
              _pcmAccumulator.sublist(0, chunkByteSize),
            );
            _pcmAccumulator.removeRange(0, chunkByteSize);

            final rms = _computePcm16Rms(frameBytes);
            // Ses aktivite eşiği (VAD): konuşma varsa paketi gönder
            final isVoiceActive = rms > 260.0;

            if (isVoiceActive) {
              _silentFramesCount = 0;
              _wasSpeakingInLastFrame = true;
              final wavBytes = _wrapPcm16MonoAsWav(frameBytes, sampleRate);
              final b64 = base64Encode(wavBytes);
              onVoicePacket(b64, true);
            } else {
              _silentFramesCount++;
              // Konuşma yeni bittiyse son paketi de gönderip konuşma halkasını kapat
              if (_wasSpeakingInLastFrame && _silentFramesCount == 1) {
                final wavBytes = _wrapPcm16MonoAsWav(frameBytes, sampleRate);
                onVoicePacket(base64Encode(wavBytes), true);
              } else if (_wasSpeakingInLastFrame && _silentFramesCount >= 2) {
                _wasSpeakingInLastFrame = false;
                onVoicePacket(null, false);
              }
            }
          }
        },
        onError: (_) {
          voiceMicEnabled = false;
          onVoicePacket(null, false);
        },
      );

      return true;
    } catch (_) {
      voiceMicEnabled = false;
      return false;
    }
  }

  /// Sürekli açık mikrofonu kapatır
  static Future<void> stopContinuousVoiceStream() async {
    voiceMicEnabled = false;
    _pcmAccumulator.clear();
    _wasSpeakingInLastFrame = false;
    _silentFramesCount = 0;
    try {
      await _micStreamSub?.cancel();
      _micStreamSub = null;
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
  }

  /// Hoparlör (Dinle) aç/kapat
  static void setVoiceListenEnabled(bool enabled) {
    voiceListenEnabled = enabled;
    if (!enabled) {
      _incomingVoiceQueue.clear();
      _voicePlayerA.stop();
      _voicePlayerB.stop();
    }
  }

  /// Geriye dönük uyumluluk: Bas-Konuş başlatma
  static Future<bool> startPttRecording() async {
    try {
      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) return false;

      final tempDir = Directory.systemTemp;
      final filePath =
          '${tempDir.path}/ptt_${DateTime.now().millisecondsSinceEpoch}.wav';
      _currentRecordingPath = filePath;

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: true,
        ),
        path: filePath,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Geriye dönük uyumluluk: Bas-Konuş bitirme
  static Future<String?> stopPttRecordingAndGetBase64() async {
    try {
      final path = await _recorder.stop() ?? _currentRecordingPath;
      _currentRecordingPath = null;
      if (path == null) return null;

      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      try {
        await file.delete();
      } catch (_) {}
      if (bytes.length < 300) return null;
      return base64Encode(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Masadaki diğer oyunculardan gelen canlı ses paketlerini kuyruğa alıp kesintisiz çalar
  static Future<void> playIncomingVoiceBase64(String base64Audio) async {
    if (!voiceListenEnabled || base64Audio.isEmpty) return;
    try {
      final bytes = base64Decode(base64Audio);
      if (bytes.length < 100) return;

      // Kuyruk çok biriktiyse gecikmeyi önlemek için eski paketleri atla (Canlı Düşük Gecikme)
      if (_incomingVoiceQueue.length > 4) {
        _incomingVoiceQueue.removeRange(0, _incomingVoiceQueue.length - 2);
      }
      _incomingVoiceQueue.add(bytes);

      if (!_isPlayingVoiceQueue) {
        _processIncomingVoiceQueue();
      }
    } catch (_) {}
  }

  static Future<void> _processIncomingVoiceQueue() async {
    if (_isPlayingVoiceQueue) return;
    _isPlayingVoiceQueue = true;

    try {
      while (_incomingVoiceQueue.isNotEmpty && voiceListenEnabled) {
        final wavBytes = _incomingVoiceQueue.removeAt(0);
        final player = _usePlayerA ? _voicePlayerA : _voicePlayerB;
        _usePlayerA = !_usePlayerA;

        try {
          await player.stop();
          await player.setVolume(1.0);
          await player.play(BytesSource(wavBytes, mimeType: 'audio/wav'));
          // ~370ms paket süresi boyunca çalmasını bekle, bir sonraki pakete pürüzsüz geç
          await Future.delayed(const Duration(milliseconds: 365));
        } catch (_) {
          // BytesSource desteklenmeyen eski cihazlar için yedek geçici dosya ile çal
          try {
            final tempFile = File(
              '${Directory.systemTemp.path}/v_${DateTime.now().microsecondsSinceEpoch}.wav',
            );
            await tempFile.writeAsBytes(wavBytes, flush: true);
            await player.play(DeviceFileSource(tempFile.path));
            await Future.delayed(const Duration(milliseconds: 365));
            tempFile.delete().ignore();
          } catch (_) {}
        }
      }
    } finally {
      _isPlayingVoiceQueue = false;
    }
  }

  static double _computePcm16Rms(Uint8List pcmBytes) {
    final sampleCount = pcmBytes.length ~/ 2;
    if (sampleCount == 0) return 0.0;
    final byteData = ByteData.sublistView(pcmBytes);
    double sumSquares = 0.0;
    for (int i = 0; i < sampleCount; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      sumSquares += sample * sample;
    }
    return math.sqrt(sumSquares / sampleCount);
  }

  static Uint8List _wrapPcm16MonoAsWav(Uint8List pcmBytes, int sampleRate) {
    final dataSize = pcmBytes.length;
    final header = ByteData(44);

    header.setUint8(0, 0x52); // 'R'
    header.setUint8(1, 0x49); // 'I'
    header.setUint8(2, 0x46); // 'F'
    header.setUint8(3, 0x46); // 'F'
    header.setUint32(4, 36 + dataSize, Endian.little);
    header.setUint8(8, 0x57); // 'W'
    header.setUint8(9, 0x41); // 'A'
    header.setUint8(10, 0x56); // 'V'
    header.setUint8(11, 0x45); // 'E'

    header.setUint8(12, 0x66); // 'f'
    header.setUint8(13, 0x6D); // 'm'
    header.setUint8(14, 0x74); // 't'
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM = 1
    header.setUint16(22, 1, Endian.little); // Mono = 1
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);

    header.setUint8(36, 0x64); // 'd'
    header.setUint8(37, 0x61); // 'a'
    header.setUint8(38, 0x74); // 't'
    header.setUint8(39, 0x61); // 'a'
    header.setUint32(40, dataSize, Endian.little);

    final out = Uint8List(44 + dataSize);
    out.setRange(0, 44, header.buffer.asUint8List());
    out.setRange(44, 44 + dataSize, pcmBytes);
    return out;
  }

  static Future<void> _playAcousticSfx(
    String key,
    Uint8List Function() generator,
  ) async {
    try {
      final bytes = _wavCache.putIfAbsent(key, generator);
      await _sfxPlayer.stop();
      await _sfxPlayer.play(BytesSource(bytes, mimeType: 'audio/wav'));
    } catch (_) {}
  }

  static ByteData _createWavHeader(int numSamples, int sampleRate) {
    final int dataSize = numSamples * 2;
    final ByteData buffer = ByteData(44 + dataSize);

    buffer.setUint8(0, 0x52); // R
    buffer.setUint8(1, 0x49); // I
    buffer.setUint8(2, 0x46); // F
    buffer.setUint8(3, 0x46); // F
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    buffer.setUint8(8, 0x57);  // W
    buffer.setUint8(9, 0x41);  // A
    buffer.setUint8(10, 0x56); // V
    buffer.setUint8(11, 0x45); // E

    buffer.setUint8(12, 0x66); // f
    buffer.setUint8(13, 0x6D); // m
    buffer.setUint8(14, 0x74); // t
    buffer.setUint8(15, 0x20); // ' '
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1, Endian.little); // PCM
    buffer.setUint16(22, 1, Endian.little); // Mono
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little);
    buffer.setUint16(32, 2, Endian.little);
    buffer.setUint16(34, 16, Endian.little);

    buffer.setUint8(36, 0x64); // d
    buffer.setUint8(37, 0x61); // a
    buffer.setUint8(38, 0x74); // t
    buffer.setUint8(39, 0x61); // a
    buffer.setUint32(40, dataSize, Endian.little);
    return buffer;
  }

  /// Masada iskambil kağıdının çuha üzerinde kayma (whoosh/hışırtı) sesi
  static Uint8List _generateCardSlideWav() {
    const int sampleRate = 22050;
    const int durationMs = 70;
    final int numSamples = ((sampleRate * durationMs) / 1000).round();
    final ByteData buffer = _createWavHeader(numSamples, sampleRate);
    final rng = math.Random(42);
    double filter = 0;
    for (int i = 0; i < numSamples; i++) {
      final double progress = i / numSamples;
      final double env = math.sin(progress * math.pi) * (1.0 - progress * 0.35);
      final double white = rng.nextDouble() * 2.0 - 1.0;
      filter = (filter * 0.72) + (white * 0.28);
      final double sample = filter * env * 0.38;
      final int pcm16 = (sample * 32767).round().clamp(-32768, 32767);
      buffer.setInt16(44 + i * 2, pcm16, Endian.little);
    }
    return buffer.buffer.asUint8List();
  }

  /// Masaya sert/tok iskambil kağıdı atma ve çuhaya vurma sesi
  static Uint8List _generateCardDiscardWav() {
    const int sampleRate = 22050;
    const int durationMs = 55;
    final int numSamples = ((sampleRate * durationMs) / 1000).round();
    final ByteData buffer = _createWavHeader(numSamples, sampleRate);
    final rng = math.Random(1337);
    double filter = 0;
    for (int i = 0; i < numSamples; i++) {
      final double progress = i / numSamples;
      final double env = math.exp(-progress * 10.0);
      final double noise = rng.nextDouble() * 2.0 - 1.0;
      filter = (filter * 0.55) + (noise * 0.45);
      final double thump = math.sin(2 * math.pi * 150 * (i / sampleRate));
      final double sample = (filter * 0.60 + thump * 0.40) * env * 0.50;
      final int pcm16 = (sample * 32767).round().clamp(-32768, 32767);
      buffer.setInt16(44 + i * 2, pcm16, Endian.little);
    }
    return buffer.buffer.asUint8List();
  }

  /// Kart seçme / dokunma ince tık sesi
  static Uint8List _generateCardTapWav() {
    const int sampleRate = 22050;
    const int durationMs = 20;
    final int numSamples = ((sampleRate * durationMs) / 1000).round();
    final ByteData buffer = _createWavHeader(numSamples, sampleRate);
    final rng = math.Random(99);
    for (int i = 0; i < numSamples; i++) {
      final double progress = i / numSamples;
      final double env = math.exp(-progress * 20.0);
      final double sample = (rng.nextDouble() * 2.0 - 1.0) * env * 0.25;
      final int pcm16 = (sample * 32767).round().clamp(-32768, 32767);
      buffer.setInt16(44 + i * 2, pcm16, Endian.little);
    }
    return buffer.buffer.asUint8List();
  }

  /// Tur sayacı için ahşap/soft metronom tik tak sesi
  static Uint8List _generateTickWav({required bool urgent}) {
    const int sampleRate = 22050;
    final int durationMs = urgent ? 35 : 25;
    final int numSamples = ((sampleRate * durationMs) / 1000).round();
    final ByteData buffer = _createWavHeader(numSamples, sampleRate);
    final double freq = urgent ? 880 : 580;
    for (int i = 0; i < numSamples; i++) {
      final double progress = i / numSamples;
      final double env = math.exp(-progress * 14.0);
      final double tone = math.sin(2 * math.pi * freq * (i / sampleRate));
      final double sample = tone * env * (urgent ? 0.40 : 0.26);
      final int pcm16 = (sample * 32767).round().clamp(-32768, 32767);
      buffer.setInt16(44 + i * 2, pcm16, Endian.little);
    }
    return buffer.buffer.asUint8List();
  }

  /// El açma / oyun kazanma zarif zil akoru
  static Uint8List _generateCelebrationWav() {
    const int sampleRate = 22050;
    const int durationMs = 380;
    final int numSamples = ((sampleRate * durationMs) / 1000).round();
    final ByteData buffer = _createWavHeader(numSamples, sampleRate);
    final freqs = [523.25, 659.25, 783.99, 1046.50]; // C - E - G - C
    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final double progress = i / numSamples;
      double sample = 0;
      for (int n = 0; n < freqs.length; n++) {
        final double noteStart = n * 0.07;
        if (t >= noteStart) {
          final double noteT = t - noteStart;
          final double noteEnv = math.exp(-noteT * 6.5);
          sample += math.sin(2 * math.pi * freqs[n] * noteT) * noteEnv * 0.22;
        }
      }
      final double masterEnv = (1.0 - progress).clamp(0.0, 1.0);
      final int pcm16 = ((sample * masterEnv).clamp(-1.0, 1.0) * 32767).round();
      buffer.setInt16(44 + i * 2, pcm16, Endian.little);
    }
    return buffer.buffer.asUint8List();
  }
}
