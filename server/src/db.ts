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

      INSERT INTO system_vault (id, rake_collected, emoji_collected, total_games_played, emoji_cost)
      VALUES (1, 0, 0, 0, 10)
      ON CONFLICT (id) DO NOTHING;
    `);
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
