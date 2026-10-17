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

  String _serverUrl = 'http://217.76.62.249:4545'; // Canlı Linux Oyun Sunucusu
  String? _token;
  UserModel? currentUser;
  int emojiCost = 10;

  io.Socket? _socket;
  bool isSocketConnected = false;

  List<LobbyTableModel> lobbyTables = [];
  TableStateModel? activeTable;
  String? lastDrawnCardId;
  List<Map<String, dynamic>> tableChatMessages = [];
  String? activeVoiceSpeakerUsername;

  // Görsel uçan efekt & bildirim akışları
  final StreamController<Map<String, dynamic>> effectStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> toastStreamController =
      StreamController<String>.broadcast();

  String get serverUrl => _serverUrl;
  bool get isLoggedIn => _token != null && currentUser != null;

  Future<void> init() async {
    await SoundFx.init();
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('server_url');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _serverUrl = savedUrl;
    }
    notifyListeners();
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', _serverUrl);
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final uri = Uri.parse('$_serverUrl/api/auth/login');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username.trim(), 'password': password}),
        )
        .timeout(const Duration(seconds: 10));

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Giriş başarısız.');
    }

    _token = data['token'];
    currentUser = UserModel.fromJson(Map<String, dynamic>.from(data['user']));
    emojiCost = int.tryParse(data['emojiCost']?.toString() ?? '10') ?? 10;

    _connectSocket();
    notifyListeners();
  }

  void logout() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _token = null;
    currentUser = null;
    activeTable = null;
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

    _socket!.on('lobby_tables', (data) {
      if (data is List) {
        lobbyTables = data
            .map((e) => LobbyTableModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
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
        tableChatMessages.add(Map<String, dynamic>.from(data));
        if (tableChatMessages.length > 50) {
          tableChatMessages.removeAt(0);
        }
        notifyListeners();
      }
    });

    _socket!.on('table_timer_tick', (data) {
      if (data is Map && activeTable != null) {
        if (data['tableId']?.toString() == activeTable!.id) {
          activeTable!.turnRemainingSeconds =
              int.tryParse(data['turnRemainingSeconds']?.toString() ?? '0') ??
                  activeTable!.turnRemainingSeconds;
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
        final senderId = data['userId']?.toString();
        final audioB64 = data['audioBase64']?.toString();

        activeVoiceSpeakerUsername = speaking ? speakerName : null;

        if (audioB64 != null && audioB64.isNotEmpty) {
          final isMe = senderId == currentUser?.id;
          final seatedOthers = activeTable?.seats
                  .where((s) => s != null && s.userId != currentUser?.id)
                  .length ??
              0;

          // Başka bir oyuncudan geldiyse VEYA kullanıcı masada tek başına mikrofon testi yapıyorsa hoparlörden çal!
          if (!isMe || seatedOthers == 0) {
            activeVoiceSpeakerUsername = speakerName;
            if (isMe && seatedOthers == 0) {
              toastStreamController.add(
                '🔊 Ses Testi: Masada tek olduğunuz için sesiniz size dinletiliyor.',
              );
            }
            Future.delayed(Duration(milliseconds: isMe ? 300 : 10), () {
              SoundFx.playIncomingVoiceBase64(audioB64);
            });
            Future.delayed(const Duration(seconds: 4), () {
              if (activeVoiceSpeakerUsername == speakerName) {
                activeVoiceSpeakerUsername = null;
                notifyListeners();
              }
            });
          } else {
            toastStreamController.add('🎙️ Sesli mesajınız masaya iletildi.');
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
      activeTable = null;
      toastStreamController.add('Masa kapatıldı.');
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
  }) {
    final completer = Completer<String>();
    _socket?.emitWithAck(
      'create_table',
      {
        'name': name,
        'maxPlayers': maxPlayers,
        'entryFee': entryFee,
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

  void declareFinish({String? discardCardId}) {
    if (activeTable == null) return;
    SoundFx.playCelebration();
    _socket?.emit('declare_finish', {
      'tableId': activeTable!.id,
      'discardCardId': discardCardId,
    });
  }

  void reorderHand({List<String>? orderedCardIds}) {
    if (activeTable == null) return;
    _socket?.emit('reorder_hand', {
      'tableId': activeTable!.id,
      'orderedCardIds': orderedCardIds,
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

  /// Bas-Konuş başlat: Mikrofondan gerçek ses kaydına başlar
  Future<bool> startVoicePushToTalk() async {
    if (activeTable == null) return false;
    final started = await SoundFx.startPttRecording();
    if (started) {
      _socket?.emit('voice_ptt', {
        'tableId': activeTable!.id,
        'isSpeaking': true,
      });
    } else {
      toastStreamController.add('🎙️ Mikrofon izni gerekli veya sesli sohbet kapalı.');
    }
    return started;
  }

  /// Bas-Konuş bırak: Kaydedilen sesi masadaki tüm oyunculara gönderir ve hoparlörden çaldırır
  Future<void> stopVoicePushToTalk() async {
    if (activeTable == null) return;
    final audioB64 = await SoundFx.stopPttRecordingAndGetBase64();
    _socket?.emit('voice_ptt', {
      'tableId': activeTable!.id,
      'isSpeaking': false,
      'audioBase64': audioB64,
    });
  }

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
