import crypto from 'crypto';
import { Server, Socket } from 'socket.io';
import { v4 as uuidv4 } from 'uuid';
import {
  Card,
  dealRoundHands,
  decomposeRowIntoMelds,
  evaluateHandOptimal,
  evaluatePlayerRowsForFinish,
  findWinningDiscard,
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
  forfeitedRebuy: boolean; // Yardımsız modda hatalı el açarsa re-buy hakkını tamamen kaybeder
  rebuyCount: number; // Kaç kez yandı ve geri döndü (0 -> ilk yanışta 1x öder, 1 -> 2x öder, 2 -> 3x öder)
  awaitingRebuyDecision: boolean;
  consecutiveTimeouts: number;
  hand: Card[];
  handRows?: string[][]; // 3 sıralı ıstaka dizilimi
  openedMelds?: Card[][]; // Oyuncunun el açarken masaya serdiği gerçek per dizilimi
  sortMode?: 'rank' | 'suit'; // Sayıya Göre Sırala butonunun geçiş modu
}

export interface RoundScoreSnapshot {
  roundNumber: number;
  scoresByUser: Record<string, number>; // O el alınan ceza puanı
  totalsByUser: Record<string, number>; // O el sonu toplam puan
  finisherUserId: string | null;
  falseDeclarerUserId?: string | null;
}

export interface ShowdownPlayerResult {
  userId: string;
  username: string;
  avatar: string;
  seatIndex: number;
  isFinisher: boolean;
  isFalseDeclarer: boolean;
  forfeitedRebuy: boolean;
  revealOrder: number;
  revealStartMs: number;
  revealDurationMs: number;
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
  isAssisted: boolean; // true = Yardımlı Mod (Per/Ceza göstergeli), false = Yardımsız Usta Modu
  status: 'waiting' | 'starting' | 'playing' | 'round_summary' | 'finished';
  pot: number;
  matchContributions: Record<string, number>;
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
  turnDurationSeconds: number;
  matchStartedAt: number;
  turnTimer?: NodeJS.Timeout;
  phaseTimer?: NodeJS.Timeout;
  activePlayersAtRoundStart: number;
  lastShowdown: ShowdownPlayerResult[] | null;
  lastFinisherUserId: string | null;
  lastFalseDeclarerUserId: string | null;
  showdownStartedAt: number;
  showdownTotalMs: number;
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
  // Çoklu sekme veya Wi-Fi/4G geçişlerinde soket çakışmasını önlemek için Set<socketId>
  private userSockets: Map<string, Set<string>> = new Map();
  // Masa bazlı asenkron işlem kuyruğu (Race Condition / Mutex kilidi)
  private tableLocks: Map<string, Promise<any>> = new Map();

  constructor(io: Server) {
    this.io = io;
    // Varsayılan açık/boş masa oluşturulmaz; yalnızca oyuncular masa kurduğunda görünür.
    // Her 1 saniyede bir aktif masalara canlı sayaç (hamle kalan süre + toplam maç süresi) gönder
    setInterval(() => this.tickActiveTables(), 1000);
  }

  /**
   * Aynı masadaki tüm kritik durum ve bakiye işlemlerini sıraya sokar (Per-Table Mutex)
   */
  private enqueueTableAction<T>(tableId: string, fn: () => Promise<T> | T): Promise<T> {
    const prev = this.tableLocks.get(tableId) || Promise.resolve();
    const next = prev
      .catch(() => {})
      .then(() => fn());
    this.tableLocks.set(
      tableId,
      next.catch(() => {})
    );
    return next;
  }

  private tickActiveTables() {
    const now = Date.now();
    for (const table of this.tables.values()) {
      if (table.status === 'playing' || table.status === 'round_summary') {
        const turnRemainingSeconds = Math.max(
          0,
          Math.ceil((table.turnDeadline - now) / 1000)
        );
        const matchElapsedSeconds =
          table.matchStartedAt > 0
            ? Math.max(0, Math.floor((now - table.matchStartedAt) / 1000))
            : 0;

        this.io.to(`table:${table.id}`).emit('table_timer_tick', {
          tableId: table.id,
          status: table.status,
          currentTurnSeat: table.currentTurnSeat,
          turnRemainingSeconds,
          turnDurationSeconds: table.turnDurationSeconds,
          matchElapsedSeconds,
        });
      }
    }
  }

  private splitHandIntoDefaultRows(cards: Card[]): string[][] {
    if (cards.length === 0) return [[], [], []];
    const r0 = cards.slice(0, 4).map((c) => c.id);
    const r1 = cards.slice(4, 7).map((c) => c.id);
    const r2 = cards.slice(7).map((c) => c.id);
    return [r0, r1, r2];
  }

  private syncSeatHandRows(seat: SeatPlayer) {
    const validIds = new Set(seat.hand.map((c) => c.id));
    if (!seat.handRows || seat.handRows.length !== 3) {
      seat.handRows = this.splitHandIntoDefaultRows(seat.hand);
      return;
    }

    const seen = new Set<string>();
    const cleanedRows: string[][] = [[], [], []];
    for (let r = 0; r < 3; r++) {
      for (const id of seat.handRows[r] || []) {
        if (validIds.has(id) && !seen.has(id)) {
          cleanedRows[r].push(id);
          seen.add(id);
        }
      }
    }

    // Yeni çekilen veya eksik kalan kağıtları en az kağıt olan sıraya ekle
    for (const c of seat.hand) {
      if (!seen.has(c.id)) {
        let targetRow = 2;
        if (cleanedRows[0].length <= cleanedRows[1].length && cleanedRows[0].length <= cleanedRows[2].length) {
          targetRow = 0;
        } else if (cleanedRows[1].length <= cleanedRows[2].length) {
          targetRow = 1;
        }
        cleanedRows[targetRow].push(c.id);
        seen.add(c.id);
      }
    }

    seat.handRows = cleanedRows;
  }

  registerUserSocket(socket: Socket, userId: string) {
    socket.join(`user:${userId}`);
    let set = this.userSockets.get(userId);
    if (!set) {
      set = new Set();
      this.userSockets.set(userId, set);
    }
    set.add(socket.id);

    // Oyuncu bir masada oturuyorsa bağlantı durumunu güncelle ve odaya otomatik dahil et
    for (const table of this.tables.values()) {
      let updated = false;
      for (const seat of table.seats) {
        if (seat && seat.userId === userId) {
          seat.isConnected = true;
          seat.consecutiveTimeouts = 0;
          updated = true;
        }
      }
      if (updated) {
        socket.join(`table:${table.id}`);
        this.broadcastTableState(table.id);
        socket.emit('active_table_rejoined', {
          tableId: table.id,
          tableName: table.name,
          status: table.status,
        });
      }
    }
  }

  disconnectUserSockets(userId: string) {
    const set = this.userSockets.get(userId);
    if (!set) return;
    for (const sid of set) {
      const sock = this.io.sockets.sockets.get(sid);
      if (sock) {
        sock.emit('error_msg', 'Hesabınız yönetici tarafından askıya alındı.');
        sock.disconnect(true);
      }
    }
    this.userSockets.delete(userId);
  }

  findUserActiveTableId(userId: string): string | null {
    for (const table of this.tables.values()) {
      if (table.seats.some((s) => s?.userId === userId)) {
        return table.id;
      }
    }
    return null;
  }

  isUserInTable(userId: string, tableId: string): boolean {
    const table = this.tables.get(tableId);
    if (!table) return false;
    if (table.spectators.has(userId)) return true;
    return table.seats.some((s) => s?.userId === userId);
  }

  private cleanupTableIfEmpty(tableId: string): boolean {
    const table = this.tables.get(tableId);
    if (!table) return false;
    // Kulübün varsayılan salon masaları her zaman açık kalır
    if (table.hostUserId === 'system') return false;
    // KRİTİK KORUMA: Aktif oyun veya pot varken masa ASLA silinmez!
    if (
      table.status === 'playing' ||
      table.status === 'round_summary' ||
      table.status === 'starting' ||
      table.pot > 0
    ) {
      return false;
    }

    const hasSeated = table.seats.some((s) => s !== null && s.isConnected);
    const hasSpectators = table.spectators.size > 0;

    if (!hasSeated && !hasSpectators) {
      if (table.turnTimer) clearTimeout(table.turnTimer);
      if (table.phaseTimer) clearTimeout(table.phaseTimer);
      this.tables.delete(tableId);
      this.tableLocks.delete(tableId);
      return true;
    }
    return false;
  }

  handleDisconnect(userId: string, socketId: string) {
    const set = this.userSockets.get(userId);
    if (set) {
      set.delete(socketId);
      if (set.size > 0) {
        // Kullanıcının başka bir aktif soketi hala bağlı (Wi-Fi -> 4G geçişi)
        return;
      }
      this.userSockets.delete(userId);
    }

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
    entryFee: number,
    isAssisted = true
  ): GameTable {
    const clampedMax = Math.min(6, Math.max(2, Math.round(maxPlayers)));
    const cleanFee = Math.max(10, Math.round(entryFee));
    const id = uuidv4().slice(0, 8);

    const table: GameTable = {
      id,
      name: name.trim() || `Masa #${id.slice(0, 4)}`,
      hostUserId,
      hostUsername,
      minPlayers: clampedMax,
      maxPlayers: clampedMax,
      entryFee: cleanFee,
      isAssisted: Boolean(isAssisted),
      status: 'waiting',
      pot: 0,
      matchContributions: {},
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
      turnDurationSeconds: 30,
      matchStartedAt: 0,
      activePlayersAtRoundStart: 0,
      lastShowdown: null,
      lastFinisherUserId: null,
      lastFalseDeclarerUserId: null,
      showdownStartedAt: 0,
      showdownTotalMs: 0,
      scoreHistory: [],
      lastWinnerInfo: null,
    };

    this.tables.set(id, table);
    this.broadcastLobbyTables();
    return table;
  }

  async closeTableByAdmin(tableId: string): Promise<boolean> {
    const table = this.tables.get(tableId);
    if (!table) return false;
    if (table.turnTimer) clearTimeout(table.turnTimer);
    if (table.phaseTimer) clearTimeout(table.phaseTimer);

    // Eğer masada aktif pot varsa tüm oyunculara yatırdıkları kredileri eksiksiz iade et!
    if (table.pot > 0) {
      try {
        const refunded = await db.refundMatchEscrow(
          tableId,
          `${table.name} yönetici tarafından kapatıldı (Pot İadesi)`
        );
        for (const r of refunded) {
          this.emitBalanceUpdate(r.userId, r.newCredits);
        }
      } catch (err) {
        console.error('Admin masa kapatma iade hatası:', err);
      }
    }

    this.io.to(`table:${tableId}`).emit('table_closed', {
      message: 'Bu masa yönetici tarafından kapatıldı. Aktif pot varsa bakiyenize iade edildi.',
    });
    this.tables.delete(tableId);
    this.tableLocks.delete(tableId);
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
      isAssisted: t.isAssisted,
      status: t.status === 'starting' ? 'playing' : t.status,
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
    const seat = table.seats.find((s) => s?.userId === userId);
    if (seat) {
      seat.isConnected = true;
      seat.consecutiveTimeouts = 0;
    }
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
    return this.enqueueTableAction(tableId, async () => {
      const table = this.tables.get(tableId);
      if (!table) throw new Error('Masa bulunamadı.');
      if (table.status !== 'waiting' && table.status !== 'finished') {
        throw new Error('Oyun devam ederken koltuğa oturulamaz.');
      }
      if (seatIndex < 0 || seatIndex >= table.maxPlayers) {
        throw new Error('Geçersiz koltuk numarası.');
      }
      if (table.seats[seatIndex] !== null && table.seats[seatIndex]?.userId !== userId) {
        throw new Error('Bu koltuk dolu.');
      }

      // Oyuncu başka bir masada aktif oyundaysa oturamasın
      for (const otherTable of this.tables.values()) {
        if (
          otherTable.id !== tableId &&
          (otherTable.status === 'playing' || otherTable.status === 'round_summary') &&
          otherTable.seats.some((s) => s?.userId === userId && !s.isEliminated)
        ) {
          throw new Error(`Zaten "${otherTable.name}" masasında devam eden bir oyununuz var.`);
        }
      }

      const user = await db.getUserById(userId);
      if (!user) throw new Error('Kullanıcı bulunamadı.');
      if (user.is_banned) throw new Error('Hesabınız askıya alınmıştır.');
      if (user.credits < table.entryFee) {
        throw new Error(`Bu masaya oturmak için en az ${table.entryFee} kredi gereklidir.`);
      }

      // Yeniden kontrol (async DB sorgusu sonrası koltuk dolmuş olabilir)
      if (table.status !== 'waiting' && table.status !== 'finished') {
        throw new Error('Oyun devam ederken koltuğa oturulamaz.');
      }
      if (table.seats[seatIndex] !== null && table.seats[seatIndex]?.userId !== userId) {
        throw new Error('Bu koltuk az önce doldu.');
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
        forfeitedRebuy: false,
        rebuyCount: 0,
        awaitingRebuyDecision: false,
        consecutiveTimeouts: 0,
        hand: [],
        handRows: [[], [], []],
        openedMelds: undefined,
        sortMode: 'rank',
      };

      if (table.status === 'finished') {
        table.status = 'waiting';
        table.lastWinnerInfo = null;
        table.lastShowdown = null;
        for (const s of table.seats) {
          if (s) {
            s.isEliminated = false;
            s.forfeitedRebuy = false;
            s.totalScore = 0;
            s.hand = [];
            s.handRows = [[], [], []];
            s.openedMelds = undefined;
          }
        }
      }

      this.broadcastTableState(tableId);
      this.broadcastLobbyTables();
    });
  }

  standUpFromSeat(userId: string, tableId: string) {
    return this.enqueueTableAction(tableId, () => {
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
    });
  }

  async toggleReady(userId: string, tableId: string): Promise<void> {
    return this.enqueueTableAction(tableId, async () => {
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
            s.forfeitedRebuy = false;
            s.totalScore = 0;
            s.hand = [];
            s.handRows = [[], [], []];
            s.openedMelds = undefined;
          }
        }
      }

      seat.isReady = !seat.isReady;
      this.broadcastTableState(tableId);

      // KURAL: Masadaki TÜM koltuklar (table.maxPlayers) dolup herkes HAZIR olduğunda oyun başlar!
      const seatedPlayers = table.seats.filter((s): s is SeatPlayer => s !== null);
      if (
        seatedPlayers.length === table.maxPlayers &&
        seatedPlayers.every((s) => s.isReady)
      ) {
        await this.startMatch(table);
      }
    });
  }

  private async startMatch(table: GameTable): Promise<void> {
    if (table.status !== 'waiting') return;
    const seatedPlayers = table.seats.filter((s): s is SeatPlayer => s !== null);
    if (seatedPlayers.length < table.maxPlayers) return;

    // Senkron kilit: Çift tahsilatı önlemek için durumu hemen 'starting' yap
    table.status = 'starting';

    let collectedPot = 0;
    const chargedUsers: string[] = [];
    const contributions: Record<string, number> = {};

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
        contributions[p.userId] = (contributions[p.userId] || 0) + table.entryFee;
        this.emitBalanceUpdate(p.userId, newBal);
      }
    } catch (err: any) {
      // Bir oyuncunun bakiyesi yetmediyse diğerlerine iade et
      for (const uid of chargedUsers) {
        try {
          const bal = await db.adjustCredits(
            uid,
            table.entryFee,
            'table_refund',
            `${table.name} masa başlangıç iptali iadesi`
          );
          this.emitBalanceUpdate(uid, bal);
        } catch {}
      }
      table.status = 'waiting';
      for (const p of seatedPlayers) p.isReady = false;
      this.io.to(`table:${table.id}`).emit('error_msg', `Oyun başlatılamadı: ${err.message}`);
      this.broadcastTableState(table.id);
      return;
    }

    table.status = 'playing';
    table.pot = collectedPot;
    table.matchContributions = contributions;
    table.roundNumber = 0;
    table.matchStartedAt = Date.now();
    table.scoreHistory = [];
    table.lastWinnerInfo = null;
    table.lastShowdown = null;
    table.lastFinisherUserId = null;
    table.lastFalseDeclarerUserId = null;

    // Aktif maçı veritabanı escrow tablosuna kaydet (Crash koruması)
    try {
      await db.upsertMatchEscrow(table.id, table.name, table.pot, table.matchContributions);
    } catch (err) {
      console.error('Escrow kayıt hatası:', err);
    }

    for (const p of seatedPlayers) {
      p.totalScore = 0;
      p.isEliminated = false;
      p.forfeitedRebuy = false;
      p.rebuyCount = 0;
      p.awaitingRebuyDecision = false;
      p.consecutiveTimeouts = 0;
      p.hand = [];
      p.handRows = [[], [], []];
      p.openedMelds = undefined;
    }

    // İlk dağıtan CSPRNG (crypto.randomInt) ile rastgele bir koltuk
    table.dealerSeat = seatedPlayers[crypto.randomInt(0, seatedPlayers.length)].seatIndex;

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
    table.lastFinisherUserId = null;
    table.lastFalseDeclarerUserId = null;
    table.discardPile = [];

    const activeIds = activePlayers.map((p) => p.userId);
    const { hands, drawPile, indicatorCard, wildRank } = dealRoundHands(activeIds);

    for (const seat of table.seats) {
      if (!seat) continue;
      seat.awaitingRebuyDecision = false;
      if (!seat.isEliminated) {
        const dealt = hands[seat.userId] || [];
        if (table.isAssisted) {
          // Yardımlı modda başlangıçta düzenli bir el sun
          seat.hand = evaluateHandOptimal(dealt, wildRank).orderedCards;
        } else {
          // Yardımsız (Usta) modda kağıtları olduğu gibi ver, oyuncu kendi dizsin
          seat.hand = [...dealt];
        }
        seat.handRows = this.splitHandIntoDefaultRows(seat.hand);
      } else {
        seat.hand = [];
        seat.handRows = [[], [], []];
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
      dealerSeat: table.dealerSeat,
      currentTurnSeat: table.currentTurnSeat,
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

    const currentSeat = table.seats[table.currentTurnSeat];
    // Bağlantısı kopuk veya üst üste 2 kez süre aşımı yapan oyuncunun süresini 8 saniyeye düşür (Anti-Stall)
    const isFastTimeout =
      currentSeat && (!currentSeat.isConnected || currentSeat.consecutiveTimeouts >= 2);
    const durationMs = isFastTimeout ? 8000 : 30000;

    table.turnDurationSeconds = Math.round(durationMs / 1000);
    table.turnDeadline = Date.now() + durationMs;

    table.turnTimer = setTimeout(() => {
      this.enqueueTableAction(table.id, () => {
        try {
          this.handleTurnTimeout(table);
        } catch (err) {
          console.error('Turn timeout hatası:', err);
        }
      });
    }, durationMs);
  }

  /**
   * Hamle süresi dolduğunda:
   * 1. Oyuncu henüz kağıt çekmediyse ortadan 1 kağıt çeker
   * 2. Per olmayan ve Joker olmayan en büyük gereksiz kağıdı otomatik atar
   */
  private handleTurnTimeout(table: GameTable) {
    if (table.status !== 'playing') return;
    const currentSeat = table.seats[table.currentTurnSeat];
    if (!currentSeat || currentSeat.isEliminated) return;

    currentSeat.consecutiveTimeouts += 1;

    // 1. Kağıt çekmediyse ortadan çek
    if (!table.hasDrawnThisTurn && table.drawPile.length > 0) {
      const drawn = table.drawPile.shift()!;
      currentSeat.hand.push(drawn);
      this.syncSeatHandRows(currentSeat);
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
    return this.enqueueTableAction(tableId, () => {
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

      currentSeat.consecutiveTimeouts = 0;
      const drawn = table.drawPile.shift()!;
      currentSeat.hand.push(drawn);
      this.syncSeatHandRows(currentSeat);
      table.hasDrawnThisTurn = true;

      this.io.to(`table:${table.id}`).emit('player_drew_card', {
        userId: currentSeat.userId,
        seatIndex: currentSeat.seatIndex,
        remainingDeckCount: table.drawPile.length,
      });

      this.broadcastTableState(table.id);
    });
  }

  /**
   * Oyuncunun elinden yere kağıt atması
   */
  discardCard(userId: string, tableId: string, cardId: string) {
    return this.enqueueTableAction(tableId, () => {
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

      currentSeat.consecutiveTimeouts = 0;
      this.executeDiscard(table, currentSeat, cardId);
    });
  }

  private executeDiscard(table: GameTable, seat: SeatPlayer, cardId: string) {
    const idx = seat.hand.findIndex((c) => c.id === cardId);
    if (idx === -1) {
      throw new Error('Atılmak istenen kağıt elinizde bulunamadı.');
    }

    const [discarded] = seat.hand.splice(idx, 1);
    this.syncSeatHandRows(seat);
    table.discardPile.push(discarded);

    this.io.to(`table:${table.id}`).emit('card_discarded', {
      userId: seat.userId,
      username: seat.username,
      seatIndex: seat.seatIndex,
      card: discarded,
    });

    // Ortadaki çekilecek kağıtlar bitti ve kimse açmadıysa herkes elindeki sayıyı yer!
    if (table.drawPile.length === 0) {
      this.endRound(table, null, null);
      return;
    }

    // Sırayı bir sonraki oyuncuya geçir
    table.currentTurnSeat = this.getNextActiveSeatIndex(table, table.currentTurnSeat);
    table.hasDrawnThisTurn = false;
    this.startTurnTimer(table);
    this.broadcastTableState(table.id);
  }

  /**
   * Oyuncunun "EL AÇ / BİTİR" yapması:
   * - ÖNCE oyuncunun 3 sırada kendi dizdiği perleri (`evaluatePlayerRowsForFinish`) kontrol eder.
   *   Böylece oyuncunun 2♠ - Joker - Joker - 5♠ gibi yaptığı geçerli perleri ASLA bozmaz ve dışarıda kalan 11. kağıdı (ör. Papaz) atar!
   * - Yardımlı Modda (`table.isAssisted === true`): Geçersizse uyarı verir, oyuncuyu yakmaz.
   * - Yardımsız Modda (`table.isAssisted === false`): Eğer hatalı el açarsa oyuncu DİREKT YANAR (101+)
   *   ve bu oyun için RE-BUY (yeniden giriş) hakkını tamamen kaybeder!
   */
  declareFinish(
    userId: string,
    tableId: string,
    discardCardId?: string,
    rowCardIds?: string[][]
  ) {
    return this.enqueueTableAction(tableId, () => {
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

      currentSeat.consecutiveTimeouts = 0;

      if (rowCardIds && Array.isArray(rowCardIds) && rowCardIds.length === 3) {
        currentSeat.handRows = rowCardIds;
        this.syncSeatHandRows(currentSeat);
      }

      // 1. ÖNCE oyuncunun kendi 3 sıra diziliminde (ör. 2♠ - Joker - Joker - 5♠ + Papaz) geçerli bitiş var mı kontrol et!
      const rowFinish = evaluatePlayerRowsForFinish(
        currentSeat.hand,
        currentSeat.handRows,
        table.wildRank,
        discardCardId
      );

      if (
        rowFinish.canWinFromRows &&
        rowFinish.discardCard &&
        rowFinish.melds &&
        rowFinish.orderedCards
      ) {
        currentSeat.hand = rowFinish.orderedCards;
        currentSeat.openedMelds = rowFinish.melds;
        const newRows: string[][] = [[], [], []];
        rowFinish.melds.forEach((meld, idx) => {
          const rIdx = Math.min(2, idx);
          newRows[rIdx].push(...meld.map((c) => c.id));
        });
        currentSeat.handRows = newRows;
        this.syncSeatHandRows(currentSeat);
        table.discardPile.push(rowFinish.discardCard);
        this.endRound(table, currentSeat.userId, null);
        return;
      }

      if (table.isAssisted) {
        // YARDIMLI MOD: Oyuncunun 3 sırası doğrudan per değilse bile eldeki 11 kağıttan 10'u per oluyorsa otomatik bul ve aç
        const winCheck = findWinningDiscard(
          currentSeat.hand,
          table.wildRank,
          currentSeat.handRows,
          discardCardId
        );

        if (!winCheck.canWin || !winCheck.discardCard || !winCheck.evaluation) {
          throw new Error(
            'Elinizdeki 10 kağıdın tamamı geçerli per oluşturmuyor! Açmak için boşta kağıt kalmamalıdır.'
          );
        }

        currentSeat.hand = winCheck.evaluation.orderedCards;
        currentSeat.openedMelds = winCheck.evaluation.melds;
        const newRows: string[][] = [[], [], []];
        winCheck.evaluation.melds.forEach((meld, idx) => {
          const rIdx = Math.min(2, idx);
          newRows[rIdx].push(...meld.map((c) => c.id));
        });
        currentSeat.handRows = newRows;
        this.syncSeatHandRows(currentSeat);
        table.discardPile.push(winCheck.discardCard);
        this.endRound(table, currentSeat.userId, null);
        return;
      }

      // YARDIMSIZ (USTA) MOD:
      // Buraya gelindiyse oyuncunun 3 sıradaki dizilimi geçerli bir 10'lu el açma oluşturmuyordur!
      let discardIdx = discardCardId
        ? currentSeat.hand.findIndex((c) => c.id === discardCardId)
        : -1;
      if (discardIdx === -1) {
        discardIdx = currentSeat.hand.length - 1;
      }

      const chosenDiscard = currentSeat.hand[discardIdx];
      const remaining10 = currentSeat.hand.filter((_, i) => i !== discardIdx);
      currentSeat.hand = remaining10;
      currentSeat.openedMelds = undefined;
      this.syncSeatHandRows(currentSeat);
      table.discardPile.push(chosenDiscard);

      // HATALI EL AÇMA CEZASI!
      // Oyuncu direkt yanar ve bu maç için Re-buy (tekrar para yatırıp dahil olma) hakkını kaybeder!
      currentSeat.forfeitedRebuy = true;
      this.io.to(`table:${table.id}`).emit('false_declare_penalty', {
        userId: currentSeat.userId,
        username: currentSeat.username,
        message: `${currentSeat.username} Yardımsız Modda HATALI EL AÇTI! Direkt yandı ve yeniden giriş (Re-buy) hakkını kaybetti!`,
      });
      this.endRound(table, null, currentSeat.userId);
    });
  }

  /**
   * El sonu puan hesaplama, Şeffaf Sıralı Açık El Gösterimi (Showdown), 101 Yanma ve Re-buy kontrolü
   * - İlk 10 saniye: Eli açan oyuncunun kağıtları masada herkese gösterilir.
   * - Sonrasında: Diğer oyuncuların elleri saat yönünde sırayla (kişi başı 3.5 sn) açılır ve ceza puanları işlenir.
   */
  private endRound(
    table: GameTable,
    finisherUserId: string | null,
    falseDeclarerUserId: string | null = null
  ) {
    if (table.turnTimer) clearTimeout(table.turnTimer);

    const activePlayers = table.seats.filter(
      (s): s is SeatPlayer => s !== null && !s.isEliminated
    );

    // Saat yönünde (seatIndex sırasına göre) sıralama:
    // Eli açan (veya hatalı açan) oyuncu 1. sırada (0-10 sn), diğerleri saat yönünde peşinden gelir
    const leadUserId = finisherUserId || falseDeclarerUserId;
    const leadSeat =
      activePlayers.find((p) => p.userId === leadUserId)?.seatIndex ?? table.currentTurnSeat;

    const orderedPlayers = [...activePlayers].sort((a, b) => {
      const distA = (a.seatIndex - leadSeat + table.maxPlayers) % table.maxPlayers;
      const distB = (b.seatIndex - leadSeat + table.maxPlayers) % table.maxPlayers;
      return distA - distB;
    });

    const scoresByUser: Record<string, number> = {};
    const totalsByUser: Record<string, number> = {};
    const showdownResults: ShowdownPlayerResult[] = [];

    const hasLeadShowcase = Boolean(leadUserId);
    const openerShowcaseMs = hasLeadShowcase ? 10000 : 0;
    const perOpponentRevealMs = 3500;

    for (let idx = 0; idx < orderedPlayers.length; idx++) {
      const player = orderedPlayers[idx];
      const isFinisher = player.userId === finisherUserId;
      const isFalseDeclarer = player.userId === falseDeclarerUserId;

      // Eli açan oyuncunun kendi dizdiği perleri (`openedMelds`) birebir koru!
      const evalHand = evaluateHandOptimal(player.hand, table.wildRank);
      const displayMelds =
        isFinisher && player.openedMelds && player.openedMelds.length > 0
          ? player.openedMelds
          : evalHand.melds;
      const displayUnmelded = isFinisher ? [] : evalHand.unmelded;

      let roundPenalty = 0;
      if (falseDeclarerUserId) {
        // Bir oyuncu hatalı el açtıysa: Sadece hatalı açan oyuncu yanar (101 ceza), diğer oyuncular 0 ceza alır
        roundPenalty = isFalseDeclarer ? 101 : 0;
      } else {
        roundPenalty = isFinisher ? 0 : evalHand.penalty;
      }

      const prevScore = player.totalScore;
      const newTotal = prevScore + roundPenalty;

      player.totalScore = newTotal;
      scoresByUser[player.userId] = roundPenalty;
      totalsByUser[player.userId] = newTotal;

      const burnedThisRound = newTotal >= 101 || isFalseDeclarer;
      if (burnedThisRound) {
        player.isEliminated = true;
      }
      if (isFalseDeclarer) {
        player.forfeitedRebuy = true;
      }

      // Zamanlama:
      // idx === 0 ve leadUserId varsa -> 0ms'de başlar, 10000ms sürer (10 saniye masada görülür)
      // Diğer oyuncular -> 10000ms + (idx - 1) * 3500ms'de sırayla saat yönünde açılır
      const revealStartMs =
        hasLeadShowcase && idx === 0
          ? 0
          : hasLeadShowcase
          ? openerShowcaseMs + (idx - 1) * perOpponentRevealMs
          : idx * perOpponentRevealMs;
      const revealDurationMs = hasLeadShowcase && idx === 0 ? openerShowcaseMs : perOpponentRevealMs;

      showdownResults.push({
        userId: player.userId,
        username: player.username,
        avatar: player.avatar,
        seatIndex: player.seatIndex,
        isFinisher,
        isFalseDeclarer,
        forfeitedRebuy: player.forfeitedRebuy,
        revealOrder: idx,
        revealStartMs,
        revealDurationMs,
        melds: displayMelds,
        unmelded: displayUnmelded,
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
      const eligible = activePlayers.filter((p) => !p.forfeitedRebuy);
      const pool = eligible.length > 0 ? eligible : activePlayers;
      pool.sort((a, b) => a.totalScore - b.totalScore);
      const bestPlayer = pool[0];
      bestPlayer.isEliminated = false;
      survivors.push(bestPlayer);
      const sd = showdownResults.find((s) => s.userId === bestPlayer.userId);
      if (sd) sd.burnedThisRound = false;
    }

    // Kaybetmeyenler arasındaki EN KÖTÜ (en yüksek) puanı bul (Re-buy yapanlar bu puanla girer)
    const worstSurvivorScore =
      survivors.length > 0 ? Math.max(...survivors.map((s) => s.totalScore)) : 0;

    // KURAL: Son 2 oyuncu kaldığında yanan oyuncu geri dönemez!
    // Ayrıca Yardımsız Modda hatalı el açan oyuncu (`forfeitedRebuy = true`) ASLA Re-buy yapamaz!
    const rebuyAllowedInThisRound =
      table.activePlayersAtRoundStart > 2 || survivors.length >= 2;

    let anyAwaitingRebuy = false;
    for (const sd of showdownResults) {
      const seat = table.seats.find((s) => s?.userId === sd.userId);
      if (
        sd.burnedThisRound &&
        rebuyAllowedInThisRound &&
        seat &&
        !seat.forfeitedRebuy
      ) {
        sd.canRebuy = true;
        sd.rebuyTargetScore = worstSurvivorScore;
        seat.awaitingRebuyDecision = true;
        anyAwaitingRebuy = true;
      }
    }

    table.scoreHistory.push({
      roundNumber: table.roundNumber,
      scoresByUser,
      totalsByUser,
      finisherUserId,
      falseDeclarerUserId,
    });

    const othersCount = hasLeadShowcase
      ? Math.max(0, orderedPlayers.length - 1)
      : orderedPlayers.length;
    const totalRevealMs = openerShowcaseMs + othersCount * perOpponentRevealMs;
    const decisionBufferMs = anyAwaitingRebuy ? 10000 : 5000;
    const waitMs = Math.max(12000, totalRevealMs + decisionBufferMs);

    table.status = 'round_summary';
    table.lastShowdown = showdownResults;
    table.lastFinisherUserId = finisherUserId;
    table.lastFalseDeclarerUserId = falseDeclarerUserId;
    table.showdownStartedAt = Date.now();
    table.showdownTotalMs = waitMs;
    table.turnDurationSeconds = Math.ceil(waitMs / 1000);
    table.turnDeadline = Date.now() + waitMs;

    this.io.to(`table:${table.id}`).emit('round_ended', {
      roundNumber: table.roundNumber,
      finisherUserId,
      falseDeclarerUserId,
      showdown: showdownResults,
      openerShowcaseMs,
      perOpponentRevealMs,
      waitMs,
    });

    this.broadcastTableState(table.id);

    table.phaseTimer = setTimeout(() => {
      this.enqueueTableAction(table.id, () => {
        try {
          this.proceedAfterRoundSummary(table);
        } catch (err) {
          console.error('Round summary geçiş hatası:', err);
        }
      });
    }, waitMs);
  }

  /**
   * 101 olup yanan oyuncunun "Yeniden Oyuna Gir (1x, 2x, 3x...)" işlemi
   */
  async rebuyIntoMatch(userId: string, tableId: string): Promise<void> {
    return this.enqueueTableAction(tableId, async () => {
      const table = this.tables.get(tableId);
      if (!table || table.status !== 'round_summary') {
        throw new Error('Şu anda yeniden giriş (re-buy) yapılamaz.');
      }

      const seat = table.seats.find((s) => s?.userId === userId);
      if (!seat || !seat.isEliminated || !seat.awaitingRebuyDecision) {
        throw new Error('Yeniden giriş hakkınız bulunmuyor.');
      }
      if (seat.forfeitedRebuy) {
        throw new Error('Yardımsız modda hatalı el açtığınız için bu oyunda yeniden giriş hakkınızı kaybettiğiniz!');
      }

      // Senkron kilit: Çift tıklama ile çift tahsilatı önle
      seat.awaitingRebuyDecision = false;

      const multiplier = seat.rebuyCount + 1; // 1. giriş: 1x, 2. giriş: 2x, 3. giriş: 3x...
      const cost = multiplier * table.entryFee;

      const survivors = table.seats.filter(
        (s): s is SeatPlayer => s !== null && !s.isEliminated
      );
      const targetScore =
        survivors.length > 0 ? Math.max(...survivors.map((s) => s.totalScore)) : 0;

      try {
        const newBalance = await db.adjustCredits(
          userId,
          -cost,
          'table_rebuy',
          `${table.name} masası ${multiplier}x yeniden oyuna giriş (Re-buy)`
        );
        this.emitBalanceUpdate(userId, newBalance);
      } catch (err) {
        seat.awaitingRebuyDecision = true;
        throw err;
      }

      table.pot += cost;
      table.matchContributions[userId] = (table.matchContributions[userId] || 0) + cost;
      seat.rebuyCount += 1;
      seat.totalScore = targetScore;
      seat.isEliminated = false;

      try {
        await db.upsertMatchEscrow(table.id, table.name, table.pot, table.matchContributions);
      } catch (err) {
        console.error('Rebuy escrow güncelleme hatası:', err);
      }

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
    });
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
   * Oyun sonu: Kasa %5 komisyon alır, %95 kazanan oyuncuya atomik işlemle aktarılır!
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
    table.matchContributions = {};

    for (const s of table.seats) {
      if (s) {
        s.isReady = false;
        // Bağlantısı kopmuş olan oyuncuları maç bittiğinde koltuktan temizle
        if (!s.isConnected) {
          table.seats[s.seatIndex] = null;
        }
      }
    }

    if (winner && totalPot > 0) {
      try {
        const newBal = await db.settleMatchVictory(
          table.id,
          winner.userId,
          prizeWon,
          houseRake,
          `${table.name} masası şampiyonluk ödülü (%95 Pot)`
        );
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
    } else {
      await db.clearMatchEscrow(table.id);
    }

    const deleted = this.cleanupTableIfEmpty(table.id);
    if (!deleted) {
      this.broadcastTableState(table.id);
    }
    this.broadcastLobbyTables();
  }

  /**
   * Oyuncunun elindeki kağıtları tüm 3 sıra genelinde tek bir bütün olarak Sayıya Göre (A..K)
   * veya Renge Göre (♠, ♥, ♣, ♦) akıllıca 3 sıraya böler.
   */
  private distributeSortedCardsIntoRows(cards: Card[], mode: 'rank' | 'suit'): string[][] {
    if (cards.length === 0) return [[], [], []];

    if (mode === 'rank') {
      // Sayıya göre sıralı kağıtlarda aynı sayılı grupları (çift/üçlü) mümkün olduğunca aynı satırda tutarak 3 sıraya dağıt
      const groups: Card[][] = [];
      for (const c of cards) {
        const keyRank = c.isPhysicalJoker ? 99 : c.rank;
        const lastGroup = groups[groups.length - 1];
        const lastRank =
          lastGroup && lastGroup.length > 0
            ? lastGroup[0].isPhysicalJoker
              ? 99
              : lastGroup[0].rank
            : -1;
        if (lastGroup && lastRank === keyRank) {
          lastGroup.push(c);
        } else {
          groups.push([c]);
        }
      }

      const rows: string[][] = [[], [], []];
      const targets = cards.length === 11 ? [4, 4, 3] : [4, 3, 3];
      let currentRow = 0;

      for (const g of groups) {
        if (
          currentRow < 2 &&
          rows[currentRow].length > 0 &&
          rows[currentRow].length + g.length > targets[currentRow] + 1
        ) {
          currentRow++;
        }
        for (const c of g) {
          if (currentRow < 2 && rows[currentRow].length >= targets[currentRow] && g.length === 1) {
            currentRow++;
          }
          rows[currentRow].push(c.id);
        }
      }
      return rows;
    } else {
      // Renge göre sıralı kağıtlarda aynı rengi kendi satırında tutmaya çalışarak 3 sıraya dağıt
      const rows: string[][] = [[], [], []];
      const targets = cards.length === 11 ? [4, 4, 3] : [4, 3, 3];
      let idx = 0;
      for (let r = 0; r < 3; r++) {
        const count = targets[r];
        rows[r] = cards.slice(idx, idx + count).map((c) => c.id);
        idx += count;
      }
      return rows;
    }
  }

  /**
   * Oyuncunun elindeki kağıtları kendi istediği sıraya (veya 3 sıraya) dizmesi
   */
  reorderPlayerHand(
    userId: string,
    tableId: string,
    orderedCardIds?: string[],
    rowCardIds?: string[][]
  ) {
    const table = this.tables.get(tableId);
    if (!table) return;
    const seat = table.seats.find((s) => s?.userId === userId);
    if (!seat || seat.hand.length === 0) return;

    if (rowCardIds && Array.isArray(rowCardIds) && rowCardIds.length === 3) {
      seat.handRows = rowCardIds;
      this.syncSeatHandRows(seat);
      const flatIds = seat.handRows.flat();
      const map = new Map(seat.hand.map((c) => [c.id, c]));
      const reordered: Card[] = [];
      for (const id of flatIds) {
        const c = map.get(id);
        if (c) {
          reordered.push(c);
          map.delete(id);
        }
      }
      for (const c of map.values()) reordered.push(c);
      seat.hand = reordered;
    } else if (!orderedCardIds || orderedCardIds.length === 0) {
      if (!table.isAssisted) {
        // Yardımsız modda tüm 10/11 kağıdı TEK BİR BÜTÜN olarak Sayıya Göre (1..13, Joker) sırala!
        // Kullanıcı tekrar basarsa Renk/Seri dizilimi ile Sayı dizilimi arasında geçiş yapar.
        const suitOrder: Record<string, number> = { S: 1, H: 2, C: 3, D: 4, J: 5 };
        const mode: 'rank' | 'suit' = seat.sortMode === 'rank' ? 'rank' : 'suit';
        seat.sortMode = mode === 'rank' ? 'suit' : 'rank';

        if (mode === 'rank') {
          seat.hand.sort((a, b) => {
            const rA = a.isPhysicalJoker ? 99 : a.rank;
            const rB = b.isPhysicalJoker ? 99 : b.rank;
            if (rA !== rB) return rA - rB;
            return suitOrder[a.suit] - suitOrder[b.suit];
          });
        } else {
          seat.hand.sort((a, b) => {
            if (suitOrder[a.suit] !== suitOrder[b.suit]) {
              return suitOrder[a.suit] - suitOrder[b.suit];
            }
            return a.rank - b.rank;
          });
        }
        seat.handRows = this.distributeSortedCardsIntoRows(seat.hand, mode);
        this.syncSeatHandRows(seat);
      } else {
        // Yardımlı modda Otomatik Per Diz:
        // Eğer 11 kağıt varsa ve 10 kağıtla el açılabiliyorsa (ör. 2♠-Joker-Joker-5♠ + Papaz),
        // doğrudan o 10 kağıdın perlerini 3 sıraya diz ve atılacak 11. kağıdı (Papaz) 3. sıranın sonuna koy!
        if (seat.hand.length === 11) {
          const winCheck = findWinningDiscard(seat.hand, table.wildRank, seat.handRows);
          if (winCheck.canWin && winCheck.discardCard && winCheck.evaluation) {
            const melds = winCheck.evaluation.melds;
            const discard = winCheck.discardCard;
            seat.hand = [...winCheck.evaluation.orderedCards, discard];
            const newRows: string[][] = [[], [], []];
            melds.forEach((meld, idx) => {
              const targetRow = Math.min(2, idx);
              newRows[targetRow].push(...meld.map((c) => c.id));
            });
            newRows[2].push(discard.id);
            seat.handRows = newRows;
            this.syncSeatHandRows(seat);
            this.sendTableStateToUser(table, userId);
            return;
          }
        }

        const evalHand = evaluateHandOptimal(seat.hand, table.wildRank);
        seat.hand = evalHand.orderedCards;
        const newRows: string[][] = [[], [], []];
        evalHand.melds.forEach((meld, idx) => {
          const targetRow = Math.min(2, idx);
          newRows[targetRow].push(...meld.map((c) => c.id));
        });
        for (const u of evalHand.unmelded) {
          newRows[2].push(u.id);
        }
        seat.handRows = newRows;
        this.syncSeatHandRows(seat);
      }
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
      this.syncSeatHandRows(seat);
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
    if (!this.isUserInTable(senderId, tableId)) {
      throw new Error('Bu masada değilsiniz.');
    }

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

  emitBalanceUpdate(userId: string, credits: number) {
    this.io.to(`user:${userId}`).emit('balance_updated', { credits });
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
    const sockets = this.userSockets.get(viewerUserId);
    if (!sockets || sockets.size === 0) return;

    const viewerSeat = table.seats.find((s) => s?.userId === viewerUserId);
    let viewerEvaluation = null;

    if (viewerSeat && viewerSeat.hand.length > 0) {
      this.syncSeatHandRows(viewerSeat);
      if (table.isAssisted) {
        // Sadece Yardımlı Modda otomatik per ve ceza ipuçlarını gönder
        const evalRes = evaluateHandOptimal(viewerSeat.hand, table.wildRank);
        const meldedIds = new Set(evalRes.melds.flat().map((c) => c.id));
        let canFinishNow = evalRes.canFinish;
        let winningDiscardCardId: string | null = null;
        let displayPenalty = evalRes.penalty;

        if (viewerSeat.hand.length === 11) {
          const winCheck = findWinningDiscard(
            viewerSeat.hand,
            table.wildRank,
            viewerSeat.handRows
          );
          if (winCheck.canWin && winCheck.discardCard && winCheck.evaluation) {
            canFinishNow = true;
            winningDiscardCardId = winCheck.discardCard.id;
            displayPenalty = 0;
            meldedIds.clear();
            for (const c of winCheck.evaluation.melds.flat()) {
              meldedIds.add(c.id);
            }
          }
        }

        viewerEvaluation = {
          canFinish: canFinishNow,
          winningDiscardCardId,
          penalty: displayPenalty,
          meldedCardIds: Array.from(meldedIds),
        };
      } else {
        // Yardımsız (Usta) Modda ipucu verilmez; ancak oyuncu 3 sırada geçerli bir el dizdiyse
        // dışarıda kalan 11. kağıdı (`winningDiscardCardId`) el açarken kullanabilmek üzere belirle
        let candidateDiscardId: string | null = null;
        if (viewerSeat.hand.length === 11) {
          const rowWin = evaluatePlayerRowsForFinish(
            viewerSeat.hand,
            viewerSeat.handRows,
            table.wildRank
          );
          if (rowWin.canWinFromRows && rowWin.discardCard) {
            candidateDiscardId = rowWin.discardCard.id;
          }
        }
        viewerEvaluation = {
          canFinish: viewerSeat.hand.length === 11,
          winningDiscardCardId: candidateDiscardId,
          penalty: -1,
          meldedCardIds: [],
        };
      }
    }

    const payload = {
      id: table.id,
      name: table.name,
      hostUserId: table.hostUserId,
      hostUsername: table.hostUsername,
      minPlayers: table.minPlayers,
      maxPlayers: table.maxPlayers,
      entryFee: table.entryFee,
      isAssisted: table.isAssisted,
      status: table.status === 'starting' ? 'playing' : table.status,
      pot: table.pot,
      roundNumber: table.roundNumber,
      drawPileCount: table.drawPile.length,
      topDiscardCard:
        table.discardPile.length > 0
          ? table.discardPile[table.discardPile.length - 1]
          : null,
      discardHistory: table.discardPile.slice(-12),
      indicatorCard: table.indicatorCard,
      wildRank: table.wildRank,
      currentTurnSeat: table.currentTurnSeat,
      dealerSeat: table.dealerSeat,
      hasDrawnThisTurn: table.hasDrawnThisTurn,
      turnRemainingSeconds: Math.max(
        0,
        Math.ceil((table.turnDeadline - Date.now()) / 1000)
      ),
      turnDurationSeconds: table.turnDurationSeconds,
      matchElapsedSeconds:
        table.matchStartedAt > 0
          ? Math.max(0, Math.floor((Date.now() - table.matchStartedAt) / 1000))
          : 0,
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
          forfeitedRebuy: s.forfeitedRebuy,
          rebuyCount: s.rebuyCount,
          awaitingRebuyDecision: s.awaitingRebuyDecision,
          cardCount: s.hand.length,
        };
      }),
      myHand: viewerSeat ? viewerSeat.hand : [],
      myHandRows: viewerSeat ? viewerSeat.handRows || [[], [], []] : [[], [], []],
      myEvaluation: viewerEvaluation,
      lastShowdown: table.lastShowdown,
      lastFinisherUserId: table.lastFinisherUserId,
      lastFalseDeclarerUserId: table.lastFalseDeclarerUserId,
      showdownElapsedMs:
        table.status === 'round_summary' && table.showdownStartedAt > 0
          ? Math.max(0, Date.now() - table.showdownStartedAt)
          : 0,
      showdownTotalMs: table.showdownTotalMs,
      scoreHistory: table.scoreHistory,
      lastWinnerInfo: table.lastWinnerInfo,
    };

    this.io.to(`user:${viewerUserId}`).emit('table_state', payload);
  }
}
