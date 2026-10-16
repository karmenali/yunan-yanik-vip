import 'package:flutter/material.dart';

class VipAvatar {
  final String key;
  final String title;
  final String emoji;
  final Color color;

  const VipAvatar({
    required this.key,
    required this.title,
    required this.emoji,
    required this.color,
  });

  static const List<VipAvatar> all = [
    VipAvatar(key: 'lion', title: 'Aslan', emoji: '🦁', color: Color(0xFFD97706)),
    VipAvatar(key: 'king', title: 'Kral', emoji: '👑', color: Color(0xFFEAB308)),
    VipAvatar(key: 'queen', title: 'Kraliçe', emoji: '👸', color: Color(0xFFEC4899)),
    VipAvatar(key: 'wolf', title: 'Kurt', emoji: '🐺', color: Color(0xFF3B82F6)),
    VipAvatar(key: 'boss', title: 'Boss', emoji: '🕶️', color: Color(0xFF10B981)),
    VipAvatar(key: 'joker', title: 'Joker', emoji: '🃏', color: Color(0xFF8B5CF6)),
  ];

  static VipAvatar fromKey(String? key) {
    return all.firstWhere(
      (a) => a.key == key,
      orElse: () => all.first,
    );
  }
}

class UserModel {
  final String id;
  final String username;
  final String role;
  int credits;
  String avatar;
  final bool isBanned;

  UserModel({
    required this.id,
    required this.username,
    required this.role,
    required this.credits,
    required this.avatar,
    this.isBanned = false,
  });

  bool get isAdmin => role == 'admin';

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      role: json['role']?.toString() ?? 'player',
      credits: int.tryParse(json['credits']?.toString() ?? '0') ?? 0,
      avatar: json['avatar']?.toString() ?? 'lion',
      isBanned: json['is_banned'] == true,
    );
  }
}

class CardModel {
  final String id;
  final String suit; // 'S', 'H', 'D', 'C', 'J'
  final int rank; // 1..13, 0 for Joker
  final int deckIndex;
  final bool isPhysicalJoker;

  CardModel({
    required this.id,
    required this.suit,
    required this.rank,
    required this.deckIndex,
    required this.isPhysicalJoker,
  });

  factory CardModel.fromJson(Map<String, dynamic> json) {
    return CardModel(
      id: json['id']?.toString() ?? '',
      suit: json['suit']?.toString() ?? 'S',
      rank: int.tryParse(json['rank']?.toString() ?? '0') ?? 0,
      deckIndex: int.tryParse(json['deckIndex']?.toString() ?? '1') ?? 1,
      isPhysicalJoker: json['isPhysicalJoker'] == true,
    );
  }

  bool isWild(int wildRank) {
    return isPhysicalJoker || (wildRank > 0 && rank == wildRank);
  }

  String get rankLabel {
    if (isPhysicalJoker) return 'JOKER';
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

  String get suitSymbol {
    if (isPhysicalJoker) return '🃏';
    switch (suit) {
      case 'S':
        return '♠';
      case 'H':
        return '♥';
      case 'D':
        return '♦';
      case 'C':
        return '♣';
      default:
        return '♠';
    }
  }

  Color get suitColor {
    if (isPhysicalJoker) return const Color(0xFF7C3AED);
    if (suit == 'H' || suit == 'D') {
      return const Color(0xFFDC2626);
    }
    return const Color(0xFF1E293B);
  }
}

class SeatPlayerModel {
  final String userId;
  final String username;
  final String avatar;
  final int seatIndex;
  final bool isReady;
  final bool isConnected;
  final int totalScore;
  final bool isEliminated;
  final int rebuyCount;
  final bool awaitingRebuyDecision;
  final int cardCount;

  SeatPlayerModel({
    required this.userId,
    required this.username,
    required this.avatar,
    required this.seatIndex,
    required this.isReady,
    required this.isConnected,
    required this.totalScore,
    required this.isEliminated,
    required this.rebuyCount,
    required this.awaitingRebuyDecision,
    required this.cardCount,
  });

  factory SeatPlayerModel.fromJson(Map<String, dynamic> json) {
    return SeatPlayerModel(
      userId: json['userId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? 'lion',
      seatIndex: int.tryParse(json['seatIndex']?.toString() ?? '0') ?? 0,
      isReady: json['isReady'] == true,
      isConnected: json['isConnected'] != false,
      totalScore: int.tryParse(json['totalScore']?.toString() ?? '0') ?? 0,
      isEliminated: json['isEliminated'] == true,
      rebuyCount: int.tryParse(json['rebuyCount']?.toString() ?? '0') ?? 0,
      awaitingRebuyDecision: json['awaitingRebuyDecision'] == true,
      cardCount: int.tryParse(json['cardCount']?.toString() ?? '0') ?? 0,
    );
  }
}

class ShowdownPlayerResultModel {
  final String userId;
  final String username;
  final String avatar;
  final List<List<CardModel>> melds;
  final List<CardModel> unmelded;
  final int roundPenalty;
  final int previousScore;
  final int newTotalScore;
  final bool burnedThisRound;
  final bool canRebuy;
  final int rebuyMultiplier;
  final int rebuyCost;
  final int rebuyTargetScore;

  ShowdownPlayerResultModel({
    required this.userId,
    required this.username,
    required this.avatar,
    required this.melds,
    required this.unmelded,
    required this.roundPenalty,
    required this.previousScore,
    required this.newTotalScore,
    required this.burnedThisRound,
    required this.canRebuy,
    required this.rebuyMultiplier,
    required this.rebuyCost,
    required this.rebuyTargetScore,
  });

  factory ShowdownPlayerResultModel.fromJson(Map<String, dynamic> json) {
    final rawMelds = (json['melds'] as List?) ?? [];
    final parsedMelds = rawMelds.map((m) {
      final list = (m as List?) ?? [];
      return list.map((c) => CardModel.fromJson(Map<String, dynamic>.from(c))).toList();
    }).toList();

    final rawUnmelded = (json['unmelded'] as List?) ?? [];
    final parsedUnmelded = rawUnmelded
        .map((c) => CardModel.fromJson(Map<String, dynamic>.from(c)))
        .toList();

    return ShowdownPlayerResultModel(
      userId: json['userId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? 'lion',
      melds: parsedMelds,
      unmelded: parsedUnmelded,
      roundPenalty: int.tryParse(json['roundPenalty']?.toString() ?? '0') ?? 0,
      previousScore: int.tryParse(json['previousScore']?.toString() ?? '0') ?? 0,
      newTotalScore: int.tryParse(json['newTotalScore']?.toString() ?? '0') ?? 0,
      burnedThisRound: json['burnedThisRound'] == true,
      canRebuy: json['canRebuy'] == true,
      rebuyMultiplier: int.tryParse(json['rebuyMultiplier']?.toString() ?? '1') ?? 1,
      rebuyCost: int.tryParse(json['rebuyCost']?.toString() ?? '0') ?? 0,
      rebuyTargetScore: int.tryParse(json['rebuyTargetScore']?.toString() ?? '0') ?? 0,
    );
  }
}

class TableStateModel {
  final String id;
  final String name;
  final String hostUsername;
  final int minPlayers;
  final int maxPlayers;
  final int entryFee;
  final String status; // 'waiting', 'playing', 'round_summary', 'finished'
  final int pot;
  final int roundNumber;
  final int drawPileCount;
  final CardModel? topDiscardCard;
  final CardModel? indicatorCard;
  final int wildRank;
  final int currentTurnSeat;
  final int dealerSeat;
  final bool hasDrawnThisTurn;
  final int turnRemainingSeconds;
  final List<SeatPlayerModel?> seats;
  final List<CardModel> myHand;
  final bool canFinishNow;
  final String? winningDiscardCardId;
  final int currentHandPenalty;
  final Set<String> meldedCardIds;
  final List<ShowdownPlayerResultModel> lastShowdown;
  final List<Map<String, dynamic>> scoreHistory;
  final Map<String, dynamic>? lastWinnerInfo;

  TableStateModel({
    required this.id,
    required this.name,
    required this.hostUsername,
    required this.minPlayers,
    required this.maxPlayers,
    required this.entryFee,
    required this.status,
    required this.pot,
    required this.roundNumber,
    required this.drawPileCount,
    this.topDiscardCard,
    this.indicatorCard,
    required this.wildRank,
    required this.currentTurnSeat,
    required this.dealerSeat,
    required this.hasDrawnThisTurn,
    required this.turnRemainingSeconds,
    required this.seats,
    required this.myHand,
    required this.canFinishNow,
    this.winningDiscardCardId,
    required this.currentHandPenalty,
    required this.meldedCardIds,
    required this.lastShowdown,
    required this.scoreHistory,
    this.lastWinnerInfo,
  });

  factory TableStateModel.fromJson(Map<String, dynamic> json) {
    final rawSeats = (json['seats'] as List?) ?? [];
    final seats = rawSeats.map((s) {
      if (s == null) return null;
      return SeatPlayerModel.fromJson(Map<String, dynamic>.from(s));
    }).toList();

    final rawHand = (json['myHand'] as List?) ?? [];
    final myHand = rawHand
        .map((c) => CardModel.fromJson(Map<String, dynamic>.from(c)))
        .toList();

    final evalMap = json['myEvaluation'] as Map<String, dynamic>?;
    final meldedList = (evalMap?['meldedCardIds'] as List?) ?? [];

    final rawShowdown = (json['lastShowdown'] as List?) ?? [];
    final showdown = rawShowdown
        .map((x) => ShowdownPlayerResultModel.fromJson(Map<String, dynamic>.from(x)))
        .toList();

    final rawHistory = (json['scoreHistory'] as List?) ?? [];

    return TableStateModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      hostUsername: json['hostUsername']?.toString() ?? '',
      minPlayers: int.tryParse(json['minPlayers']?.toString() ?? '2') ?? 2,
      maxPlayers: int.tryParse(json['maxPlayers']?.toString() ?? '4') ?? 4,
      entryFee: int.tryParse(json['entryFee']?.toString() ?? '100') ?? 100,
      status: json['status']?.toString() ?? 'waiting',
      pot: int.tryParse(json['pot']?.toString() ?? '0') ?? 0,
      roundNumber: int.tryParse(json['roundNumber']?.toString() ?? '0') ?? 0,
      drawPileCount: int.tryParse(json['drawPileCount']?.toString() ?? '0') ?? 0,
      topDiscardCard: json['topDiscardCard'] != null
          ? CardModel.fromJson(Map<String, dynamic>.from(json['topDiscardCard']))
          : null,
      indicatorCard: json['indicatorCard'] != null
          ? CardModel.fromJson(Map<String, dynamic>.from(json['indicatorCard']))
          : null,
      wildRank: int.tryParse(json['wildRank']?.toString() ?? '0') ?? 0,
      currentTurnSeat: int.tryParse(json['currentTurnSeat']?.toString() ?? '0') ?? 0,
      dealerSeat: int.tryParse(json['dealerSeat']?.toString() ?? '0') ?? 0,
      hasDrawnThisTurn: json['hasDrawnThisTurn'] == true,
      turnRemainingSeconds:
          int.tryParse(json['turnRemainingSeconds']?.toString() ?? '30') ?? 30,
      seats: seats,
      myHand: myHand,
      canFinishNow: evalMap?['canFinish'] == true,
      winningDiscardCardId: evalMap?['winningDiscardCardId']?.toString(),
      currentHandPenalty: int.tryParse(evalMap?['penalty']?.toString() ?? '0') ?? 0,
      meldedCardIds: meldedList.map((e) => e.toString()).toSet(),
      lastShowdown: showdown,
      scoreHistory: rawHistory.map((e) => Map<String, dynamic>.from(e)).toList(),
      lastWinnerInfo: json['lastWinnerInfo'] != null
          ? Map<String, dynamic>.from(json['lastWinnerInfo'])
          : null,
    );
  }
}

class LobbyTableModel {
  final String id;
  final String name;
  final String hostUsername;
  final int minPlayers;
  final int maxPlayers;
  final int entryFee;
  final String status;
  final int pot;
  final int roundNumber;
  final int seatedCount;
  final List<Map<String, dynamic>> players;

  LobbyTableModel({
    required this.id,
    required this.name,
    required this.hostUsername,
    required this.minPlayers,
    required this.maxPlayers,
    required this.entryFee,
    required this.status,
    required this.pot,
    required this.roundNumber,
    required this.seatedCount,
    required this.players,
  });

  factory LobbyTableModel.fromJson(Map<String, dynamic> json) {
    final rawPlayers = (json['players'] as List?) ?? [];
    return LobbyTableModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      hostUsername: json['hostUsername']?.toString() ?? '',
      minPlayers: int.tryParse(json['minPlayers']?.toString() ?? '2') ?? 2,
      maxPlayers: int.tryParse(json['maxPlayers']?.toString() ?? '4') ?? 4,
      entryFee: int.tryParse(json['entryFee']?.toString() ?? '100') ?? 100,
      status: json['status']?.toString() ?? 'waiting',
      pot: int.tryParse(json['pot']?.toString() ?? '0') ?? 0,
      roundNumber: int.tryParse(json['roundNumber']?.toString() ?? '0') ?? 0,
      seatedCount: int.tryParse(json['seatedCount']?.toString() ?? '0') ?? 0,
      players: rawPlayers.map((p) => Map<String, dynamic>.from(p)).toList(),
    );
  }
}
