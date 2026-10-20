import express, { Request, Response, NextFunction } from 'express';
import http from 'http';
import cors from 'cors';
import { Server } from 'socket.io';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import dotenv from 'dotenv';
import { db } from './db';
import { TableManager } from './engine/tableManager';

dotenv.config();

const PORT = Number(process.env.PORT || 4545);
const JWT_SECRET = process.env.JWT_SECRET || 'YunanYanikSuperSecretJwtKey2026!';

interface JwtPayload {
  userId: string;
  username: string;
  role: 'admin' | 'player';
}

const app = express();
app.use(cors());
app.use(express.json({ limit: '5mb' }));

const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST'],
  },
  maxHttpBufferSize: 2e6, // Sesli sohbet paketleri için güvenli 2MB limit
});

const tableManager = new TableManager(io);

// Basit hız sınırlayıcı (Rate Limiter: userId:event -> son gönderim zamanı)
const rateLimits = new Map<string, number>();
function checkRateLimit(userId: string, action: string, minIntervalMs: number): boolean {
  const key = `${userId}:${action}`;
  const now = Date.now();
  const last = rateLimits.get(key) || 0;
  if (now - last < minIntervalMs) {
    return false;
  }
  rateLimits.set(key, now);
  return true;
}

// 🛡️ Argo & Küfür Filtresi (Kök ve Kelime Eşleşmeli)
const PROFANITY_ROOTS = [
  'amk', 'aq', 'oç', 'oc', 'piç', 'pic', 'siktir', 'sik', 'sikerim', 'orospu', 
  'göt', 'got', 'yarak', 'yarrak', 'ibne', 'kahpe', 'puşt', 'pust', 'pezevenk',
  'amcık', 'amcik', 'yarram', 'taşak', 'tasak', 'fahişe', 'fahise', 'orospuçocuğu',
  'sikik', 'sürtük', 'surtuk', 'mal', 'salak', 'aptal', 'şerefsiz', 'serefsiz'
];

function filterProfanity(text: string): string {
  let cleaned = text;
  for (const word of PROFANITY_ROOTS) {
    const escaped = word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const regex = new RegExp(`\\b${escaped}\\b`, 'gi');
    cleaned = cleaned.replace(regex, '***');
  }
  return cleaned;
}

// Auth Middleware
async function requireAuth(req: Request, res: Response, next: NextFunction) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Oturum açmanız gerekiyor.' });
  }
  const token = authHeader.slice(7);
  try {
    const decoded = jwt.verify(token, JWT_SECRET) as JwtPayload;
    const dbUser = await db.getUserById(decoded.userId);
    if (!dbUser || dbUser.is_banned) {
      return res.status(403).json({ error: 'Hesabınız askıya alınmıştır.' });
    }
    (req as any).user = decoded;
    next();
  } catch {
    return res.status(401).json({ error: 'Geçersiz veya süresi dolmuş oturum.' });
  }
}

function requireAdmin(req: Request, res: Response, next: NextFunction) {
  requireAuth(req, res, () => {
    const user = (req as any).user as JwtPayload;
    if (user.role !== 'admin') {
      return res.status(403).json({ error: 'Bu işlem için Admin yetkisi gereklidir.' });
    }
    next();
  });
}

// Health check
app.get('/api/health', (_req, res) => {
  res.json({
    status: 'ok',
    game: 'Yanık İskambil HD Server',
    timestamp: new Date().toISOString(),
  });
});

// Kullanıcı Girişi (Kullanıcı Adı & Şifre)
app.post('/api/auth/login', async (req, res) => {
  try {
    const { username, password } = req.body;
    if (!username || !password) {
      return res.status(400).json({ error: 'Kullanıcı adı ve şifre zorunludur.' });
    }

    const user = await db.getUserByUsername(String(username));
    if (!user) {
      return res.status(401).json({ error: 'Kullanıcı adı veya şifre hatalı.' });
    }

    if (user.is_banned) {
      return res.status(403).json({ error: 'Hesabınız yönetici tarafından askıya alınmıştır.' });
    }

    const valid = await bcrypt.compare(String(password), user.password_hash);
    if (!valid) {
      return res.status(401).json({ error: 'Kullanıcı adı veya şifre hatalı.' });
    }

    const token = jwt.sign(
      { userId: user.id, username: user.username, role: user.role } as JwtPayload,
      JWT_SECRET,
      { expiresIn: '30d' }
    );

    const vault = await db.getVaultSummary();

    res.json({
      token,
      user: {
        id: user.id,
        username: user.username,
        role: user.role,
        credits: user.credits,
        avatar: user.avatar,
      },
      emojiCost: vault.emoji_cost,
      activeTableId: tableManager.findUserActiveTableId(user.id),
    });
  } catch (err: any) {
    res.status(500).json({ error: err.message || 'Sunucu hatası.' });
  }
});

// Profil Bilgisi (JWT ile otomatik oturum yenileme)
app.get('/api/auth/me', requireAuth, async (req, res) => {
  try {
    const jwtUser = (req as any).user as JwtPayload;
    const user = await db.getUserById(jwtUser.userId);
    if (!user) return res.status(404).json({ error: 'Kullanıcı bulunamadı.' });
    const vault = await db.getVaultSummary();

    res.json({
      user: {
        id: user.id,
        username: user.username,
        role: user.role,
        credits: user.credits,
        avatar: user.avatar,
      },
      emojiCost: vault.emoji_cost,
      activeTableId: tableManager.findUserActiveTableId(user.id),
    });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// VIP Avatar Değiştirme
app.post('/api/profile/avatar', requireAuth, async (req, res) => {
  try {
    const jwtUser = (req as any).user as JwtPayload;
    const { avatar } = req.body;
    const allowed = ['lion', 'king', 'queen', 'wolf', 'boss', 'joker'];
    const chosen = allowed.includes(avatar) ? avatar : 'lion';
    await db.updateUserAvatar(jwtUser.userId, chosen);
    res.json({ success: true, avatar: chosen });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// Oyuncu Kendi Oyun ve Kredi Hareketleri Geçmişi
app.get('/api/profile/history', requireAuth, async (req, res) => {
  try {
    const jwtUser = (req as any).user as JwtPayload;
    const transactions = await db.getUserTransactions(jwtUser.userId, 80);
    const totalWins = transactions.filter((t) => t.type === 'table_win').length;
    const totalEntries = transactions.filter((t) => t.type === 'table_entry').length;
    const totalWonCredits = transactions
      .filter((t) => t.type === 'table_win')
      .reduce((acc, t) => acc + t.amount, 0);

    res.json({
      transactions,
      stats: {
        totalGames: totalEntries,
        totalWins,
        totalWonCredits,
      },
    });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// ==========================================
// 👥 GERÇEK ARKADAŞLAR VE ÇEVRİMİÇİ KULLANICILAR API
// ==========================================

// Kullanıcı Arama
app.get('/api/users/search', requireAuth, async (req, res) => {
  try {
    const q = String(req.query.q || '').trim();
    if (!q) return res.json({ users: [] });
    const users = await db.searchUsers(q, (req as any).user.userId);
    const withOnline = users.map((u) => ({
      ...u,
      is_online: tableManager.isUserOnline(u.id),
    }));
    res.json({ users: withOnline });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// Arkadaş Listesi
app.get('/api/friends', requireAuth, async (req, res) => {
  try {
    const userId = (req as any).user.userId;
    const [friends, sentUserIds] = await Promise.all([
      db.getFriends(userId),
      db.getSentFriendRequestUserIds(userId),
    ]);
    const withOnline = friends.map((f) => ({
      ...f,
      is_online: tableManager.isUserOnline(f.id),
    }));
    res.json({ friends: withOnline, sentRequestUserIds: sentUserIds });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// Arkadaşlık İstekleri Listesi (Gelen bekleyen istekler)
app.get('/api/friends/requests', requireAuth, async (req, res) => {
  try {
    const userId = (req as any).user.userId;
    const requests = await db.getPendingFriendRequests(userId);
    res.json({ requests });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// Arkadaşlık İsteği Gönderme
app.post('/api/friends/request', requireAuth, async (req, res) => {
  try {
    const userId = (req as any).user.userId;
    const username = String(req.body.username || '').trim();
    if (!username) {
      return res.status(400).json({ error: 'Kullanıcı adı belirtilmelidir.' });
    }
    const result = await db.sendFriendRequest(userId, username);

    // Alıcı online ise gerçek zamanlı soket bildirimi gönder
    io.to(`user:${result.receiver.id}`).emit('notification_received', {
      type: 'friend_request',
      title: 'Yeni Arkadaşlık İsteği',
      message: `${(req as any).user.username || 'Bir oyuncu'} sana arkadaşlık isteği gönderdi.`,
      requestId: result.requestId,
    });
    io.to(`user:${result.receiver.id}`).emit('friend_request_received', {
      requestId: result.requestId,
      sender: {
        id: userId,
        username: (req as any).user.username,
      },
    });

    if (result.status === 'auto_accepted') {
      io.to(`user:${userId}`).emit('friend_added', { friend: result.receiver });
      io.to(`user:${result.receiver.id}`).emit('friend_added', {
        friend: { id: userId, username: (req as any).user.username },
      });
    }

    res.json({
      success: true,
      status: result.status,
      receiver: result.receiver,
      message:
        result.status === 'auto_accepted'
          ? `'${result.receiver.username}' ile karşılıklı arkadaş oldunuz!`
          : `'${result.receiver.username}' kullanıcısına arkadaşlık isteği gönderildi.`,
    });
  } catch (err: any) {
    res.status(400).json({ error: err.message });
  }
});

// Arkadaşlık İsteğine Yanıt Verme (Kabul / Red)
app.post('/api/friends/respond', requireAuth, async (req, res) => {
  try {
    const userId = (req as any).user.userId;
    const { requestId, accept } = req.body;
    if (!requestId) {
      return res.status(400).json({ error: 'İstek ID belirtilmelidir.' });
    }
    const result = await db.respondFriendRequest(requestId, userId, Boolean(accept));

    if (accept && result.senderId) {
      // Her iki tarafa arkadaş eklendi olayını bildir
      io.to(`user:${userId}`).emit('friend_added', {
        friend: { id: result.senderId, username: result.senderUsername },
      });
      io.to(`user:${result.senderId}`).emit('friend_added', {
        friend: { id: userId, username: (req as any).user.username },
      });
      io.to(`user:${result.senderId}`).emit('notification_received', {
        type: 'friend_accepted',
        title: 'Arkadaşlık Kabul Edildi',
        message: `${(req as any).user.username || 'Oyuncu'} arkadaşlık isteğinizi kabul etti!`,
      });
    }

    res.json({ success: true, accepted: Boolean(accept) });
  } catch (err: any) {
    res.status(400).json({ error: err.message });
  }
});

// Bildirim Listesi
app.get('/api/notifications', requireAuth, async (req, res) => {
  try {
    const userId = (req as any).user.userId;
    const notifications = await db.getNotifications(userId);
    res.json({ notifications });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// Bildirimi Okundu Olarak İşaretle
app.post('/api/notifications/read', requireAuth, async (req, res) => {
  try {
    const userId = (req as any).user.userId;
    const { id } = req.body;
    if (id) {
      await db.markNotificationRead(id, userId);
    } else {
      await db.markAllNotificationsRead(userId);
    }
    res.json({ success: true });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// Eski addFriend route geriye dönük uyumluluk için (doğrudan istek gönderir)
app.post('/api/friends/add', requireAuth, async (req, res) => {
  try {
    const userId = (req as any).user.userId;
    const username = String(req.body.username || '').trim();
    if (!username) {
      return res.status(400).json({ error: 'Kullanıcı adı belirtilmelidir.' });
    }
    const result = await db.sendFriendRequest(userId, username);
    res.json({ success: true, ...result });
  } catch (err: any) {
    res.status(400).json({ error: err.message });
  }
});

// Çevrimiçi Kullanıcılar
app.get('/api/users/online', requireAuth, async (req, res) => {
  try {
    const onlineIds = tableManager.getOnlineUserIds((req as any).user.userId);
    const users = await db.getUsersByIds(onlineIds);
    res.json({ users: users.map((u) => ({ ...u, is_online: true })) });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// ==========================================
// 👑 UYGULAMA İÇİ ADMİN PANELİ ENDPOINTLERİ
// ==========================================

app.get('/api/admin/dashboard', requireAdmin, async (_req, res) => {
  try {
    const [users, vault, transactions] = await Promise.all([
      db.getAllUsers(),
      db.getVaultSummary(),
      db.getRecentTransactions(100),
    ]);
    const tables = tableManager.getLobbyTablesSummary();
    res.json({
      users,
      vault,
      transactions,
      tables,
    });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// Yeni Oyuncu Oluşturma
app.post('/api/admin/users', requireAdmin, async (req, res) => {
  try {
    const { username, password, initialCredits, role, avatar } = req.body;
    if (!username || !password) {
      return res.status(400).json({ error: 'Kullanıcı adı ve şifre zorunludur.' });
    }
    const created = await db.createUser(
      String(username),
      String(password),
      role === 'admin' ? 'admin' : 'player',
      Number(initialCredits || 0),
      avatar || 'lion'
    );
    const { password_hash, ...safeUser } = created;
    res.json({ user: safeUser });
  } catch (err: any) {
    res.status(400).json({ error: err.message });
  }
});

// Oyuncuya Sanal Kredi Yükleme / Silme
app.post('/api/admin/users/:id/credits', requireAdmin, async (req, res) => {
  try {
    const targetUserId = req.params.id;
    const { amount, description } = req.body;
    const numAmount = Number(amount);
    if (!numAmount || isNaN(numAmount)) {
      return res.status(400).json({ error: 'Geçerli bir kredi miktarı giriniz.' });
    }

    const type = numAmount > 0 ? 'admin_add' : 'admin_deduct';
    const desc =
      description?.trim() ||
      (numAmount > 0 ? 'Admin tarafından kredi yüklendi' : 'Admin tarafından kredi düşüldü');

    const newCredits = await db.adjustCredits(targetUserId, numAmount, type, desc);

    // SADECE ilgili oyuncunun özel odasına bakiye senkronizasyonu gönder (Gizlilik)
    io.to(`user:${targetUserId}`).emit('user_credit_sync', {
      userId: targetUserId,
      credits: newCredits,
    });
    tableManager.emitBalanceUpdate(targetUserId, newCredits);

    res.json({ success: true, credits: newCredits });
  } catch (err: any) {
    res.status(400).json({ error: err.message });
  }
});

// Oyuncu Şifresi Sıfırlama
app.post('/api/admin/users/:id/password', requireAdmin, async (req, res) => {
  try {
    const { newPassword } = req.body;
    if (!newPassword || String(newPassword).length < 4) {
      return res.status(400).json({ error: 'Şifre en az 4 karakter olmalıdır.' });
    }
    await db.updateUserPassword(req.params.id, String(newPassword));
    res.json({ success: true });
  } catch (err: any) {
    res.status(400).json({ error: err.message });
  }
});

// Oyuncu Banla / Ban Kaldır
app.post('/api/admin/users/:id/ban', requireAdmin, async (req, res) => {
  try {
    const { isBanned } = req.body;
    const banned = Boolean(isBanned);
    await db.setUserBanStatus(req.params.id, banned);
    if (banned) {
      tableManager.disconnectUserSockets(req.params.id);
    }
    res.json({ success: true, is_banned: banned });
  } catch (err: any) {
    res.status(400).json({ error: err.message });
  }
});

// Masa İçi Emoji/Efekt Kredi Ücretini Güncelle
app.post('/api/admin/settings/emoji-cost', requireAdmin, async (req, res) => {
  try {
    const { emojiCost } = req.body;
    await db.setEmojiCost(Number(emojiCost || 0));
    const vault = await db.getVaultSummary();
    io.emit('emoji_cost_updated', { emojiCost: vault.emoji_cost });
    res.json({ success: true, emojiCost: vault.emoji_cost });
  } catch (err: any) {
    res.status(400).json({ error: err.message });
  }
});

// Admin Masa Kapatma (Aktif pot varsa otomatik iade eder)
app.delete('/api/admin/tables/:id', requireAdmin, async (req, res) => {
  try {
    const closed = await tableManager.closeTableByAdmin(req.params.id);
    res.json({ success: closed });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// ==========================================
// ⚡ SOCKET.IO GERÇEK ZAMANLI OYUN İLETİŞİMİ
// ==========================================

io.use(async (socket, next) => {
  const token = socket.handshake.auth?.token || socket.handshake.query?.token;
  if (!token) {
    return next(new Error('Oturum anahtarı eksik.'));
  }
  try {
    const decoded = jwt.verify(String(token), JWT_SECRET) as JwtPayload;
    const dbUser = await db.getUserById(decoded.userId);
    if (!dbUser || dbUser.is_banned) {
      return next(new Error('Hesabınız askıya alınmıştır.'));
    }
    (socket as any).user = decoded;
    next();
  } catch {
    next(new Error('Geçersiz oturum anahtarı.'));
  }
});

io.on('connection', (socket) => {
  const user = (socket as any).user as JwtPayload;
  tableManager.registerUserSocket(socket, user.userId);

  // İlk bağlantıda lobi masalarını gönder
  socket.emit('lobby_tables', tableManager.getLobbyTablesSummary());

  socket.on('get_lobby_tables', () => {
    socket.emit('lobby_tables', tableManager.getLobbyTablesSummary());
  });

  // Hızlı Oyun: Tek tıkla 4 kişilik masada 3 bot ile anında oyuna başlama
  socket.on('create_quick_match', async (_data, cb) => {
    try {
      const dbUser = await db.getUserById(user.userId);
      if (!dbUser) throw new Error('Kullanıcı bulunamadı.');
      const entryFee = 100;
      if (dbUser.credits < entryFee) {
        throw new Error(`Oyuna başlamak için en az ${entryFee} krediniz olmalıdır.`);
      }
      const table = tableManager.createQuickMatchWithBots(
        dbUser.id,
        dbUser.username,
        dbUser.avatar,
        entryFee
      );
      tableManager.joinTableRoom(socket, dbUser.id, table.id);
      if (cb) cb({ ok: true, tableId: table.id });
    } catch (err: any) {
      if (cb) cb({ ok: false, error: err.message });
      else socket.emit('error_msg', err.message);
    }
  });

  // Yeni Oyun Odası Açma (Min 2, Maks 6 Kişilik + Giriş Kredisi + Yardımlı/Yardımsız Mod + Oynama Bekleme Süresi)
  socket.on('create_table', async (data, cb) => {
    try {
      const dbUser = await db.getUserById(user.userId);
      if (!dbUser) throw new Error('Kullanıcı bulunamadı.');
      const entryFee = Math.max(10, Number(data?.entryFee || 100));
      if (dbUser.credits < entryFee) {
        throw new Error(`Bu odayı açmak için en az ${entryFee} krediniz olmalıdır.`);
      }
      const isAssisted = data?.isAssisted !== undefined ? Boolean(data.isAssisted) : true;
      const turnDuration = [15, 30, 45].includes(Number(data?.turnDurationSeconds))
        ? Number(data.turnDurationSeconds)
        : 30;
      const table = tableManager.createTable(
        String(data?.name || `${dbUser.username} Odası`),
        dbUser.id,
        dbUser.username,
        Number(data?.maxPlayers || 4),
        entryFee,
        isAssisted,
        turnDuration
      );
      if (cb) cb({ ok: true, tableId: table.id });
    } catch (err: any) {
      if (cb) cb({ ok: false, error: err.message });
      else socket.emit('error_msg', err.message);
    }
  });

  // Test İçin Odaya Bot Oyuncu Ekleme
  socket.on('add_bot', (data, cb) => {
    try {
      tableManager.addBotToTable(user.userId, String(data?.tableId));
      if (cb) cb({ ok: true });
    } catch (err: any) {
      if (cb) cb({ ok: false, error: err.message });
      else socket.emit('error_msg', err.message);
    }
  });

  // Odadan Bot Oyuncuyu Çıkarma
  socket.on('remove_bot', (data, cb) => {
    try {
      tableManager.removeBotFromTable(
        user.userId,
        String(data?.tableId),
        Number(data?.seatIndex)
      );
      if (cb) cb({ ok: true });
    } catch (err: any) {
      if (cb) cb({ ok: false, error: err.message });
      else socket.emit('error_msg', err.message);
    }
  });

  // Oda Kurucusunun Oyunu Başlatması (En az 2 hazır oyuncu ile)
  socket.on('start_game', async (data, cb) => {
    try {
      await tableManager.forceStartByHost(user.userId, String(data?.tableId));
      if (cb) cb({ ok: true });
    } catch (err: any) {
      if (cb) cb({ ok: false, error: err.message });
      else socket.emit('error_msg', err.message);
    }
  });

  // Odaya Giriş (Gezinme / İzleme)
  socket.on('join_table', (data) => {
    if (data?.tableId) {
      tableManager.joinTableRoom(socket, user.userId, String(data.tableId));
    }
  });

  // Odadan Çıkış
  socket.on('leave_table', (data) => {
    if (data?.tableId) {
      tableManager.leaveTableRoom(socket, user.userId, String(data.tableId));
    }
  });

  // Masayı Tamamen Terk Et (Oyundan Çekil / Masadan Çık)
  socket.on('forfeit_match', async (data, cb) => {
    try {
      if (data?.tableId) {
        socket.leave(`table:${data.tableId}`);
        await tableManager.forfeitAndLeaveTable(user.userId, String(data.tableId));
      }
      if (cb) cb({ ok: true });
    } catch (err: any) {
      if (cb) cb({ ok: false, error: err.message });
      else socket.emit('error_msg', err.message);
    }
  });

  // Koltuk Seçimi
  socket.on('sit_seat', async (data, cb) => {
    try {
      await tableManager.sitAtSeat(
        user.userId,
        String(data?.tableId),
        Number(data?.seatIndex)
      );
      if (cb) cb({ ok: true });
    } catch (err: any) {
      if (cb) cb({ ok: false, error: err.message });
      else socket.emit('error_msg', err.message);
    }
  });

  // Koltuktan Kalkma
  socket.on('stand_up', async (data, cb) => {
    try {
      await tableManager.standUpFromSeat(user.userId, String(data?.tableId));
      if (cb) cb({ ok: true });
    } catch (err: any) {
      if (cb) cb({ ok: false, error: err.message });
      else socket.emit('error_msg', err.message);
    }
  });

  // Oyuna Başla / Hazır
  socket.on('toggle_ready', async (data, cb) => {
    try {
      await tableManager.toggleReady(user.userId, String(data?.tableId));
      if (cb) cb({ ok: true });
    } catch (err: any) {
      if (cb) cb({ ok: false, error: err.message });
      else socket.emit('error_msg', err.message);
    }
  });

  // Ortadaki Desteden Kağıt Çekme
  socket.on('draw_card', async (data, cb) => {
    try {
      await tableManager.drawFromDeck(user.userId, String(data?.tableId));
      if (cb) cb({ ok: true });
    } catch (err: any) {
      if (cb) cb({ ok: false, error: err.message });
      else socket.emit('error_msg', err.message);
    }
  });

  // Yere Kağıt Atma
  socket.on('discard_card', async (data, cb) => {
    try {
      await tableManager.discardCard(
        user.userId,
        String(data?.tableId),
        String(data?.cardId)
      );
      if (cb) cb({ ok: true });
    } catch (err: any) {
      if (cb) cb({ ok: false, error: err.message });
      else socket.emit('error_msg', err.message);
    }
  });

  // El Aç / Bitir (Yardımlı ve Yardımsız Mod destekli)
  socket.on('declare_finish', async (data, cb) => {
    try {
      await tableManager.declareFinish(
        user.userId,
        String(data?.tableId),
        data?.discardCardId ? String(data.discardCardId) : undefined,
        Array.isArray(data?.rowCardIds) ? data.rowCardIds : undefined
      );
      if (cb) cb({ ok: true });
    } catch (err: any) {
      if (cb) cb({ ok: false, error: err.message });
      else socket.emit('error_msg', err.message);
    }
  });

  // Eldeki Kağıtları Sıralama / 3 Sıralı Istaka Dizilimi
  socket.on('reorder_hand', (data) => {
    tableManager.reorderPlayerHand(
      user.userId,
      String(data?.tableId),
      Array.isArray(data?.orderedCardIds) ? data.orderedCardIds : undefined,
      Array.isArray(data?.rowCardIds) ? data.rowCardIds : undefined
    );
  });

  // 101 Olup Yanan Oyuncunun Yeniden Girişi (Re-buy: 1x, 2x, 3x...)
  socket.on('rebuy', async (data, cb) => {
    try {
      await tableManager.rebuyIntoMatch(user.userId, String(data?.tableId));
      if (cb) cb({ ok: true });
    } catch (err: any) {
      if (cb) cb({ ok: false, error: err.message });
      else socket.emit('error_msg', err.message);
    }
  });

  // Tur Bitiminde "Devam Et" Oyu
  socket.on('vote_continue_round', async (data, cb) => {
    try {
      await tableManager.voteContinue(user.userId, String(data?.tableId));
      if (cb) cb({ ok: true });
    } catch (err: any) {
      if (cb) cb({ ok: false, error: err.message });
      else socket.emit('error_msg', err.message);
    }
  });

  // Oda İçi Yazılı Sohbet (Oda üyeliği + Karakter sınırı + Argo filtresi + Rate limit korumalı)
  socket.on('send_chat', async (data) => {
    const tableId = String(data?.tableId || '');
    const rawText = String(data?.message || '').trim().slice(0, 80); // Maksimum 80 karakter
    if (!tableId || !rawText) return;
    if (!tableManager.isUserInTable(user.userId, tableId)) return;
    if (!checkRateLimit(user.userId, 'chat', 700)) return;

    const filteredText = filterProfanity(rawText);

    const dbUser = await db.getUserById(user.userId);
    io.to(`table:${tableId}`).emit('chat_message', {
      id: Date.now().toString(),
      userId: user.userId,
      username: dbUser?.username || user.username,
      avatar: dbUser?.avatar || 'lion',
      message: filteredText,
      timestamp: new Date().toISOString(),
    });
  });

  // Masa İçi Ücretli Emoji / Efekt Gönderimi (Bomba, Domates, Gül, Alkış, Kahkaha, Ağlama)
  socket.on('send_effect', async (data, cb) => {
    try {
      if (!checkRateLimit(user.userId, 'effect', 1200)) {
        throw new Error('Çok hızlı efekt gönderiyorsunuz, lütfen biraz bekleyin.');
      }
      await tableManager.sendInteractiveEffect(
        user.userId,
        String(data?.tableId),
        String(data?.targetUserId),
        String(data?.effectKey)
      );
      if (cb) cb({ ok: true });
    } catch (err: any) {
      if (cb) cb({ ok: false, error: err.message });
      else socket.emit('error_msg', err.message);
    }
  });

  // PUBG Tarzı Sürekli Canlı Sesli Sohbet (Continuous Live Voice Stream & Mic Durumu)
  socket.on('voice_ptt', (data) => {
    const tableId = String(data?.tableId || '');
    if (!tableId) return;
    if (!tableManager.isUserInTable(user.userId, tableId)) return;
    const audioBase64 =
      typeof data?.audioBase64 === 'string' && data.audioBase64.length <= 1500000
        ? data.audioBase64
        : null;
    if (audioBase64 && !checkRateLimit(user.userId, 'voice_clip', 150)) return;

    io.to(`table:${tableId}`).emit('voice_ptt_stream', {
      userId: user.userId,
      username: user.username,
      isSpeaking: Boolean(data?.isSpeaking),
      audioBase64,
    });
  });

  socket.on('disconnect', () => {
    tableManager.handleDisconnect(user.userId, socket.id);
  });
});

async function bootstrap() {
  await db.init();
  server.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Yanık İskambil HD Oyun Sunucusu 0.0.0.0:${PORT} portunda çalışıyor!`);
  });
}

bootstrap();
