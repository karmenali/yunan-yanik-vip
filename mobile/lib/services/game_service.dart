import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../models/game_models.dart';
import 'sound_fx.dart';

class GameService extends ChangeNotifier {
  static final GameService instance = GameService._internal();
  GameService._internal();

  static const List<String> _candidateServers = [
    'http://217.76.62.249:4545', // 1. Canlı Bulut Oyun Sunucusu (VPS)
    'http://192.168.1.5:4545', // 2. Yerel Ağ (Wi-Fi) Yedek Sunucu
    'http://10.0.2.2:4545', // 3. Android Emülatör Yedek Sunucu
  ];

  String _serverUrl = 'http://217.76.62.249:4545';
  String? _token;
  UserModel? currentUser;
  int emojiCost = 10;
  String? rejoinedActiveTableId;

  io.Socket? _socket;
  bool isSocketConnected = false;

  List<LobbyTableModel> lobbyTables = [];
  TableStateModel? activeTable;
  String? lastDrawnCardId;
  List<Map<String, dynamic>> tableChatMessages = [];
  String? activeVoiceSpeakerUsername;
  final Set<String> activeSpeakingUserIds = {};
  final Map<String, Timer> _speakerTimers = {};

  bool get isVoiceMicOn => SoundFx.voiceMicEnabled;
  bool get isVoiceListenOn => SoundFx.voiceListenEnabled;

  // Görsel uçan efekt, kart animasyonu & bildirim akışları
  final StreamController<Map<String, dynamic>> effectStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> cardAnimStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> chatStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> toastStreamController =
      StreamController<String>.broadcast();

  String get serverUrl => _serverUrl;
  bool get isLoggedIn => _token != null && currentUser != null;

  Future<void> init() async {
    await SoundFx.init();
    final prefs = await SharedPreferences.getInstance();
    // Eski sürümlerden kalmış geçersiz IP kayıtlarını temizle, aktif sunucuyu otomatik tespit et
    await prefs.remove('server_url');
    await _resolveActiveServerUrl();
    notifyListeners();
  }

  /// Aday sunucuları paralel yoklayarak en hızlı yanıt veren aktif sunucuyu seçer
  Future<String> _resolveActiveServerUrl() async {
    for (final candidate in _candidateServers) {
      try {
        final res = await http
            .get(Uri.parse('$candidate/api/health'))
            .timeout(const Duration(milliseconds: 2800));
        if (res.statusCode == 200) {
          _serverUrl = candidate;
          return _serverUrl;
        }
      } catch (_) {}
    }
    return _serverUrl;
  }

  Future<bool> tryAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString('jwt_token');
      if (savedToken == null || savedToken.isEmpty) return false;

      await _resolveActiveServerUrl();
      final uri = Uri.parse('$_serverUrl/api/auth/me');
      final response = await http
          .get(uri, headers: {'Authorization': 'Bearer $savedToken'})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        await prefs.remove('jwt_token');
        return false;
      }

      final data = jsonDecode(response.body);
      _token = savedToken;
      currentUser = UserModel.fromJson(Map<String, dynamic>.from(data['user']));
      emojiCost = int.tryParse(data['emojiCost']?.toString() ?? '10') ?? 10;
      rejoinedActiveTableId = data['activeTableId']?.toString();

      _connectSocket();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setServerUrl(String url) async {
    String clean = url.trim();
    if (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'http://$clean';
    }
    _serverUrl = clean;
    notifyListeners();
  }

  Future<void> login(String username, String password, {bool rememberMe = true}) async {
    http.Response? response;
    final orderedTargets = <String>[
      _serverUrl,
      ..._candidateServers.where((s) => s != _serverUrl),
    ];

    for (final baseUrl in orderedTargets) {
      try {
        final uri = Uri.parse('$baseUrl/api/auth/login');
        final res = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'username': username.trim(),
                'password': password,
              }),
            )
            .timeout(const Duration(seconds: 5));
        _serverUrl = baseUrl;
        response = res;
        break;
      } catch (_) {
        // Bu uç nokta zaman aşımına uğradıysa sıradaki yedek sunucuyu dene
      }
    }

    if (response == null) {
      throw Exception(
        'Oyun sunucusuna şu anda ulaşılamıyor (Bağlantı zaman aşımı). Lütfen internet bağlantınızı kontrol edip tekrar deneyin.',
      );
    }

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Giriş başarısız.');
    }

    _token = data['token'];
    currentUser = UserModel.fromJson(Map<String, dynamic>.from(data['user']));
    emojiCost = int.tryParse(data['emojiCost']?.toString() ?? '10') ?? 10;
    rejoinedActiveTableId = data['activeTableId']?.toString();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_password');
    if (rememberMe && _token != null) {
      await prefs.setString('saved_username', username.trim());
      await prefs.setString('jwt_token', _token!);
    } else {
      await prefs.remove('saved_username');
      await prefs.remove('jwt_token');
    }

    _connectSocket();
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _token = null;
    currentUser = null;
    activeTable = null;
    rejoinedActiveTableId = null;
    lastDrawnCardId = null;
    lobbyTables = [];
    isSocketConnected = false;
    notifyListeners();
  }

  void _connectSocket() {
    _socket?.disconnect();
    _socket?.dispose();

    _socket = io.io(
      _serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setAuth({'token': _token})
          .enableAutoConnect()
          .enableReconnection()
          .build(),
    );

    _socket!.onConnect((_) {
      isSocketConnected = true;
      _socket!.emit('get_lobby_tables');
      if (activeTable != null) {
        _socket!.emit('join_table', {'tableId': activeTable!.id});
      }
      notifyListeners();
    });

    _socket!.onDisconnect((_) {
      isSocketConnected = false;
      notifyListeners();
    });

    _socket!.on('active_table_rejoined', (data) {
      if (data is Map && data['tableId'] != null) {
        rejoinedActiveTableId = data['tableId'].toString();
        notifyListeners();
      }
    });

    _socket!.on('lobby_tables', (data) {
      if (data is List) {
        lobbyTables = data
            .map((e) => LobbyTableModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        // Kullanıcının oturduğu aktif masa varsa tespit et
        if (currentUser != null) {
          String? foundId;
          for (final t in lobbyTables) {
            if (t.players.any((p) => p['userId']?.toString() == currentUser!.id)) {
              foundId = t.id;
              break;
            }
          }
          rejoinedActiveTableId = foundId;
        }
        notifyListeners();
      }
    });

    _socket!.on('table_state', (data) {
      if (data is Map) {
        final prevIds = activeTable?.myHand.map((c) => c.id).toSet() ?? <String>{};
        final nextTable = TableStateModel.fromJson(Map<String, dynamic>.from(data));

        // Yeni çekilen 11. kağıdı tespit et (vurgulama ve akıcı animasyon için)
        if (nextTable.myHand.length == 11 && prevIds.length == 10) {
          for (final c in nextTable.myHand) {
            if (!prevIds.contains(c.id)) {
              lastDrawnCardId = c.id;
              SoundFx.playCardDraw();
              break;
            }
          }
        } else if (nextTable.myHand.length <= 10) {
          lastDrawnCardId = null;
        }

        activeTable = nextTable;
        notifyListeners();
      }
    });

    _socket!.on('round_started', (data) {
      if (data is Map) {
        SoundFx.playCardDraw();
        cardAnimStreamController.add({
          'type': 'round_started',
          ...Map<String, dynamic>.from(data),
        });
      }
    });

    _socket!.on('player_drew_card', (data) {
      if (data is Map) {
        cardAnimStreamController.add({
          'type': 'draw',
          ...Map<String, dynamic>.from(data),
        });
      }
    });

    _socket!.on('card_discarded', (data) {
      if (data is Map) {
        SoundFx.playCardDiscard();
        cardAnimStreamController.add({
          'type': 'discard',
          ...Map<String, dynamic>.from(data),
        });
      }
    });

    _socket!.on('false_declare_penalty', (data) {
      if (data is Map) {
        final msg = data['message']?.toString() ?? 'Hatalı el açıldı!';
        toastStreamController.add('🚨 $msg');
        cardAnimStreamController.add({
          'type': 'false_declare',
          ...Map<String, dynamic>.from(data),
        });
      }
    });

    _socket!.on('round_ended', (data) {
      if (data is Map) {
        SoundFx.playCelebration();
        cardAnimStreamController.add({
          'type': 'round_ended',
          ...Map<String, dynamic>.from(data),
        });
      }
    });

    _socket!.on('balance_updated', (data) {
      if (data is Map && currentUser != null) {
        currentUser!.credits =
            int.tryParse(data['credits']?.toString() ?? '${currentUser!.credits}') ??
                currentUser!.credits;
        notifyListeners();
      }
    });

    _socket!.on('user_credit_sync', (data) {
      if (data is Map && currentUser != null && data['userId'] == currentUser!.id) {
        currentUser!.credits =
            int.tryParse(data['credits']?.toString() ?? '${currentUser!.credits}') ??
                currentUser!.credits;
        notifyListeners();
      }
    });

    _socket!.on('emoji_cost_updated', (data) {
      if (data is Map) {
        emojiCost = int.tryParse(data['emojiCost']?.toString() ?? '10') ?? 10;
        notifyListeners();
      }
    });

    _socket!.on('interactive_effect', (data) {
      if (data is Map) {
        effectStreamController.add(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('chat_message', (data) {
      if (data is Map) {
        final msg = Map<String, dynamic>.from(data);
        tableChatMessages.add(msg);
        if (tableChatMessages.length > 50) {
          tableChatMessages.removeAt(0);
        }
        chatStreamController.add(msg);
        notifyListeners();
      }
    });

    _socket!.on('table_timer_tick', (data) {
      if (data is Map && activeTable != null) {
        if (data['tableId']?.toString() == activeTable!.id) {
          activeTable!.turnRemainingSeconds =
              int.tryParse(data['turnRemainingSeconds']?.toString() ?? '0') ??
                  activeTable!.turnRemainingSeconds;
          activeTable!.turnDurationSeconds =
              int.tryParse(data['turnDurationSeconds']?.toString() ?? '30') ??
                  activeTable!.turnDurationSeconds;
          activeTable!.matchElapsedSeconds =
              int.tryParse(data['matchElapsedSeconds']?.toString() ?? '0') ??
                  activeTable!.matchElapsedSeconds;
          notifyListeners();
        }
      }
    });

    _socket!.on('voice_ptt_stream', (data) {
      if (data is Map) {
        final speaking = data['isSpeaking'] == true;
        final speakerName = data['username']?.toString();
        final senderId = data['userId']?.toString() ?? '';
        final audioB64 = data['audioBase64']?.toString();

        if (senderId.isNotEmpty) {
          _speakerTimers[senderId]?.cancel();
          if (speaking) {
            activeSpeakingUserIds.add(senderId);
            activeVoiceSpeakerUsername = speakerName;
            _speakerTimers[senderId] = Timer(
              const Duration(milliseconds: 1400),
              () {
                activeSpeakingUserIds.remove(senderId);
                if (activeVoiceSpeakerUsername == speakerName) {
                  activeVoiceSpeakerUsername = null;
                }
                notifyListeners();
              },
            );
          } else {
            activeSpeakingUserIds.remove(senderId);
            if (activeVoiceSpeakerUsername == speakerName) {
              activeVoiceSpeakerUsername = null;
            }
          }
        }

        if (audioB64 != null && audioB64.isNotEmpty) {
          final isMe = senderId == currentUser?.id;
          // Diğer oyuncuların sesini anında oynat
          if (!isMe) {
            SoundFx.playIncomingVoiceBase64(audioB64);
          }
        }

        notifyListeners();
      }
    });

    _socket!.on('auto_play_notice', (data) {
      if (data is Map) {
        final uname = data['username'] ?? 'Oyuncu';
        toastStreamController.add('⏱️ $uname süresini doldurduğu için otomatik oynandı.');
      }
    });

    _socket!.on('player_rebought', (data) {
      if (data is Map) {
        final uname = data['username'] ?? 'Oyuncu';
        final mult = data['multiplier'] ?? 1;
        final score = data['newScore'] ?? 0;
        toastStreamController.add(
          '🔥 $uname ${mult}x kredi ödeyerek $score puanla oyuna geri döndü!',
        );
      }
    });

    _socket!.on('table_closed', (data) {
      stopContinuousMic();
      activeTable = null;
      final msg = (data is Map && data['message'] != null)
          ? data['message'].toString()
          : 'Masa kapatıldı.';
      toastStreamController.add(msg);
      notifyListeners();
    });

    _socket!.on('error_msg', (msg) {
      if (msg != null) {
        toastStreamController.add(msg.toString());
      }
    });
  }

  Future<void> updateAvatar(String avatarKey) async {
    final uri = Uri.parse('$_serverUrl/api/profile/avatar');
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({'avatar': avatarKey}),
    );
    if (res.statusCode == 200 && currentUser != null) {
      currentUser!.avatar = avatarKey;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> fetchMyHistory() async {
    final uri = Uri.parse('$_serverUrl/api/profile/history');
    final res = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $_token'},
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Geçmiş verileri alınamadı.');
    }
    return Map<String, dynamic>.from(data);
  }

  // ==========================================
  // 🃏 MASA & OYUN AKSİYONLARI
  // ==========================================

  Future<String> createTable({
    required String name,
    required int maxPlayers,
    required int entryFee,
    bool isAssisted = true,
  }) {
    final completer = Completer<String>();
    _socket?.emitWithAck(
      'create_table',
      {
        'name': name,
        'maxPlayers': maxPlayers,
        'entryFee': entryFee,
        'isAssisted': isAssisted,
      },
      ack: (res) {
        if (res is Map && res['ok'] == true) {
          completer.complete(res['tableId'].toString());
        } else {
          completer.completeError(res?['error'] ?? 'Masa kurulamadı.');
        }
      },
    );
    return completer.future;
  }

  void enterTable(String tableId) {
    tableChatMessages.clear();
    lastDrawnCardId = null;
    _socket?.emit('join_table', {'tableId': tableId});
  }

  void leaveCurrentTable() {
    stopContinuousMic();
    if (activeTable != null) {
      _socket?.emit('leave_table', {'tableId': activeTable!.id});
      activeTable = null;
      lastDrawnCardId = null;
      tableChatMessages.clear();
      notifyListeners();
    }
  }

  void sitAtSeat(int seatIndex) {
    if (activeTable == null) return;
    _socket?.emit('sit_seat', {
      'tableId': activeTable!.id,
      'seatIndex': seatIndex,
    });
  }

  void standUp() {
    if (activeTable == null) return;
    _socket?.emit('stand_up', {'tableId': activeTable!.id});
  }

  void toggleReady() {
    if (activeTable == null) return;
    _socket?.emit('toggle_ready', {'tableId': activeTable!.id});
  }

  void drawCard() {
    if (activeTable == null) return;
    _socket?.emit('draw_card', {'tableId': activeTable!.id});
  }

  void discardCard(String cardId) {
    if (activeTable == null) return;
    SoundFx.playCardDiscard();
    _socket?.emit('discard_card', {
      'tableId': activeTable!.id,
      'cardId': cardId,
    });
  }

  void declareFinish({String? discardCardId, List<List<String>>? rowCardIds}) {
    if (activeTable == null) return;
    SoundFx.playCelebration();
    _socket?.emit('declare_finish', {
      'tableId': activeTable!.id,
      'discardCardId': discardCardId,
      'rowCardIds': rowCardIds,
    });
  }

  void reorderHand({
    List<String>? orderedCardIds,
    List<List<String>>? rowCardIds,
  }) {
    if (activeTable == null) return;
    _socket?.emit('reorder_hand', {
      'tableId': activeTable!.id,
      'orderedCardIds': orderedCardIds,
      'rowCardIds': rowCardIds,
    });
  }

  void rebuyIntoMatch() {
    if (activeTable == null) return;
    _socket?.emit('rebuy', {'tableId': activeTable!.id});
  }

  void sendChatMessage(String text) {
    if (activeTable == null || text.trim().isEmpty) return;
    _socket?.emit('send_chat', {
      'tableId': activeTable!.id,
      'message': text.trim(),
    });
  }

  void sendInteractiveEffect(String targetUserId, String effectKey) {
    if (activeTable == null) return;
    _socket?.emit('send_effect', {
      'tableId': activeTable!.id,
      'targetUserId': targetUserId,
      'effectKey': effectKey,
    });
  }

  /// 🔊 PUBG Tarzı Hoparlör (Dinle: Açık / Kapalı)
  void toggleVoiceListen() {
    final nextState = !SoundFx.voiceListenEnabled;
    SoundFx.setVoiceListenEnabled(nextState);
    if (!nextState && SoundFx.voiceMicEnabled) {
      // Hoparlör tamamen kapatılırsa mikrofonu da kapat
      stopContinuousMic();
    }
    notifyListeners();
  }

  /// 🎙️ PUBG Tarzı Sürekli Açık Mikrofon (Konuş: Açık / Kapalı)
  Future<bool> toggleContinuousMic() async {
    if (activeTable == null) return false;
    if (SoundFx.voiceMicEnabled) {
      await stopContinuousMic();
      return false;
    }

    // Mikrofon açıldığında hoparlörü de otomatik aç
    if (!SoundFx.voiceListenEnabled) {
      SoundFx.setVoiceListenEnabled(true);
    }

    final started = await SoundFx.startContinuousVoiceStream(
      onVoicePacket: (audioBase64, isSpeaking) {
        if (activeTable == null) return;
        _socket?.emit('voice_ptt', {
          'tableId': activeTable!.id,
          'isSpeaking': isSpeaking,
          'audioBase64': audioBase64,
        });
      },
    );

    if (!started) {
      toastStreamController.add('🎙️ Mikrofon izni gerekli! Lütfen mikrofon iznini onaylayın.');
    }
    notifyListeners();
    return started;
  }

  Future<void> stopContinuousMic() async {
    final wasOn = SoundFx.voiceMicEnabled;
    await SoundFx.stopContinuousVoiceStream();
    if (wasOn && activeTable != null) {
      _socket?.emit('voice_ptt', {
        'tableId': activeTable!.id,
        'isSpeaking': false,
      });
    }
    if (currentUser != null) {
      activeSpeakingUserIds.remove(currentUser!.id);
    }
    notifyListeners();
  }

  Future<bool> startVoicePushToTalk() => toggleContinuousMic();
  Future<void> stopVoicePushToTalk() => stopContinuousMic();

  // ==========================================
  // 👑 ADMİN PANELİ API ÇAĞRILARI
  // ==========================================

  Future<Map<String, dynamic>> fetchAdminDashboard() async {
    final uri = Uri.parse('$_serverUrl/api/admin/dashboard');
    final res = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $_token'},
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Yönetim verileri alınamadı.');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<void> adminCreateUser({
    required String username,
    required String password,
    required int initialCredits,
    required String avatar,
    String role = 'player',
  }) async {
    final uri = Uri.parse('$_serverUrl/api/admin/users');
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({
        'username': username,
        'password': password,
        'initialCredits': initialCredits,
        'avatar': avatar,
        'role': role,
      }),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Kullanıcı oluşturulamadı.');
    }
  }

  Future<void> adminAdjustCredits({
    required String userId,
    required int amount,
    required String description,
  }) async {
    final uri = Uri.parse('$_serverUrl/api/admin/users/$userId/credits');
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({
        'amount': amount,
        'description': description,
      }),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Kredi işlemi başarısız.');
    }
  }

  Future<void> adminResetPassword(String userId, String newPassword) async {
    final uri = Uri.parse('$_serverUrl/api/admin/users/$userId/password');
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({'newPassword': newPassword}),
    );
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['error'] ?? 'Şifre güncellenemedi.');
    }
  }

  Future<void> adminSetBan(String userId, bool isBanned) async {
    final uri = Uri.parse('$_serverUrl/api/admin/users/$userId/ban');
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({'isBanned': isBanned}),
    );
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['error'] ?? 'İşlem başarısız.');
    }
  }

  Future<void> adminSetEmojiCost(int cost) async {
    final uri = Uri.parse('$_serverUrl/api/admin/settings/emoji-cost');
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({'emojiCost': cost}),
    );
    if (res.statusCode != 200) {
      throw Exception('Emoji ücreti güncellenemedi.');
    }
  }

  Future<void> adminCloseTable(String tableId) async {
    final uri = Uri.parse('$_serverUrl/api/admin/tables/$tableId');
    await http.delete(
      uri,
      headers: {'Authorization': 'Bearer $_token'},
    );
  }
}
