import { Server, Socket } from 'socket.io';
import { v4 as uuidv4 } from 'uuid';
import {
  Card,
  dealRoundHands,
  evaluateHandOptimal,
  findWinningDiscard,
  isWildCard,
  selectBestAutoDiscard,
} from './gameEngine';
import { db } from '../db';

export interface SeatPlayer {
  userId: string;
  username: string;
  avatar: string;
  seatIndex: number;
  isReady: boolean;
  isConnected: boolean;
  totalScore: number;
  isEliminated: boolean;
  rebuyCount: number; // Kaç kez yandı ve geri döndü (0 -> ilk yanışta 1x öder, 1 -> 2x öder, 2 -> 3x öder)
  awaitingRebuyDecision: boolean;
  hand: Card[];
}

export interface RoundScoreSnapshot {
  roundNumber: number;
  scoresByUser: Record<string, number>; // O el alınan ceza puanı
  totalsByUser: Record<string, number>; // O el sonu toplam puan
  finisherUserId: string | null;
}

export interface ShowdownPlayerResult {
  userId: string;
  username: string;
  avatar: string;
  melds: Card[][];
  unmelded: Card[];
  roundPenalty: number;
  previousScore: number;
  newTotalScore: number;
  burnedThisRound: boolean;
  canRebuy: boolean;
  rebuyMultiplier: number;
  rebuyCost: number;
  rebuyTargetScore: number;
}

export interface GameTable {
  id: string;
  name: string;
  hostUserId: string;
  hostUsername: string;
  minPlayers: number;
  maxPlayers: number;
  entryFee: number;
  status: 'waiting' | 'playing' | 'round_summary' | 'finished';
  pot: number;
  roundNumber: number;
  seats: (SeatPlayer | null)[];
  spectators: Set<string>;
  // Aktif el durumu
  drawPile: Card[];
  discardPile: Card[];
  indicatorCard: Card | null;
  wildRank: number;
  currentTurnSeat: number;
  dealerSeat: number;
  hasDrawnThisTurn: boolean;
  turnDeadline: number;
  turnTimer?: NodeJS.Timeout;
  phaseTimer?: NodeJS.Timeout;
  activePlayersAtRoundStart: number;
  lastShowdown: ShowdownPlayerResult[] | null;
  scoreHistory: RoundScoreSnapshot[];
  lastWinnerInfo: {
    userId: string;
    username: string;
    avatar: string;
    totalPot: number;
    houseRake: number;
    prizeWon: number;
  } | null;
}

export const INTERACTIVE_EFFECTS: Record<string, { name: string; icon: string }> = {
  bomb: { name: 'Bomba', icon: '💣' },
  tomato: { name: 'Domates', icon: '🍅' },
  rose: { name: 'Gül', icon: '🌹' },
  clap: { name: 'Alkış', icon: '👏' },
  laugh: { name: 'Kahkaha', icon: '😂' },
  cry: { name: 'Ağlama', icon: '😭' },
};

export class TableManager {
  private io: Server;
  private tables: Map<string, GameTable> = new Map();
  private userSockets: Map<string, string> = new Map(); // userId -> socketId

  constructor(io: Server) {
    this.io = io;
    this.seedDefaultTables();
  }

  private seedDefaultTables() {
    this.createTable('VIP Salon #1 (2 Kişilik)', 'system', 'Kulüp', 2, 100);
    this.createTable('Atina Meydanı (4 Kişilik)', 'system', 'Kulüp', 4, 250);
    this.createTable('Büyük Masa (6 Kişilik)', 'system', 'Kulüp', 6, 500);
  }

  registerUserSocket(userId: string, socketId: string) {
    this.userSockets.set(userId, socketId);
    // Oyuncu bir masada oturuyorsa bağlantı durumunu güncelle
    for (const table of this.tables.values()) {
      let updated = false;
      for (const seat of table.seats) {
        if (seat && seat.userId === userId) {
          seat.isConnected = true;
          updated = true;
        }
      }
      if (updated) {
        this.broadcastTableState(table.id);
      }
    }
  }

  private cleanupTableIfEmpty(tableId: string): boolean {
    const table = this.tables.get(tableId);
    if (!table) return false;
    // Kulübün 3 varsayılan salon masası her zaman açık kalır, oyuncuların kurduğu masalar boşalınca silinir
    if (table.hostUserId === 'system') return false;

    const hasSeated = table.seats.some((s) => s !== null && s.isConnected);
    const hasSpectators = table.spectators.size > 0;

    if (!hasSeated && !hasSpectators) {
      if (table.turnTimer) clearTimeout(table.turnTimer);
      if (table.phaseTimer) clearTimeout(table.phaseTimer);
      this.tables.delete(tableId);
      return true;
    }
    return false;
  }

  handleDisconnect(userId: string) {
    this.userSockets.delete(userId);
    for (const table of Array.from(this.tables.values())) {
      table.spectators.delete(userId);
      let updated = false;
      for (let i = 0; i < table.seats.length; i++) {
        const seat = table.seats[i];
        if (seat && seat.userId === userId) {
          if (table.status === 'waiting' || table.status === 'finished') {
            table.seats[i] = null;
          } else {
            seat.isConnected = false;
          }
          updated = true;
        }
      }
      const deleted = this.cleanupTableIfEmpty(table.id);
      if (updated || deleted) {
        if (!deleted) this.broadcastTableState(table.id);
        this.broadcastLobbyTables();
      }
    }
  }

  createTable(
    name: string,
    hostUserId: string,
    hostUsername: string,
    maxPlayers: number,
    entryFee: number
  ): GameTable {
    const clampedMax = Math.min(6, Math.max(2, Math.round(maxPlayers)));
    const cleanFee = Math.max(10, Math.round(entryFee));
    const id = uuidv4().slice(0, 8);

    const table: GameTable = {
      id,
      name: name.trim() || `Masa #${id.slice(0, 4)}`,
      hostUserId,
      hostUsername,
      minPlayers: 2,
      maxPlayers: clampedMax,
      entryFee: cleanFee,
      status: 'waiting',
      pot: 0,
      roundNumber: 0,
      seats: Array(clampedMax).fill(null),
      spectators: new Set(),
      drawPile: [],
      discardPile: [],
      indicatorCard: null,
      wildRank: 0,
      currentTurnSeat: 0,
      dealerSeat: 0,
      hasDrawnThisTurn: false,
      turnDeadline: 0,
      activePlayersAtRoundStart: 0,
      lastShowdown: null,
      scoreHistory: [],
      lastWinnerInfo: null,
    };

    this.tables.set(id, table);
    this.broadcastLobbyTables();
    return table;
  }

  closeTableByAdmin(tableId: string): boolean {
    const table = this.tables.get(tableId);
    if (!table) return false;
    if (table.turnTimer) clearTimeout(table.turnTimer);
    if (table.phaseTimer) clearTimeout(table.phaseTimer);
    this.io.to(`table:${tableId}`).emit('table_closed', {
      message: 'Bu masa yönetici tarafından kapatıldı.',
    });
    this.tables.delete(tableId);
    this.broadcastLobbyTables();
    return true;
  }

  getLobbyTablesSummary() {
    return Array.from(this.tables.values()).map((t) => ({
      id: t.id,
      name: t.name,
      hostUsername: t.hostUsername,
      minPlayers: t.minPlayers,
      maxPlayers: t.maxPlayers,
      entryFee: t.entryFee,
      status: t.status,
      pot: t.pot,
      roundNumber: t.roundNumber,
      seatedCount: t.seats.filter((s) => s !== null).length,
      players: t.seats
        .filter((s): s is SeatPlayer => s !== null)
        .map((s) => ({
          userId: s.userId,
          username: s.username,
          avatar: s.avatar,
          seatIndex: s.seatIndex,
        })),
    }));
  }

  broadcastLobbyTables() {
    this.io.emit('lobby_tables', this.getLobbyTablesSummary());
  }

  joinTableRoom(socket: Socket, userId: string, tableId: string) {
    const table = this.tables.get(tableId);
    if (!table) {
      socket.emit('error_msg', 'Masa bulunamadı.');
      return;
    }
    socket.join(`table:${tableId}`);
    table.spectators.add(userId);
    this.sendTableStateToUser(table, userId);
  }

  leaveTableRoom(socket: Socket, userId: string, tableId: string) {
    const table = this.tables.get(tableId);
    if (!table) return;

    socket.leave(`table:${tableId}`);
    table.spectators.delete(userId);

    // Eğer oyun henüz başlamadıysa koltuktan da kaldır
    if (table.status === 'waiting' || table.status === 'finished') {
      for (let i = 0; i < table.seats.length; i++) {
        if (table.seats[i]?.userId === userId) {
          table.seats[i] = null;
        }
      }
    }

    const deleted = this.cleanupTableIfEmpty(tableId);
    if (!deleted) {
      this.broadcastTableState(tableId);
    }
    this.broadcastLobbyTables();
  }

  async sitAtSeat(userId: string, tableId: string, seatIndex: number): Promise<void> {
    const table = this.tables.get(tableId);
    if (!table) throw new Error('Masa bulunamadı.');
    if (table.status !== 'waiting' && table.status !== 'finished') {
      throw new Error('Oyun devam ederken koltuğa oturulamaz.');
    }
    if (seatIndex < 0 || seatIndex >= table.maxPlayers) {
      throw new Error('Geçersiz koltuk numarası.');
    }
    if (table.seats[seatIndex] !== null) {
      throw new Error('Bu koltuk dolu.');
    }

    const user = await db.getUserById(userId);
    if (!user) throw new Error('Kullanıcı bulunamadı.');
    if (user.is_banned) throw new Error('Hesabınız askıya alınmıştır.');
    if (user.credits < table.entryFee) {
      throw new Error(`Bu masaya oturmak için en az ${table.entryFee} kredi gereklidir.`);
    }

    // Oyuncu aynı masada başka koltukta oturuyorsa oradan kaldır
    for (let i = 0; i < table.seats.length; i++) {
      if (table.seats[i]?.userId === userId) {
        table.seats[i] = null;
      }
    }

    table.seats[seatIndex] = {
      userId: user.id,
      username: user.username,
      avatar: user.avatar,
      seatIndex,
      isReady: false,
      isConnected: true,
      totalScore: 0,
      isEliminated: false,
      rebuyCount: 0,
      awaitingRebuyDecision: false,
      hand: [],
    };

    if (table.status === 'finished') {
      table.status = 'waiting';
      table.lastWinnerInfo = null;
      table.lastShowdown = null;
      for (const s of table.seats) {
        if (s) {
          s.isEliminated = false;
          s.totalScore = 0;
          s.hand = [];
        }
      }
    }

    this.broadcastTableState(tableId);
    this.broadcastLobbyTables();
  }

  standUpFromSeat(userId: string, tableId: string) {
    const table = this.tables.get(tableId);
    if (!table) return;
    if (table.status !== 'waiting' && table.status !== 'finished') {
      throw new Error('Aktif oyun sırasında koltuktan kalkılamaz.');
    }
    for (let i = 0; i < table.seats.length; i++) {
      if (table.seats[i]?.userId === userId) {
        table.seats[i] = null;
      }
    }
    this.broadcastTableState(tableId);
    this.broadcastLobbyTables();
  }

  async toggleReady(userId: string, tableId: string): Promise<void> {
    const table = this.tables.get(tableId);
    if (!table) throw new Error('Masa bulunamadı.');
    if (table.status !== 'waiting' && table.status !== 'finished') {
      throw new Error('Oyun zaten başladı.');
    }

    const seat = table.seats.find((s) => s?.userId === userId);
    if (!seat) throw new Error('Önce bir koltuğa oturmalısınız.');

    const user = await db.getUserById(userId);
    if (!user || user.credits < table.entryFee) {
      throw new Error(`Oyuna başlamak için ${table.entryFee} kredi gereklidir.`);
    }

    if (table.status === 'finished') {
      table.status = 'waiting';
      table.lastWinnerInfo = null;
      table.lastShowdown = null;
      for (const s of table.seats) {
        if (s) {
          s.isEliminated = false;
          s.totalScore = 0;
          s.hand = [];
        }
      }
    }

    seat.isReady = !seat.isReady;
    this.broadcastTableState(tableId);

    // Masada en az 2 oyuncu oturuyor ve oturan HERKES Hazır dediyse oyunu başlat!
    const seatedPlayers = table.seats.filter((s): s is SeatPlayer => s !== null);
    if (seatedPlayers.length >= table.minPlayers && seatedPlayers.every((s) => s.isReady)) {
      await this.startMatch(table);
    }
  }

  private async startMatch(table: GameTable): Promise<void> {
    const seatedPlayers = table.seats.filter((s): s is SeatPlayer => s !== null);
    if (seatedPlayers.length < 2) return;

    // Her oyuncudan 1x masa giriş kredisini tahsil et ve Pot'a ekle
    let collectedPot = 0;
    const chargedUsers: string[] = [];

    try {
      for (const p of seatedPlayers) {
        const newBal = await db.adjustCredits(
          p.userId,
          -table.entryFee,
          'table_entry',
          `${table.name} masası oyun giriş ücreti (1x)`
        );
        chargedUsers.push(p.userId);
        collectedPot += table.entryFee;
        this.emitBalanceUpdate(p.userId, newBal);
      }
    } catch (err: any) {
      // Bir oyuncunun bakiyesi yetmediyse diğerlerine iade et
      for (const uid of chargedUsers) {
        const bal = await db.adjustCredits(
          uid,
          table.entryFee,
          'table_refund',
          `${table.name} masa başlangıç iptali iadesi`
        );
        this.emitBalanceUpdate(uid, bal);
      }
      for (const p of seatedPlayers) p.isReady = false;
      this.io.to(`table:${table.id}`).emit('error_msg', `Oyun başlatılamadı: ${err.message}`);
      this.broadcastTableState(table.id);
      return;
    }

    table.status = 'playing';
    table.pot = collectedPot;
    table.roundNumber = 0;
    table.scoreHistory = [];
    table.lastWinnerInfo = null;
    table.lastShowdown = null;

    for (const p of seatedPlayers) {
      p.totalScore = 0;
      p.isEliminated = false;
      p.rebuyCount = 0;
      p.awaitingRebuyDecision = false;
      p.hand = [];
    }

    // İlk dağıtan rastgele bir koltuk
    table.dealerSeat = seatedPlayers[Math.floor(Math.random() * seatedPlayers.length)].seatIndex;

    this.broadcastLobbyTables();
    this.startNewRound(table);
  }

  private startNewRound(table: GameTable) {
    if (table.turnTimer) clearTimeout(table.turnTimer);
    if (table.phaseTimer) clearTimeout(table.phaseTimer);

    const activePlayers = table.seats.filter(
      (s): s is SeatPlayer => s !== null && !s.isEliminated
    );

    if (activePlayers.length < 2) {
      this.concludeMatch(table);
      return;
    }

    table.status = 'playing';
    table.roundNumber += 1;
    table.activePlayersAtRoundStart = activePlayers.length;
    table.lastShowdown = null;
    table.discardPile = [];

    const activeIds = activePlayers.map((p) => p.userId);
    const { hands, drawPile, indicatorCard, wildRank } = dealRoundHands(activeIds);

    for (const seat of table.seats) {
      if (!seat) continue;
      seat.awaitingRebuyDecision = false;
      if (!seat.isEliminated) {
        const dealt = hands[seat.userId] || [];
        // Oyuncuya başlangıçta düzenli bir el sun
        seat.hand = evaluateHandOptimal(dealt, wildRank).orderedCards;
      } else {
        seat.hand = [];
      }
    }

    table.drawPile = drawPile;
    table.indicatorCard = indicatorCard;
    table.wildRank = wildRank;

    // Dağıtandan bir sonraki aktif oyuncu başlar
    table.dealerSeat = this.getNextActiveSeatIndex(table, table.dealerSeat);
    table.currentTurnSeat = this.getNextActiveSeatIndex(table, table.dealerSeat);
    table.hasDrawnThisTurn = false;

    this.io.to(`table:${table.id}`).emit('round_started', {
      roundNumber: table.roundNumber,
      indicatorCard: table.indicatorCard,
      wildRank: table.wildRank,
    });

    this.startTurnTimer(table);
    this.broadcastTableState(table.id);
  }

  private getNextActiveSeatIndex(table: GameTable, fromSeat: number): number {
    const max = table.seats.length;
    for (let offset = 1; offset <= max; offset++) {
      const idx = (fromSeat + offset) % max;
      const s = table.seats[idx];
      if (s && !s.isEliminated) {
        return idx;
      }
    }
    return fromSeat;
  }

  private startTurnTimer(table: GameTable) {
    if (table.turnTimer) clearTimeout(table.turnTimer);
    table.turnDeadline = Date.now() + 30000; // 30 saniye hamle süresi

    table.turnTimer = setTimeout(() => {
      this.handleTurnTimeout(table);
    }, 30000);
  }

  /**
   * 30 saniye dolduğunda:
   * 1. Oyuncu henüz kağıt çekmediyse ortadan 1 kağıt çeker
   * 2. Per olmayan ve Joker olmayan en büyük gereksiz kağıdı otomatik atar
   */
  private handleTurnTimeout(table: GameTable) {
    if (table.status !== 'playing') return;
    const currentSeat = table.seats[table.currentTurnSeat];
    if (!currentSeat || currentSeat.isEliminated) return;

    // 1. Kağıt çekmediyse ortadan çek
    if (!table.hasDrawnThisTurn && table.drawPile.length > 0) {
      const drawn = table.drawPile.shift()!;
      currentSeat.hand.push(drawn);
      table.hasDrawnThisTurn = true;
    }

    // 2. En büyük gereksiz (per olmayan ve joker olmayan) kağıdı seç ve at
    const cardToDiscard = selectBestAutoDiscard(currentSeat.hand, table.wildRank);
    this.io.to(`table:${table.id}`).emit('auto_play_notice', {
      userId: currentSeat.userId,
      username: currentSeat.username,
      discardedCard: cardToDiscard,
    });

    this.executeDiscard(table, currentSeat, cardToDiscard.id);
  }

  /**
   * Oyuncunun ortadaki kapalı desteden kağıt çekmesi
   */
  drawFromDeck(userId: string, tableId: string) {
    const table = this.tables.get(tableId);
    if (!table || table.status !== 'playing') {
      throw new Error('Şu anda kağıt çekilemez.');
    }
    const currentSeat = table.seats[table.currentTurnSeat];
    if (!currentSeat || currentSeat.userId !== userId) {
      throw new Error('Sıra sizde değil.');
    }
    if (table.hasDrawnThisTurn) {
      throw new Error('Bu turda zaten kağıt çektiniz. Şimdi bir kağıt atmalısınız.');
    }
    if (table.drawPile.length === 0) {
      throw new Error('Ortada çekilecek kağıt kalmadı.');
    }

    const drawn = table.drawPile.shift()!;
    currentSeat.hand.push(drawn);
    table.hasDrawnThisTurn = true;

    this.io.to(`table:${table.id}`).emit('player_drew_card', {
      userId: currentSeat.userId,
      seatIndex: currentSeat.seatIndex,
      remainingDeckCount: table.drawPile.length,
    });

    this.sendTableStateToUser(table, userId);
    this.broadcastTableState(table.id);
  }

  /**
   * Oyuncunun elinden yere kağıt atması
   */
  discardCard(userId: string, tableId: string, cardId: string) {
    const table = this.tables.get(tableId);
    if (!table || table.status !== 'playing') {
      throw new Error('Şu anda kağıt atılamaz.');
    }
    const currentSeat = table.seats[table.currentTurnSeat];
    if (!currentSeat || currentSeat.userId !== userId) {
      throw new Error('Sıra sizde değil.');
    }
    if (!table.hasDrawnThisTurn) {
      throw new Error('Kağıt atmadan önce ortadaki desteden kağıt çekmelisiniz!');
    }

    this.executeDiscard(table, currentSeat, cardId);
  }

  private executeDiscard(table: GameTable, seat: SeatPlayer, cardId: string) {
    const idx = seat.hand.findIndex((c) => c.id === cardId);
    if (idx === -1) {
      throw new Error('Atılmak istenen kağıt elinizde bulunamadı.');
    }

    const [discarded] = seat.hand.splice(idx, 1);
    table.discardPile.push(discarded);

    this.io.to(`table:${table.id}`).emit('card_discarded', {
      userId: seat.userId,
      username: seat.username,
      seatIndex: seat.seatIndex,
      card: discarded,
    });

    // Ortadaki çekilecek kağıtlar bitti ve kimse açmadıysa herkes elindeki sayıyı yer!
    if (table.drawPile.length === 0) {
      this.endRound(table, null);
      return;
    }

    // Sırayı bir sonraki oyuncuya geçir
    table.currentTurnSeat = this.getNextActiveSeatIndex(table, table.currentTurnSeat);
    table.hasDrawnThisTurn = false;
    this.startTurnTimer(table);
    this.broadcastTableState(table.id);
  }

  /**
   * Oyuncunun "EL AÇ / BİTİR" yapması (11 kağıttan 1'ini yere atıp kalan 10 kağıdın tamamının per olması)
   */
  declareFinish(userId: string, tableId: string, discardCardId?: string) {
    const table = this.tables.get(tableId);
    if (!table || table.status !== 'playing') {
      throw new Error('Oyun aktif değil.');
    }
    const currentSeat = table.seats[table.currentTurnSeat];
    if (!currentSeat || currentSeat.userId !== userId) {
      throw new Error('Sadece sırası gelen oyuncu el açabilir.');
    }
    if (!table.hasDrawnThisTurn || currentSeat.hand.length !== 11) {
      throw new Error('El açmak için önce ortadan kağıt çekmiş olmalısınız (11 kağıt).');
    }

    let chosenDiscard: Card | null = null;
    let remaining10: Card[] = [];

    if (discardCardId) {
      const idx = currentSeat.hand.findIndex((c) => c.id === discardCardId);
      if (idx !== -1) {
        const candidate10 = currentSeat.hand.filter((_, i) => i !== idx);
        const eval10 = evaluateHandOptimal(candidate10, table.wildRank);
        if (eval10.canFinish) {
          chosenDiscard = currentSeat.hand[idx];
          remaining10 = eval10.orderedCards;
        }
      }
    }

    // Eğer belirli bir kağıt seçilmediyse veya seçilenle bitmiyorsa, 11 kağıttan hangisi atılınca bittiğini otomatik bul
    if (!chosenDiscard) {
      for (let i = 0; i < currentSeat.hand.length; i++) {
        const candidate10 = currentSeat.hand.filter((_, idx) => idx !== i);
        const eval10 = evaluateHandOptimal(candidate10, table.wildRank);
        if (eval10.canFinish) {
          chosenDiscard = currentSeat.hand[i];
          remaining10 = eval10.orderedCards;
          break;
        }
      }
    }

    if (!chosenDiscard) {
      throw new Error(
        'Elinizdeki 10 kağıdın tamamı geçerli per oluşturmuyor! Açmak için boşta kağıt kalmamalıdır.'
      );
    }

    // Atılan kağıdı ıskartaya koy ve eli bitir
    currentSeat.hand = remaining10;
    table.discardPile.push(chosenDiscard);

    this.endRound(table, currentSeat.userId);
  }

  /**
   * El sonu puan hesaplama, Açık El Gösterimi (Showdown), 101 Yanma ve Re-buy kontrolü
   */
  private endRound(table: GameTable, finisherUserId: string | null) {
    if (table.turnTimer) clearTimeout(table.turnTimer);

    const activePlayers = table.seats.filter(
      (s): s is SeatPlayer => s !== null && !s.isEliminated
    );

    const scoresByUser: Record<string, number> = {};
    const totalsByUser: Record<string, number> = {};
    const showdownResults: ShowdownPlayerResult[] = [];

    // Önce herkesin bu eldeki cezasını ve yeni toplam puanını hesapla
    for (const player of activePlayers) {
      const evalHand = evaluateHandOptimal(player.hand, table.wildRank);
      const isFinisher = player.userId === finisherUserId;
      const roundPenalty = isFinisher ? 0 : evalHand.penalty;
      const prevScore = player.totalScore;
      const newTotal = prevScore + roundPenalty;

      player.totalScore = newTotal;
      scoresByUser[player.userId] = roundPenalty;
      totalsByUser[player.userId] = newTotal;

      const burnedThisRound = newTotal >= 101;
      if (burnedThisRound) {
        player.isEliminated = true;
      }

      showdownResults.push({
        userId: player.userId,
        username: player.username,
        avatar: player.avatar,
        melds: evalHand.melds,
        unmelded: isFinisher ? [] : evalHand.unmelded,
        roundPenalty,
        previousScore: prevScore,
        newTotalScore: newTotal,
        burnedThisRound,
        canRebuy: false,
        rebuyMultiplier: player.rebuyCount + 1,
        rebuyCost: (player.rebuyCount + 1) * table.entryFee,
        rebuyTargetScore: 0,
      });
    }

    // Eğer herkes aynı anda 101'i geçtiyse (örneğin deste bittiğinde), en düşük puana sahip olan elenmemiş sayılır
    const survivors = activePlayers.filter((p) => !p.isEliminated);
    if (survivors.length === 0 && activePlayers.length > 0) {
      activePlayers.sort((a, b) => a.totalScore - b.totalScore);
      const bestPlayer = activePlayers[0];
      bestPlayer.isEliminated = false;
      survivors.push(bestPlayer);
      const sd = showdownResults.find((s) => s.userId === bestPlayer.userId);
      if (sd) sd.burnedThisRound = false;
    }

    // Kaybetmeyenler arasındaki EN KÖTÜ (en yüksek) puanı bul (Re-buy yapanlar bu puanla girer)
    const worstSurvivorScore =
      survivors.length > 0 ? Math.max(...survivors.map((s) => s.totalScore)) : 0;

    // KURAL: Son 2 oyuncu kaldığında yanan oyuncu geri dönemez!
    // Yani el başında 2 kişi oynuyorsa ve biri yandıysa kazanan belli olmuştur.
    // El başında 3 veya daha fazla kişi varsa (veya hala en az 2 kişi hayattaysa) yanan oyuncular Re-buy yapabilir.
    const rebuyAllowedInThisRound =
      table.activePlayersAtRoundStart > 2 || survivors.length >= 2;

    let anyAwaitingRebuy = false;
    for (const sd of showdownResults) {
      if (sd.burnedThisRound && rebuyAllowedInThisRound) {
        sd.canRebuy = true;
        sd.rebuyTargetScore = worstSurvivorScore;
        const seat = table.seats.find((s) => s?.userId === sd.userId);
        if (seat) {
          seat.awaitingRebuyDecision = true;
          anyAwaitingRebuy = true;
        }
      }
    }

    table.scoreHistory.push({
      roundNumber: table.roundNumber,
      scoresByUser,
      totalsByUser,
      finisherUserId,
    });

    table.status = 'round_summary';
    table.lastShowdown = showdownResults;
    // Sonraki el veya Re-buy karar süresi: Re-buy varsa 15 sn, yoksa 8 sn açık elleri göster
    const waitMs = anyAwaitingRebuy ? 15000 : 8000;
    table.turnDeadline = Date.now() + waitMs;

    this.io.to(`table:${table.id}`).emit('round_ended', {
      roundNumber: table.roundNumber,
      finisherUserId,
      showdown: showdownResults,
      waitMs,
    });

    this.broadcastTableState(table.id);

    table.phaseTimer = setTimeout(() => {
      this.proceedAfterRoundSummary(table);
    }, waitMs);
  }

  /**
   * 101 olup yanan oyuncunun "Yeniden Oyuna Gir (1x, 2x, 3x...)" işlemi
   */
  async rebuyIntoMatch(userId: string, tableId: string): Promise<void> {
    const table = this.tables.get(tableId);
    if (!table || table.status !== 'round_summary') {
      throw new Error('Şu anda yeniden giriş (re-buy) yapılamaz.');
    }

    const seat = table.seats.find((s) => s?.userId === userId);
    if (!seat || !seat.isEliminated || !seat.awaitingRebuyDecision) {
      throw new Error('Yeniden giriş hakkınız bulunmuyor.');
    }

    const multiplier = seat.rebuyCount + 1; // 1. giriş: 1x, 2. giriş: 2x, 3. giriş: 3x...
    const cost = multiplier * table.entryFee;

    const survivors = table.seats.filter(
      (s): s is SeatPlayer => s !== null && !s.isEliminated
    );
    const targetScore =
      survivors.length > 0 ? Math.max(...survivors.map((s) => s.totalScore)) : 0;

    // Krediyi düş ve Masanın Ödül Havuzuna (Pot) ekle
    const newBalance = await db.adjustCredits(
      userId,
      -cost,
      'table_rebuy',
      `${table.name} masası ${multiplier}x yeniden oyuna giriş (Re-buy)`
    );

    this.emitBalanceUpdate(userId, newBalance);

    table.pot += cost;
    seat.rebuyCount += 1;
    seat.totalScore = targetScore;
    seat.isEliminated = false;
    seat.awaitingRebuyDecision = false;

    if (table.lastShowdown) {
      const sd = table.lastShowdown.find((x) => x.userId === userId);
      if (sd) {
        sd.burnedThisRound = false;
        sd.canRebuy = false;
        sd.newTotalScore = targetScore;
      }
    }

    this.io.to(`table:${table.id}`).emit('player_rebought', {
      userId: seat.userId,
      username: seat.username,
      multiplier,
      cost,
      newScore: targetScore,
      newPot: table.pot,
    });

    this.broadcastTableState(table.id);
    this.broadcastLobbyTables();
  }

  private proceedAfterRoundSummary(table: GameTable) {
    if (table.phaseTimer) clearTimeout(table.phaseTimer);

    for (const s of table.seats) {
      if (s) s.awaitingRebuyDecision = false;
    }

    const survivors = table.seats.filter(
      (s): s is SeatPlayer => s !== null && !s.isEliminated
    );

    if (survivors.length <= 1) {
      this.concludeMatch(table);
    } else {
      this.startNewRound(table);
    }
  }

  /**
   * Oyun sonu: Kasa %5 komisyon alır, %95 kazanan oyuncuya aktarılır!
   */
  private async concludeMatch(table: GameTable) {
    if (table.turnTimer) clearTimeout(table.turnTimer);
    if (table.phaseTimer) clearTimeout(table.phaseTimer);

    const survivors = table.seats.filter(
      (s): s is SeatPlayer => s !== null && !s.isEliminated
    );

    const winner = survivors[0] || table.seats.find((s) => s !== null);
    const totalPot = table.pot;
    const houseRake = Math.round(totalPot * 0.05); // %5 Kasa Komisyonu
    const prizeWon = totalPot - houseRake; // %95 Kazanan Ödülü

    table.status = 'finished';
    table.pot = 0;

    for (const s of table.seats) {
      if (s) s.isReady = false;
    }

    if (winner && totalPot > 0) {
      try {
        const newBal = await db.adjustCredits(
          winner.userId,
          prizeWon,
          'table_win',
          `${table.name} masası şampiyonluk ödülü (%95 Pot)`
        );
        await db.addVaultRake(houseRake);
        this.emitBalanceUpdate(winner.userId, newBal);

        table.lastWinnerInfo = {
          userId: winner.userId,
          username: winner.username,
          avatar: winner.avatar,
          totalPot,
          houseRake,
          prizeWon,
        };

        this.io.to(`table:${table.id}`).emit('match_finished', table.lastWinnerInfo);
      } catch (err) {
        console.error('Ödül dağıtım hatası:', err);
      }
    }

    this.broadcastTableState(table.id);
    this.broadcastLobbyTables();
  }

  /**
   * Oyuncunun elindeki kağıtları kendi istediği sıraya dizmesi veya "Otomatik Diz" yapması
   */
  reorderPlayerHand(userId: string, tableId: string, orderedCardIds?: string[]) {
    const table = this.tables.get(tableId);
    if (!table) return;
    const seat = table.seats.find((s) => s?.userId === userId);
    if (!seat || seat.hand.length === 0) return;

    if (!orderedCardIds || orderedCardIds.length === 0) {
      // Otomatik Per Diz
      const evalHand = evaluateHandOptimal(seat.hand, table.wildRank);
      seat.hand = evalHand.orderedCards;
    } else {
      const map = new Map(seat.hand.map((c) => [c.id, c]));
      const reordered: Card[] = [];
      for (const id of orderedCardIds) {
        const c = map.get(id);
        if (c) {
          reordered.push(c);
          map.delete(id);
        }
      }
      for (const c of map.values()) {
        reordered.push(c);
      }
      seat.hand = reordered;
    }

    this.sendTableStateToUser(table, userId);
  }

  /**
   * Masa içi Ücretli Emoji / Efekt gönderimi (Bomba, Domates, Gül, Alkış, Kahkaha, Ağlama)
   */
  async sendInteractiveEffect(
    senderId: string,
    tableId: string,
    targetUserId: string,
    effectKey: string
  ): Promise<void> {
    const table = this.tables.get(tableId);
    if (!table) throw new Error('Masa bulunamadı.');

    const effect = INTERACTIVE_EFFECTS[effectKey] || INTERACTIVE_EFFECTS.clap;
    const vault = await db.getVaultSummary();
    const cost = vault.emoji_cost;

    const sender = await db.getUserById(senderId);
    if (!sender) throw new Error('Kullanıcı bulunamadı.');

    if (cost > 0) {
      const newBal = await db.adjustCredits(
        senderId,
        -cost,
        'emoji_gift',
        `Masa içi ${effect.name} efekti gönderimi`
      );
      await db.addVaultEmojiRevenue(cost);
      this.emitBalanceUpdate(senderId, newBal);
    }

    this.io.to(`table:${tableId}`).emit('interactive_effect', {
      senderId,
      senderUsername: sender.username,
      targetUserId,
      effectKey,
      effectName: effect.name,
      effectIcon: effect.icon,
      cost,
    });
  }

  private emitBalanceUpdate(userId: string, credits: number) {
    const sid = this.userSockets.get(userId);
    if (sid) {
      this.io.to(sid).emit('balance_updated', { credits });
    }
  }

  /**
   * Masadaki tüm oyunculara ve izleyicilere (herkese sadece kendi elindeki kağıtları açık göstererek) masa durumunu yayınlar
   */
  broadcastTableState(tableId: string) {
    const table = this.tables.get(tableId);
    if (!table) return;

    const recipientIds = new Set<string>(table.spectators);
    for (const s of table.seats) {
      if (s) recipientIds.add(s.userId);
    }

    for (const uid of recipientIds) {
      this.sendTableStateToUser(table, uid);
    }
  }

  sendTableStateToUser(table: GameTable, viewerUserId: string) {
    const sid = this.userSockets.get(viewerUserId);
    if (!sid) return;

    const viewerSeat = table.seats.find((s) => s?.userId === viewerUserId);
    let viewerEvaluation = null;
    if (viewerSeat && viewerSeat.hand.length > 0) {
      const evalRes = evaluateHandOptimal(viewerSeat.hand, table.wildRank);
      const meldedIds = new Set(evalRes.melds.flat().map((c) => c.id));
      let canFinishNow = evalRes.canFinish;
      let winningDiscardCardId: string | null = null;

      if (viewerSeat.hand.length === 11) {
        const winCheck = findWinningDiscard(viewerSeat.hand, table.wildRank);
        if (winCheck.canWin && winCheck.discardCard && winCheck.evaluation) {
          canFinishNow = true;
          winningDiscardCardId = winCheck.discardCard.id;
          meldedIds.clear();
          for (const c of winCheck.evaluation.melds.flat()) {
            meldedIds.add(c.id);
          }
        }
      }

      viewerEvaluation = {
        canFinish: canFinishNow,
        winningDiscardCardId,
        penalty: evalRes.penalty,
        meldedCardIds: Array.from(meldedIds),
      };
    }

    const payload = {
      id: table.id,
      name: table.name,
      hostUserId: table.hostUserId,
      hostUsername: table.hostUsername,
      minPlayers: table.minPlayers,
      maxPlayers: table.maxPlayers,
      entryFee: table.entryFee,
      status: table.status,
      pot: table.pot,
      roundNumber: table.roundNumber,
      drawPileCount: table.drawPile.length,
      topDiscardCard:
        table.discardPile.length > 0
          ? table.discardPile[table.discardPile.length - 1]
          : null,
      indicatorCard: table.indicatorCard,
      wildRank: table.wildRank,
      currentTurnSeat: table.currentTurnSeat,
      dealerSeat: table.dealerSeat,
      hasDrawnThisTurn: table.hasDrawnThisTurn,
      turnRemainingSeconds: Math.max(
        0,
        Math.ceil((table.turnDeadline - Date.now()) / 1000)
      ),
      seats: table.seats.map((s) => {
        if (!s) return null;
        return {
          userId: s.userId,
          username: s.username,
          avatar: s.avatar,
          seatIndex: s.seatIndex,
          isReady: s.isReady,
          isConnected: s.isConnected,
          totalScore: s.totalScore,
          isEliminated: s.isEliminated,
          rebuyCount: s.rebuyCount,
          awaitingRebuyDecision: s.awaitingRebuyDecision,
          cardCount: s.hand.length,
        };
      }),
      myHand: viewerSeat ? viewerSeat.hand : [],
      myEvaluation: viewerEvaluation,
      lastShowdown: table.lastShowdown,
      scoreHistory: table.scoreHistory,
      lastWinnerInfo: table.lastWinnerInfo,
    };

    this.io.to(sid).emit('table_state', payload);
  }
}
