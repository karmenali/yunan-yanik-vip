import { Pool } from 'pg';
import bcrypt from 'bcryptjs';
import { v4 as uuidv4 } from 'uuid';

export interface UserRecord {
  id: string;
  username: string;
  password_hash: string;
  role: 'admin' | 'player';
  credits: number;
  avatar: string;
  is_banned: boolean;
  created_at: string;
}

export interface CreditTransaction {
  id: string;
  user_id: string;
  username: string;
  amount: number;
  type: string;
  description: string;
  created_at: string;
}

export interface VaultSummary {
  rake_collected: number;
  emoji_collected: number;
  total_games_played: number;
  emoji_cost: number;
}

class DatabaseService {
  private pool: Pool | null = null;
  private useMemory = false;

  // In-memory yedek (yerel hızlı testler için, Docker'da doğrudan PostgreSQL kullanılır)
  private memUsers: Map<string, UserRecord> = new Map();
  private memTransactions: CreditTransaction[] = [];
  private memActiveMatches: Map<
    string,
    { tableName: string; pot: number; contributions: Record<string, number> }
  > = new Map();
  private memVault: VaultSummary = {
    rake_collected: 0,
    emoji_collected: 0,
    total_games_played: 0,
    emoji_cost: 10,
  };

  async init(): Promise<void> {
    const dbUrl = process.env.DATABASE_URL;
    if (dbUrl) {
      try {
        this.pool = new Pool({ connectionString: dbUrl });
        await this.pool.query('SELECT 1');
        console.log('✅ PostgreSQL veritabanına başarıyla bağlanıldı.');
        await this.createSchema();
        await this.refundUnfinishedMatchesOnStartup();
        await this.seedDefaultUsers();
        return;
      } catch (err) {
        console.warn('⚠️ PostgreSQL bağlantısı kurulamadı, bellek içi (In-Memory) modda çalışılıyor:', err);
        this.useMemory = true;
      }
    } else {
      console.log('ℹ️ DATABASE_URL tanımlı değil, bellek içi (In-Memory) mod aktif.');
      this.useMemory = true;
    }

    await this.seedDefaultUsers();
  }

  private async createSchema(): Promise<void> {
    if (!this.pool) return;

    await this.pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        id UUID PRIMARY KEY,
        username VARCHAR(64) UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        role VARCHAR(16) NOT NULL DEFAULT 'player',
        credits BIGINT NOT NULL DEFAULT 0,
        avatar VARCHAR(32) NOT NULL DEFAULT 'king',
        is_banned BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );

      CREATE TABLE IF NOT EXISTS credit_transactions (
        id UUID PRIMARY KEY,
        user_id UUID NOT NULL,
        username VARCHAR(64) NOT NULL,
        amount BIGINT NOT NULL,
        type VARCHAR(32) NOT NULL,
        description TEXT NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );

      CREATE TABLE IF NOT EXISTS system_vault (
        id INT PRIMARY KEY DEFAULT 1,
        rake_collected BIGINT NOT NULL DEFAULT 0,
        emoji_collected BIGINT NOT NULL DEFAULT 0,
        total_games_played INT NOT NULL DEFAULT 0,
        emoji_cost INT NOT NULL DEFAULT 10
      );

      CREATE TABLE IF NOT EXISTS active_matches (
        table_id VARCHAR(64) PRIMARY KEY,
        table_name VARCHAR(128) NOT NULL,
        pot BIGINT NOT NULL DEFAULT 0,
        contributions JSONB NOT NULL DEFAULT '{}'::jsonb,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );

      CREATE TABLE IF NOT EXISTS user_friends (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        friend_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        status VARCHAR(20) DEFAULT 'accepted',
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        UNIQUE(user_id, friend_id)
      );

      CREATE TABLE IF NOT EXISTS friend_requests (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        status VARCHAR(20) NOT NULL DEFAULT 'pending',
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        UNIQUE(sender_id, receiver_id)
      );

      CREATE TABLE IF NOT EXISTS user_notifications (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        type VARCHAR(50) NOT NULL,
        title VARCHAR(100) NOT NULL,
        message TEXT NOT NULL,
        data JSONB DEFAULT '{}'::jsonb,
        is_read BOOLEAN NOT NULL DEFAULT false,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );

      INSERT INTO system_vault (id, rake_collected, emoji_collected, total_games_played, emoji_cost)
      VALUES (1, 0, 0, 0, 10)
      ON CONFLICT (id) DO NOTHING;
    `);
  }

  /**
   * Sunucu yeniden başladığında yarım kalmış aktif maçların potlarını oyunculara otomatik iade eder
   */
  async refundUnfinishedMatchesOnStartup(): Promise<void> {
    if (this.useMemory || !this.pool) return;
    try {
      const res = await this.pool.query('SELECT * FROM active_matches');
      for (const row of res.rows) {
        const tableId = String(row.table_id);
        const tableName = String(row.table_name || 'Masa');
        await this.refundMatchEscrow(
          tableId,
          `${tableName} sunucu bakımı / yarım kalan maç otomatik kredi iadesi`
        );
        console.log(`♻️ Yarım kalan maç iade edildi: ${tableName} (${tableId})`);
      }
    } catch (err) {
      console.error('Başlangıç escrow iade kontrolü hatası:', err);
    }
  }

  private async seedDefaultUsers(): Promise<void> {
    const adminUsername = process.env.ADMIN_USERNAME || 'admin';
    const adminPassword = process.env.ADMIN_PASSWORD || 'admin123456';

    const existingAdmin = await this.getUserByUsername(adminUsername);
    if (!existingAdmin) {
      await this.createUser(adminUsername, adminPassword, 'admin', 100000, 'king');
      console.log(`👑 Varsayılan Admin oluşturuldu -> Kullanıcı: ${adminUsername} | Şifre: ${adminPassword}`);
    }

    // Demo / Test oyuncuları
    const demoPlayers = [
      { u: 'oyuncu1', p: '123456', c: 5000, av: 'lion' },
      { u: 'oyuncu2', p: '123456', c: 5000, av: 'queen' },
      { u: 'oyuncu3', p: '123456', c: 5000, av: 'wolf' },
      { u: 'oyuncu4', p: '123456', c: 5000, av: 'boss' },
    ];
    for (const dp of demoPlayers) {
      const ex = await this.getUserByUsername(dp.u);
      if (!ex) {
        await this.createUser(dp.u, dp.p, 'player', dp.c, dp.av);
      }
    }
  }

  async getUserByUsername(username: string): Promise<UserRecord | null> {
    const clean = username.trim().toLowerCase();
    if (this.useMemory || !this.pool) {
      for (const u of this.memUsers.values()) {
        if (u.username.toLowerCase() === clean) return { ...u };
      }
      return null;
    }
    const res = await this.pool.query(
      'SELECT * FROM users WHERE LOWER(username) = $1 LIMIT 1',
      [clean]
    );
    if (res.rows.length === 0) return null;
    return this.mapUserRow(res.rows[0]);
  }

  async getUserById(id: string): Promise<UserRecord | null> {
    if (this.useMemory || !this.pool) {
      const u = this.memUsers.get(id);
      return u ? { ...u } : null;
    }
    const res = await this.pool.query('SELECT * FROM users WHERE id = $1 LIMIT 1', [id]);
    if (res.rows.length === 0) return null;
    return this.mapUserRow(res.rows[0]);
  }

  async getAllUsers(): Promise<Omit<UserRecord, 'password_hash'>[]> {
    if (this.useMemory || !this.pool) {
      return Array.from(this.memUsers.values()).map(({ password_hash, ...rest }) => rest);
    }
    const res = await this.pool.query('SELECT * FROM users ORDER BY created_at DESC');
    return res.rows.map((r) => {
      const u = this.mapUserRow(r);
      const { password_hash, ...rest } = u;
      return rest;
    });
  }

  async createUser(
    username: string,
    plainPassword: string,
    role: 'admin' | 'player' = 'player',
    initialCredits = 0,
    avatar = 'lion'
  ): Promise<UserRecord> {
    const cleanUsername = username.trim();
    const existing = await this.getUserByUsername(cleanUsername);
    if (existing) {
      throw new Error('Bu kullanıcı adı zaten kullanılıyor.');
    }

    const id = uuidv4();
    const password_hash = await bcrypt.hash(plainPassword, 10);
    const created_at = new Date().toISOString();

    if (this.useMemory || !this.pool) {
      const record: UserRecord = {
        id,
        username: cleanUsername,
        password_hash,
        role,
        credits: Number(initialCredits),
        avatar,
        is_banned: false,
        created_at,
      };
      this.memUsers.set(id, record);
      if (initialCredits > 0) {
        await this.logTransaction(id, cleanUsername, initialCredits, 'admin_add', 'Başlangıç kredisi');
      }
      return { ...record };
    }

    const res = await this.pool.query(
      `INSERT INTO users (id, username, password_hash, role, credits, avatar, is_banned)
       VALUES ($1, $2, $3, $4, $5, $6, FALSE)
       RETURNING *`,
      [id, cleanUsername, password_hash, role, initialCredits, avatar]
    );

    if (initialCredits > 0) {
      await this.logTransaction(id, cleanUsername, initialCredits, 'admin_add', 'Başlangıç kredisi');
    }

    return this.mapUserRow(res.rows[0]);
  }

  async updateUserPassword(userId: string, newPlainPassword: string): Promise<void> {
    const hash = await bcrypt.hash(newPlainPassword, 10);
    if (this.useMemory || !this.pool) {
      const u = this.memUsers.get(userId);
      if (u) u.password_hash = hash;
      return;
    }
    await this.pool.query('UPDATE users SET password_hash = $1 WHERE id = $2', [hash, userId]);
  }

  async updateUserAvatar(userId: string, avatar: string): Promise<void> {
    if (this.useMemory || !this.pool) {
      const u = this.memUsers.get(userId);
      if (u) u.avatar = avatar;
      return;
    }
    await this.pool.query('UPDATE users SET avatar = $1 WHERE id = $2', [avatar, userId]);
  }

  async setUserBanStatus(userId: string, isBanned: boolean): Promise<void> {
    if (this.useMemory || !this.pool) {
      const u = this.memUsers.get(userId);
      if (u) u.is_banned = isBanned;
      return;
    }
    await this.pool.query('UPDATE users SET is_banned = $1 WHERE id = $2', [isBanned, userId]);
  }

  /**
   * Kredi ekleme / düşme (Atomik işlem)
   */
  async adjustCredits(
    userId: string,
    delta: number,
    type: string,
    description: string
  ): Promise<number> {
    const intDelta = Math.round(delta);
    if (this.useMemory || !this.pool) {
      const u = this.memUsers.get(userId);
      if (!u) throw new Error('Kullanıcı bulunamadı.');
      if (u.credits + intDelta < 0) {
        throw new Error('Yetersiz oyun kredisi.');
      }
      u.credits += intDelta;
      await this.logTransaction(u.id, u.username, intDelta, type, description);
      return u.credits;
    }

    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const res = await client.query('SELECT id, username, credits FROM users WHERE id = $1 FOR UPDATE', [
        userId,
      ]);
      if (res.rows.length === 0) {
        throw new Error('Kullanıcı bulunamadı.');
      }
      const currentCredits = Number(res.rows[0].credits);
      const username = res.rows[0].username;

      if (currentCredits + intDelta < 0) {
        throw new Error('Yetersiz oyun kredisi.');
      }

      const newCredits = currentCredits + intDelta;
      await client.query('UPDATE users SET credits = $1 WHERE id = $2', [newCredits, userId]);
      await client.query(
        `INSERT INTO credit_transactions (id, user_id, username, amount, type, description)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [uuidv4(), userId, username, intDelta, type, description]
      );
      await client.query('COMMIT');
      return newCredits;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async logTransaction(
    userId: string,
    username: string,
    amount: number,
    type: string,
    description: string
  ): Promise<void> {
    const tx: CreditTransaction = {
      id: uuidv4(),
      user_id: userId,
      username,
      amount: Math.round(amount),
      type,
      description,
      created_at: new Date().toISOString(),
    };

    if (this.useMemory || !this.pool) {
      this.memTransactions.unshift(tx);
      if (this.memTransactions.length > 300) this.memTransactions.pop();
      return;
    }

    await this.pool.query(
      `INSERT INTO credit_transactions (id, user_id, username, amount, type, description)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [tx.id, tx.user_id, tx.username, tx.amount, tx.type, tx.description]
    );
  }

  async addVaultRake(rakeAmount: number): Promise<void> {
    const amt = Math.round(rakeAmount);
    if (this.useMemory || !this.pool) {
      this.memVault.rake_collected += amt;
      this.memVault.total_games_played += 1;
      return;
    }
    await this.pool.query(
      `UPDATE system_vault
       SET rake_collected = rake_collected + $1,
           total_games_played = total_games_played + 1
       WHERE id = 1`,
      [amt]
    );
  }

  async addVaultEmojiRevenue(amount: number): Promise<void> {
    const amt = Math.round(amount);
    if (this.useMemory || !this.pool) {
      this.memVault.emoji_collected += amt;
      return;
    }
    await this.pool.query(
      `UPDATE system_vault
       SET emoji_collected = emoji_collected + $1
       WHERE id = 1`,
      [amt]
    );
  }

  async setEmojiCost(cost: number): Promise<void> {
    const c = Math.max(0, Math.round(cost));
    if (this.useMemory || !this.pool) {
      this.memVault.emoji_cost = c;
      return;
    }
    await this.pool.query('UPDATE system_vault SET emoji_cost = $1 WHERE id = 1', [c]);
  }

  async getVaultSummary(): Promise<VaultSummary> {
    if (this.useMemory || !this.pool) {
      return { ...this.memVault };
    }
    const res = await this.pool.query('SELECT * FROM system_vault WHERE id = 1');
    if (res.rows.length === 0) {
      return { rake_collected: 0, emoji_collected: 0, total_games_played: 0, emoji_cost: 10 };
    }
    const row = res.rows[0];
    return {
      rake_collected: Number(row.rake_collected),
      emoji_collected: Number(row.emoji_collected),
      total_games_played: Number(row.total_games_played),
      emoji_cost: Number(row.emoji_cost),
    };
  }

  async getRecentTransactions(limit = 100): Promise<CreditTransaction[]> {
    if (this.useMemory || !this.pool) {
      return this.memTransactions.slice(0, limit);
    }
    const res = await this.pool.query(
      'SELECT * FROM credit_transactions ORDER BY created_at DESC LIMIT $1',
      [limit]
    );
    return res.rows.map((r) => ({
      id: r.id,
      user_id: r.user_id,
      username: r.username,
      amount: Number(r.amount),
      type: r.type,
      description: r.description,
      created_at: new Date(r.created_at).toISOString(),
    }));
  }

  async getUserTransactions(userId: string, limit = 60): Promise<CreditTransaction[]> {
    if (this.useMemory || !this.pool) {
      return this.memTransactions.filter((t) => t.user_id === userId).slice(0, limit);
    }
    const res = await this.pool.query(
      'SELECT * FROM credit_transactions WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2',
      [userId, limit]
    );
    return res.rows.map((r) => ({
      id: r.id,
      user_id: r.user_id,
      username: r.username,
      amount: Number(r.amount),
      type: r.type,
      description: r.description,
      created_at: new Date(r.created_at).toISOString(),
    }));
  }

  async upsertMatchEscrow(
    tableId: string,
    tableName: string,
    pot: number,
    contributions: Record<string, number>
  ): Promise<void> {
    if (this.useMemory || !this.pool) {
      this.memActiveMatches.set(tableId, {
        tableName,
        pot: Math.round(pot),
        contributions: { ...contributions },
      });
      return;
    }
    await this.pool.query(
      `INSERT INTO active_matches (table_id, table_name, pot, contributions, updated_at)
       VALUES ($1, $2, $3, $4::jsonb, NOW())
       ON CONFLICT (table_id)
       DO UPDATE SET table_name = EXCLUDED.table_name,
                     pot = EXCLUDED.pot,
                     contributions = EXCLUDED.contributions,
                     updated_at = NOW()`,
      [tableId, tableName, Math.round(pot), JSON.stringify(contributions)]
    );
  }

  async clearMatchEscrow(tableId: string): Promise<void> {
    if (this.useMemory || !this.pool) {
      this.memActiveMatches.delete(tableId);
      return;
    }
    await this.pool.query('DELETE FROM active_matches WHERE table_id = $1', [tableId]);
  }

  async refundMatchEscrow(
    tableId: string,
    reason: string
  ): Promise<Array<{ userId: string; amount: number; newCredits: number }>> {
    const refunded: Array<{ userId: string; amount: number; newCredits: number }> = [];

    if (this.useMemory || !this.pool) {
      const escrow = this.memActiveMatches.get(tableId);
      if (!escrow) return refunded;
      this.memActiveMatches.delete(tableId);
      for (const [uid, amt] of Object.entries(escrow.contributions)) {
        const cleanAmt = Math.round(Number(amt));
        if (cleanAmt > 0) {
          try {
            const newCredits = await this.adjustCredits(uid, cleanAmt, 'table_refund', reason);
            refunded.push({ userId: uid, amount: cleanAmt, newCredits });
          } catch {}
        }
      }
      return refunded;
    }

    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const res = await client.query(
        'SELECT * FROM active_matches WHERE table_id = $1 FOR UPDATE',
        [tableId]
      );
      if (res.rows.length === 0) {
        await client.query('COMMIT');
        return refunded;
      }

      const contributions: Record<string, number> = res.rows[0].contributions || {};
      await client.query('DELETE FROM active_matches WHERE table_id = $1', [tableId]);

      for (const [uid, amt] of Object.entries(contributions)) {
        const cleanAmt = Math.round(Number(amt));
        if (cleanAmt <= 0) continue;
        // Botları ve geçersiz UUID formatındaki kullanıcıları atla
        if (uid.startsWith('bot_') || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(uid)) {
          continue;
        }
        const uRes = await client.query(
          'SELECT id, username, credits FROM users WHERE id = $1 FOR UPDATE',
          [uid]
        );
        if (uRes.rows.length === 0) continue;
        const username = uRes.rows[0].username;
        const newCredits = Number(uRes.rows[0].credits) + cleanAmt;
        await client.query('UPDATE users SET credits = $1 WHERE id = $2', [newCredits, uid]);
        await client.query(
          `INSERT INTO credit_transactions (id, user_id, username, amount, type, description)
           VALUES ($1, $2, $3, $4, $5, $6)`,
          [uuidv4(), uid, username, cleanAmt, 'table_refund', reason]
        );
        refunded.push({ userId: uid, amount: cleanAmt, newCredits });
      }

      await client.query('COMMIT');
      return refunded;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Oyun sonu ödül dağıtımını, kasa komisyonunu ve aktif maç escrow kaydının silinmesini tek bir atomik DB işleminde yapar
   */
  async settleMatchVictory(
    tableId: string,
    winnerUserId: string,
    prizeWon: number,
    houseRake: number,
    description: string
  ): Promise<number> {
    const cleanPrize = Math.round(prizeWon);
    const cleanRake = Math.round(houseRake);

    if (this.useMemory || !this.pool) {
      this.memActiveMatches.delete(tableId);
      const newBal = await this.adjustCredits(winnerUserId, cleanPrize, 'table_win', description);
      await this.addVaultRake(cleanRake);
      return newBal;
    }

    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('DELETE FROM active_matches WHERE table_id = $1', [tableId]);

      const uRes = await client.query(
        'SELECT id, username, credits FROM users WHERE id = $1 FOR UPDATE',
        [winnerUserId]
      );
      if (uRes.rows.length === 0) {
        throw new Error('Kazanan kullanıcı bulunamadı.');
      }
      const username = uRes.rows[0].username;
      const newCredits = Number(uRes.rows[0].credits) + cleanPrize;

      await client.query('UPDATE users SET credits = $1 WHERE id = $2', [newCredits, winnerUserId]);
      await client.query(
        `INSERT INTO credit_transactions (id, user_id, username, amount, type, description)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [uuidv4(), winnerUserId, username, cleanPrize, 'table_win', description]
      );
      await client.query(
        `UPDATE system_vault
         SET rake_collected = rake_collected + $1,
             total_games_played = total_games_played + 1
         WHERE id = 1`,
        [cleanRake]
      );

      await client.query('COMMIT');
      return newCredits;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async searchUsers(
    query: string,
    currentUserId: string
  ): Promise<{ id: string; username: string; avatar: string; role: string }[]> {
    if (this.useMemory || !this.pool) {
      const q = query.toLowerCase();
      const results: { id: string; username: string; avatar: string; role: string }[] = [];
      for (const u of this.memUsers.values()) {
        if (u.id !== currentUserId && u.username.toLowerCase().includes(q)) {
          results.push({ id: u.id, username: u.username, avatar: u.avatar, role: u.role });
        }
      }
      return results;
    }
    const res = await this.pool.query(
      `SELECT id, username, avatar, role FROM users WHERE username ILIKE $1 AND id != $2 ORDER BY username ASC LIMIT 20`,
      [`%${query}%`, currentUserId]
    );
    return res.rows.map((r) => ({
      id: String(r.id),
      username: String(r.username),
      avatar: String(r.avatar || 'king'),
      role: String(r.role || 'player'),
    }));
  }

  async getFriends(
    userId: string
  ): Promise<{ id: string; username: string; avatar: string; role: string }[]> {
    if (this.useMemory || !this.pool) {
      return [];
    }
    const res = await this.pool.query(
      `SELECT u.id, u.username, u.avatar, u.role
       FROM user_friends f
       JOIN users u ON f.friend_id = u.id
       WHERE f.user_id = $1
       ORDER BY u.username ASC`,
      [userId]
    );
    return res.rows.map((r) => ({
      id: String(r.id),
      username: String(r.username),
      avatar: String(r.avatar || 'king'),
      role: String(r.role || 'player'),
    }));
  }

  async sendFriendRequest(
    senderId: string,
    receiverUsername: string
  ): Promise<{
    status: 'sent' | 'already_friends' | 'auto_accepted';
    receiver: { id: string; username: string; avatar: string; role: string };
    requestId?: string;
  }> {
    if (this.useMemory || !this.pool) {
      throw new Error('Veritabanı bağlantısı yok.');
    }
    const receiverRes = await this.pool.query(
      `SELECT id, username, avatar, role FROM users WHERE username ILIKE $1`,
      [receiverUsername]
    );
    if (receiverRes.rows.length === 0) {
      throw new Error(`'${receiverUsername}' adında bir kullanıcı bulunamadı.`);
    }
    const receiver = receiverRes.rows[0];
    if (receiver.id === senderId) {
      throw new Error('Kendinize arkadaşlık isteği gönderemezsiniz.');
    }

    // Zaten arkadaşlar mı?
    const friendCheck = await this.pool.query(
      `SELECT id FROM user_friends WHERE user_id = $1 AND friend_id = $2`,
      [senderId, receiver.id]
    );
    if (friendCheck.rows.length > 0) {
      throw new Error(`'${receiver.username}' ile zaten arkadaşsınız.`);
    }

    // Karşı taraf zaten bir istek göndermiş ve bekliyor mu? (Çapraz istek durumunda otomatik kabul)
    const reverseReq = await this.pool.query(
      `SELECT id FROM friend_requests WHERE sender_id = $1 AND receiver_id = $2 AND status = 'pending'`,
      [receiver.id, senderId]
    );
    if (reverseReq.rows.length > 0) {
      // Otomatik kabul et
      await this.pool.query(
        `UPDATE friend_requests SET status = 'accepted', updated_at = NOW() WHERE id = $1`,
        [reverseReq.rows[0].id]
      );
      await this.pool.query(
        `INSERT INTO user_friends (user_id, friend_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
        [senderId, receiver.id]
      );
      await this.pool.query(
        `INSERT INTO user_friends (user_id, friend_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
        [receiver.id, senderId]
      );
      return {
        status: 'auto_accepted',
        receiver: {
          id: String(receiver.id),
          username: String(receiver.username),
          avatar: String(receiver.avatar || 'king'),
          role: String(receiver.role || 'player'),
        },
      };
    }

    // Daha önce gönderilmiş bekleyen istek var mı?
    const existingReq = await this.pool.query(
      `SELECT id, status FROM friend_requests WHERE sender_id = $1 AND receiver_id = $2 AND status = 'pending'`,
      [senderId, receiver.id]
    );
    if (existingReq.rows.length > 0) {
      throw new Error(`'${receiver.username}' kullanıcısına zaten bekleyen bir isteğiniz var.`);
    }

    // Yeni arkadaşlık isteği kaydet
    const reqRes = await this.pool.query(
      `INSERT INTO friend_requests (sender_id, receiver_id, status)
       VALUES ($1, $2, 'pending')
       ON CONFLICT (sender_id, receiver_id) DO UPDATE SET status = 'pending', updated_at = NOW()
       RETURNING id`,
      [senderId, receiver.id]
    );

    // Gönderenin adını alıp alıcıya bildirim oluştur
    const senderRes = await this.pool.query(`SELECT username FROM users WHERE id = $1`, [senderId]);
    const senderUsername = senderRes.rows[0]?.username || 'Bir oyuncu';

    await this.pool.query(
      `INSERT INTO user_notifications (user_id, type, title, message, data)
       VALUES ($1, 'friend_request', 'Yeni Arkadaşlık İsteği', $2, $3)`,
      [
        receiver.id,
        `${senderUsername} sana arkadaşlık isteği gönderdi.`,
        JSON.stringify({
          requestId: String(reqRes.rows[0].id),
          senderId,
          senderUsername,
        }),
      ]
    );

    return {
      status: 'sent',
      requestId: String(reqRes.rows[0].id),
      receiver: {
        id: String(receiver.id),
        username: String(receiver.username),
        avatar: String(receiver.avatar || 'king'),
        role: String(receiver.role || 'player'),
      },
    };
  }

  async getPendingFriendRequests(userId: string): Promise<any[]> {
    if (this.useMemory || !this.pool) return [];
    const res = await this.pool.query(
      `SELECT fr.id, fr.sender_id, fr.created_at, u.username, u.avatar, u.role
       FROM friend_requests fr
       JOIN users u ON fr.sender_id = u.id
       WHERE fr.receiver_id = $1 AND fr.status = 'pending'
       ORDER BY fr.created_at DESC`,
      [userId]
    );
    return res.rows.map((r) => ({
      id: String(r.id),
      sender_id: String(r.sender_id),
      username: String(r.username),
      avatar: String(r.avatar || 'king'),
      role: String(r.role || 'player'),
      created_at: r.created_at,
    }));
  }

  async getSentFriendRequestUserIds(userId: string): Promise<string[]> {
    if (this.useMemory || !this.pool) return [];
    const res = await this.pool.query(
      `SELECT receiver_id FROM friend_requests WHERE sender_id = $1 AND status = 'pending'`,
      [userId]
    );
    return res.rows.map((r) => String(r.receiver_id));
  }

  async respondFriendRequest(
    requestId: string,
    userId: string,
    accept: boolean
  ): Promise<{
    success: boolean;
    senderId?: string;
    senderUsername?: string;
  }> {
    if (this.useMemory || !this.pool) {
      throw new Error('Veritabanı bağlantısı yok.');
    }
    const reqRes = await this.pool.query(
      `SELECT fr.id, fr.sender_id, fr.receiver_id, u.username as sender_username
       FROM friend_requests fr
       JOIN users u ON fr.sender_id = u.id
       WHERE fr.id = $1 AND fr.receiver_id = $2 AND fr.status = 'pending'`,
      [requestId, userId]
    );
    if (reqRes.rows.length === 0) {
      throw new Error('İstek bulunamadı veya süresi dolmuş.');
    }
    const req = reqRes.rows[0];

    if (accept) {
      await this.pool.query(
        `UPDATE friend_requests SET status = 'accepted', updated_at = NOW() WHERE id = $1`,
        [requestId]
      );
      await this.pool.query(
        `INSERT INTO user_friends (user_id, friend_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
        [userId, req.sender_id]
      );
      await this.pool.query(
        `INSERT INTO user_friends (user_id, friend_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
        [req.sender_id, userId]
      );

      // Gönderene kabul bildirimini ekle
      const receiverRes = await this.pool.query(`SELECT username FROM users WHERE id = $1`, [userId]);
      const receiverUsername = receiverRes.rows[0]?.username || 'Oyuncu';

      await this.pool.query(
        `INSERT INTO user_notifications (user_id, type, title, message, data)
         VALUES ($1, 'friend_accepted', 'Arkadaşlık Kabul Edildi', $2, $3)`,
        [
          req.sender_id,
          `${receiverUsername} arkadaşlık isteğinizi kabul etti!`,
          JSON.stringify({ friendId: userId, friendUsername: receiverUsername }),
        ]
      );

      return {
        success: true,
        senderId: String(req.sender_id),
        senderUsername: String(req.sender_username),
      };
    } else {
      await this.pool.query(
        `UPDATE friend_requests SET status = 'rejected', updated_at = NOW() WHERE id = $1`,
        [requestId]
      );
      return { success: true };
    }
  }

  async getNotifications(userId: string): Promise<any[]> {
    if (this.useMemory || !this.pool) return [];
    const res = await this.pool.query(
      `SELECT id, type, title, message, data, is_read, created_at
       FROM user_notifications
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT 30`,
      [userId]
    );
    return res.rows.map((r) => ({
      id: String(r.id),
      type: String(r.type),
      title: String(r.title),
      message: String(r.message),
      data: r.data || {},
      is_read: Boolean(r.is_read),
      created_at: r.created_at,
    }));
  }

  async markNotificationRead(notificationId: string, userId: string): Promise<void> {
    if (this.useMemory || !this.pool) return;
    await this.pool.query(
      `UPDATE user_notifications SET is_read = true WHERE id = $1 AND user_id = $2`,
      [notificationId, userId]
    );
  }

  async markAllNotificationsRead(userId: string): Promise<void> {
    if (this.useMemory || !this.pool) return;
    await this.pool.query(
      `UPDATE user_notifications SET is_read = true WHERE user_id = $1`,
      [userId]
    );
  }

  async addFriend(
    userId: string,
    friendUsername: string
  ): Promise<{ id: string; username: string; avatar: string; role: string }> {
    return (await this.sendFriendRequest(userId, friendUsername)).receiver;
  }

  async getUsersByIds(
    ids: string[]
  ): Promise<{ id: string; username: string; avatar: string; role: string }[]> {
    if (ids.length === 0) return [];
    if (this.useMemory || !this.pool) {
      return ids
        .map((id) => this.memUsers.get(id))
        .filter(Boolean)
        .map((u) => ({
          id: u!.id,
          username: u!.username,
          avatar: u!.avatar,
          role: u!.role,
        }));
    }
    const res = await this.pool.query(
      `SELECT id, username, avatar, role FROM users WHERE id = ANY($1::uuid[])`,
      [ids]
    );
    return res.rows.map((r) => ({
      id: String(r.id),
      username: String(r.username),
      avatar: String(r.avatar || 'king'),
      role: String(r.role || 'player'),
    }));
  }

  private mapUserRow(row: any): UserRecord {
    return {
      id: row.id,
      username: row.username,
      password_hash: row.password_hash,
      role: row.role,
      credits: Number(row.credits),
      avatar: row.avatar || 'lion',
      is_banned: Boolean(row.is_banned),
      created_at: new Date(row.created_at).toISOString(),
    };
  }
}

export const db = new DatabaseService();
