// Server boss for Respite Collection.
// One Durable Object ("global") holds every boss event. It handles one request at a time,
// so two players hitting the boss at the same moment can't overwrite each other's damage.
//
// Routes (send "X-Game-Version: <n>" on all of them, and "Authorization: Bearer <token>" once registered):
//   POST /register      {name}                -> {player_id, token}
//   GET  /boss                                -> {event, top, recent, me}
//   POST /boss/start                          -> {attempt_id, seed, attempts_left}
//   POST /boss/submit   {attempt_id, damage}  -> {damage, hp, defeated}
//   POST /boss/claim                          -> {rewards: [{event_id, boss_key, defeated, damage, rank, players}]}
//                                                (defeated events the player hit at least once; each returned once)
//   POST /admin/start   {boss_key, max_hp, hours, attempts_per_day, max_hit}   (header X-Admin-Key)
//   POST /admin/end                                                            (header X-Admin-Key)
//   POST /admin/set_hp  {max_hp}   new max HP for the running event; damage already dealt still counts (X-Admin-Key)
//   POST /admin/set_hours {hours}  the newest event now lasts `hours` from its start; reopens it if it ran out of
//                                  time (not if the boss fell). Damage and the leaderboard are kept. (X-Admin-Key)
import { DurableObject } from "cloudflare:workers";

// A started fight must be reported within this time. Long, because a game that loses its connection
// keeps the result and sends it the next time it's online.
const ATTEMPT_TTL_MS = 24 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;     // attempts reset at 00:00 UTC
const NAME_MAX = 16;
const LIST_SIZE = 10;                   // players on the leaderboard and hits in the recent feed

export default {
	async fetch(request, env) {
		const cors = corsHeaders(request, env);
		if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });

		const url = new URL(request.url);
		const route = `${request.method} ${url.pathname.replace(/\/+$/, "")}`;
		const body = request.method === "POST" ? await request.json().catch(() => ({})) : {};
		const token = (request.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
		const room = env.BOSS.get(env.BOSS.idFromName("global"));

		let result;
		if (route.startsWith("POST /admin/")) {
			if (!env.ADMIN_KEY || request.headers.get("X-Admin-Key") !== env.ADMIN_KEY) {
				result = fail(403, "forbidden");
			} else if (route === "POST /admin/start") {
				result = await room.adminStart(body);
			} else if (route === "POST /admin/end") {
				result = await room.adminEnd();
			} else if (route === "POST /admin/set_hp") {
				result = await room.adminSetHp(body);
			} else if (route === "POST /admin/set_hours") {
				result = await room.adminSetHours(body);
			}
		} else {
			// Old builds still open in someone's tab get told to refresh instead of breaking
			const minVersion = Number(env.MIN_VERSION || 0);
			if (Number(request.headers.get("X-Game-Version") || 0) < minVersion) {
				result = fail(426, "update_required", { min_version: minVersion });
			} else if (route === "POST /register") {
				result = await room.register(body.name);
			} else if (route === "GET /boss") {
				result = await room.state(token);
			} else if (route === "POST /boss/start") {
				result = await room.start(token);
			} else if (route === "POST /boss/submit") {
				result = await room.submit(token, body.attempt_id, body.damage);
			} else if (route === "POST /boss/claim") {
				result = await room.claim(token);
			}
		}
		result ??= fail(404, "not_found");
		return Response.json(result.body, { status: result.status, headers: cors });
	},
};

function corsHeaders(request, env) {
	const origin = request.headers.get("Origin") || "";
	const allowed = (env.ALLOWED_ORIGINS || "").split(",").map((s) => s.trim());
	const headers = {
		"Access-Control-Allow-Methods": "GET, POST, OPTIONS",
		"Access-Control-Allow-Headers": "Content-Type, Authorization, X-Game-Version, X-Admin-Key",
		"Access-Control-Max-Age": "86400",
		"Vary": "Origin",
	};
	if (allowed.includes(origin)) headers["Access-Control-Allow-Origin"] = origin;
	return headers;
}

const ok = (body) => ({ status: 200, body });
const fail = (status, error, extra = {}) => ({ status, body: { error, ...extra } });

export class BossRoom extends DurableObject {
	constructor(ctx, env) {
		super(ctx, env);
		this.sql = ctx.storage.sql;
		this.sql.exec(`CREATE TABLE IF NOT EXISTS players (
			id TEXT PRIMARY KEY, token TEXT UNIQUE NOT NULL, name TEXT NOT NULL, created_at INTEGER NOT NULL)`);
		this.sql.exec(`CREATE TABLE IF NOT EXISTS events (
			id INTEGER PRIMARY KEY AUTOINCREMENT, boss_key TEXT NOT NULL, max_hp INTEGER NOT NULL, hp INTEGER NOT NULL,
			starts_at INTEGER NOT NULL, ends_at INTEGER NOT NULL, attempts_per_day INTEGER NOT NULL,
			max_hit INTEGER NOT NULL, status TEXT NOT NULL, last_hit TEXT)`);
		this.sql.exec(`CREATE TABLE IF NOT EXISTS attempts (
			id TEXT PRIMARY KEY, event_id INTEGER NOT NULL, player_id TEXT NOT NULL, day INTEGER NOT NULL,
			seed INTEGER NOT NULL, issued_at INTEGER NOT NULL, damage INTEGER, submitted_at INTEGER)`);
		this.sql.exec(`CREATE INDEX IF NOT EXISTS attempts_by_player ON attempts (event_id, player_id, day)`);
		this.sql.exec(`CREATE INDEX IF NOT EXISTS attempts_by_time ON attempts (event_id, submitted_at)`);
		this.sql.exec(`CREATE TABLE IF NOT EXISTS contributions (
			event_id INTEGER NOT NULL, player_id TEXT NOT NULL, damage INTEGER NOT NULL DEFAULT 0,
			attempts INTEGER NOT NULL DEFAULT 0, claimed INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (event_id, player_id))`);
		// Added after the first deploy: when the player reached their current total, to break ties on the leaderboard
		const columns = this.sql.exec("PRAGMA table_info(contributions)").toArray().map((c) => c.name);
		if (!columns.includes("reached_at")) {
			this.sql.exec("ALTER TABLE contributions ADD COLUMN reached_at INTEGER NOT NULL DEFAULT 0");
		}
	}

	// 1 = most damage; equal damage goes to whoever reached it first
	_rank(eventId, playerId) {
		return this.sql.exec(`SELECT COUNT(*) AS n FROM contributions o, contributions c
			WHERE c.event_id = ? AND c.player_id = ? AND o.event_id = c.event_id AND o.damage > 0
			AND (o.damage > c.damage OR (o.damage = c.damage AND o.reached_at < c.reached_at))`, eventId, playerId).one().n + 1;
	}

	register(name) {
		const id = crypto.randomUUID();
		const bytes = crypto.getRandomValues(new Uint8Array(24));
		const token = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
		this.sql.exec("INSERT INTO players (id, token, name, created_at) VALUES (?, ?, ?, ?)",
			id, token, cleanName(name), Date.now());
		return ok({ player_id: id, token });
	}

	state(token) {
		const now = Date.now();
		const event = this._currentEvent(now);
		if (!event) return ok({ event: null, top: [], recent: [], me: null });

		const top = this.sql.exec(`SELECT p.name, c.damage FROM contributions c JOIN players p ON p.id = c.player_id
			WHERE c.event_id = ? AND c.damage > 0 ORDER BY c.damage DESC, c.reached_at ASC LIMIT ?`, event.id, LIST_SIZE).toArray();
		const recent = this.sql.exec(`SELECT p.name, a.damage, a.submitted_at FROM attempts a JOIN players p ON p.id = a.player_id
			WHERE a.event_id = ? AND a.submitted_at IS NOT NULL ORDER BY a.submitted_at DESC LIMIT ?`, event.id, LIST_SIZE).toArray();

		let me = null;
		const player = this._player(token);
		if (player) {
			const mine = this.sql.exec("SELECT damage FROM contributions WHERE event_id = ? AND player_id = ?",
				event.id, player.id).toArray()[0];
			me = {
				name: player.name,
				damage: mine ? mine.damage : 0,
				rank: mine && mine.damage > 0 ? this._rank(event.id, player.id) : 0,
				attempts_left: event.status === "active" ? this._attemptsLeft(event, player.id, now) : 0,
				unclaimed: this.sql.exec(`SELECT COUNT(*) AS n FROM contributions c JOIN events e ON e.id = c.event_id
					WHERE c.player_id = ? AND c.claimed = 0 AND e.status = 'defeated' AND c.damage > 0`, player.id).one().n,
			};
		}
		return ok({ event: publicEvent(event), top, recent, me, server_time: now });
	}

	start(token) {
		const player = this._player(token);
		if (!player) return fail(401, "unknown_player");
		const now = Date.now();
		const event = this._currentEvent(now);
		if (!event || event.status !== "active") return fail(409, "no_active_event");
		const left = this._attemptsLeft(event, player.id, now);
		if (left <= 0) return fail(409, "no_attempts_left");

		const attemptId = crypto.randomUUID();
		const seed = crypto.getRandomValues(new Uint32Array(1))[0] & 0x7fffffff;
		this.sql.exec("INSERT INTO attempts (id, event_id, player_id, day, seed, issued_at) VALUES (?, ?, ?, ?, ?, ?)",
			attemptId, event.id, player.id, Math.floor(now / DAY_MS), seed, now);
		return ok({ attempt_id: attemptId, seed, attempts_left: left - 1 });
	}

	submit(token, attemptId, damage) {
		const player = this._player(token);
		if (!player) return fail(401, "unknown_player");
		const now = Date.now();
		const attempt = this.sql.exec("SELECT * FROM attempts WHERE id = ? AND player_id = ?",
			String(attemptId || ""), player.id).toArray()[0];
		if (!attempt) return fail(404, "unknown_attempt");
		if (attempt.submitted_at !== null) return fail(409, "already_submitted");
		if (now - attempt.issued_at > ATTEMPT_TTL_MS) return fail(409, "attempt_expired");

		this._currentEvent(now);  // closes the event first if its time ran out
		const event = this.sql.exec("SELECT * FROM events WHERE id = ?", attempt.event_id).one();
		// The client calculates the damage, so cap it at what the strongest team could plausibly deal
		const dealt = Math.min(Math.max(Math.floor(Number(damage) || 0), 0), event.max_hit);

		this.sql.exec("UPDATE attempts SET damage = ?, submitted_at = ? WHERE id = ?", dealt, now, attempt.id);
		this.sql.exec(`INSERT INTO contributions (event_id, player_id, damage, attempts, reached_at) VALUES (?, ?, ?, 1, ?)
			ON CONFLICT (event_id, player_id) DO UPDATE SET damage = damage + excluded.damage, attempts = attempts + 1,
				reached_at = CASE WHEN excluded.damage > 0 THEN excluded.reached_at ELSE reached_at END`,
			event.id, player.id, dealt, now);

		let hp = event.hp;
		let defeated = event.status === "defeated";
		if (event.status === "active") {
			hp = Math.max(event.hp - dealt, 0);
			defeated = hp === 0;
			this.sql.exec("UPDATE events SET hp = ?, status = ?, last_hit = ? WHERE id = ?",
				hp, defeated ? "defeated" : "active", defeated ? player.id : null, event.id);
		}
		return ok({ damage: dealt, hp, defeated });
	}

	// Results of defeated events this player hit at least once. Each is returned once; the game grants the rewards.
	// Events that ran out of time give nothing, so they're just marked done.
	claim(token) {
		const player = this._player(token);
		if (!player) return fail(401, "unknown_player");
		this._currentEvent(Date.now());
		const rows = this.sql.exec(`SELECT e.id AS event_id, e.boss_key, e.last_hit, c.damage,
				(SELECT COUNT(*) FROM contributions o WHERE o.event_id = e.id AND o.damage > 0) AS players
			FROM contributions c JOIN events e ON e.id = c.event_id
			WHERE c.player_id = ? AND c.claimed = 0 AND e.status = 'defeated' AND c.damage > 0`, player.id).toArray();
		this.sql.exec(`UPDATE contributions SET claimed = 1 WHERE player_id = ? AND claimed = 0
			AND event_id IN (SELECT id FROM events WHERE status != 'active')`, player.id);
		return ok({
			rewards: rows.map((r) => ({
				event_id: r.event_id, boss_key: r.boss_key, defeated: true, last_hit: r.last_hit === player.id,
				damage: r.damage, rank: this._rank(r.event_id, player.id), players: r.players,
			})),
		});
	}

	adminStart(body) {
		const now = Date.now();
		const current = this._currentEvent(now);
		if (current && current.status === "active") return fail(409, "event_already_active", { event: publicEvent(current) });
		const maxHp = Math.floor(Number(body.max_hp) || 1000000);
		const hours = Number(body.hours) || 72;
		this.sql.exec(`INSERT INTO events (boss_key, max_hp, hp, starts_at, ends_at, attempts_per_day, max_hit, status)
			VALUES (?, ?, ?, ?, ?, ?, ?, 'active')`,
			String(body.boss_key || "boss"), maxHp, maxHp, now, now + hours * 60 * 60 * 1000,
			Math.floor(Number(body.attempts_per_day) || 5), Math.floor(Number(body.max_hit) || 100000));
		return ok({ event: publicEvent(this._currentEvent(now)) });
	}

	adminEnd() {
		const event = this._currentEvent(Date.now());
		if (!event || event.status !== "active") return fail(409, "no_active_event");
		this.sql.exec("UPDATE events SET status = 'expired' WHERE id = ?", event.id);
		return ok({ ended: event.id });
	}

	// Changes the running event's max HP and keeps the damage players have dealt: 1M with 300k dealt, set to 2M,
	// leaves 1.7M to go. Refused if the damage already dealt would cover the new max (that would end the event).
	adminSetHp(body) {
		const event = this._currentEvent(Date.now());
		if (!event || event.status !== "active") return fail(409, "no_active_event");
		const maxHp = Math.floor(Number(body.max_hp) || 0);
		const dealt = event.max_hp - event.hp;
		if (maxHp <= dealt) return fail(409, "would_defeat", { damage_dealt: dealt });
		this.sql.exec("UPDATE events SET max_hp = ?, hp = ? WHERE id = ?", maxHp, maxHp - dealt, event.id);
		return ok({ event: publicEvent(this._currentEvent(Date.now())), damage_dealt: dealt });
	}

	// Changes how long the newest event lasts, counted from its start: 72h set to 168h runs it a week. An event that
	// ran out of time (or was ended) comes back if the new end is still ahead; a defeated boss stays defeated.
	adminSetHours(body) {
		const now = Date.now();
		const event = this._currentEvent(now);
		if (!event) return fail(409, "no_event");
		if (event.status === "defeated") return fail(409, "already_defeated");
		const hours = Number(body.hours) || 0;
		if (hours <= 0) return fail(400, "bad_hours");
		const endsAt = event.starts_at + Math.round(hours * 60 * 60 * 1000);
		if (endsAt <= now) return fail(409, "already_past", { ends_at: endsAt });
		this.sql.exec("UPDATE events SET ends_at = ?, status = 'active' WHERE id = ?", endsAt, event.id);
		return ok({ event: publicEvent(this._currentEvent(now)) });
	}

	// The newest event, marked expired if its time is up
	_currentEvent(now) {
		const event = this.sql.exec("SELECT * FROM events ORDER BY id DESC LIMIT 1").toArray()[0];
		if (event && event.status === "active" && now >= event.ends_at) {
			this.sql.exec("UPDATE events SET status = 'expired' WHERE id = ?", event.id);
			event.status = "expired";
		}
		return event || null;
	}

	_player(token) {
		if (!token) return null;
		return this.sql.exec("SELECT id, name FROM players WHERE token = ?", token).toArray()[0] || null;
	}

	_attemptsLeft(event, playerId, now) {
		const used = this.sql.exec("SELECT COUNT(*) AS n FROM attempts WHERE event_id = ? AND player_id = ? AND day = ?",
			event.id, playerId, Math.floor(now / DAY_MS)).one().n;
		return Math.max(event.attempts_per_day - used, 0);
	}
}

function publicEvent(e) {
	return {
		id: e.id, boss_key: e.boss_key, max_hp: e.max_hp, hp: e.hp, starts_at: e.starts_at, ends_at: e.ends_at,
		attempts_per_day: e.attempts_per_day, status: e.status,
	};
}

function cleanName(name) {
	const s = String(name || "").replace(/[\u0000-\u001f]/g, "").trim().slice(0, NAME_MAX);
	return s || "Player";
}
