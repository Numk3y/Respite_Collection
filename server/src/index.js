// Server boss for Respite Collection.
// One Durable Object ("global") holds every boss event. It handles one request at a time,
// so two players hitting the boss at the same moment can't overwrite each other's damage.
//
// Routes (send "X-Game-Version: <n>" on all of them, and "Authorization: Bearer <token>" once registered):
//   POST /register      {name}                -> {player_id, token, recovery_code}
//   GET  /account                             -> {player_id, name, recovery_code}   (makes a code for older accounts)
//   POST /account/rename {name}               -> {name}
//   POST /save          {data, summary}       -> {version, saved_at}   (cloud save; the last SAVE_VERSIONS are kept)
//   GET  /save                                -> {data, summary, saved_at, version} | {data: null}
//   POST /recover       {code}                -> {player_id, token, name, recovery_code, save: {data, summary, saved_at} | null}
//   GET  /boss                                -> {event, top, recent, me}
//   POST /boss/start                          -> {attempt_id, seed, attempts_left}
//   POST /boss/submit   {attempt_id, damage}  -> {damage, hp, defeated}
//   POST /boss/claim                          -> {rewards: [{event_id, boss_key, defeated, damage, rank, players}]}
//                                                (defeated events the player hit at least once; each returned once)
//   GET  /arena                                -> {me: {rating, wins, losses, rank, fights_left, has_team} | null, top}
//   POST /arena/team    {team, power}          -> {ok}   (the player's defense team, as the game describes it)
//   GET  /arena/opponents                      -> {opponents: [{player_id, name, rating, power, team}]}
//   POST /arena/start   {opponent_id}          -> {fight_id, seed, fights_left}   ("bot" = a practice team the game makes)
//   POST /arena/submit  {fight_id, win}        -> {rating, change, wins, losses}
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

// Arena: players fight each other's saved teams (the game plays the fight, like the boss), Elo ratings.
const ARENA_FIGHTS_PER_DAY = 5;         // attacks per player per day (00:00 UTC, like boss attempts)
const ARENA_START_RATING = 1000;
const ARENA_K = 32;                     // rating swing for the attacker; the defender moves half as much
const ARENA_BOT_K = 12;                 // practice bots move the rating less
const ARENA_BOT_GAP = 100;              // a bot counts as this much below the attacker's rating
const ARENA_TEAM_MAX = 6000;            // longest team description accepted (JSON characters)
const ARENA_POOL = 12;                  // closest-rated players considered when picking opponents
const ARENA_OPPONENTS = 3;

// Cloud save: the whole save as the game's JSON text, kept per player with a few older versions to roll back to.
// A recovery code (shown in the game's Settings) gets the account and its save back on a new device.
const SAVE_MAX_CHARS = 1_000_000;       // about 10x a big save today
const SAVE_VERSIONS = 3;
const SUMMARY_MAX_CHARS = 2000;
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";  // no 0/O, 1/I/L
const CODE_GROUPS = 3;                   // RC-XXXX-XXXX-XXXX: 12 characters, about 59 bits

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
			} else if (route === "GET /account") {
				result = await room.account(token);
			} else if (route === "POST /account/rename") {
				result = await room.rename(token, body.name);
			} else if (route === "POST /save") {
				result = await room.uploadSave(token, body.data, body.summary);
			} else if (route === "GET /save") {
				result = await room.downloadSave(token);
			} else if (route === "POST /recover") {
				result = await room.recover(body.code);
			} else if (route === "GET /boss") {
				result = await room.state(token);
			} else if (route === "POST /boss/start") {
				result = await room.start(token);
			} else if (route === "POST /boss/submit") {
				result = await room.submit(token, body.attempt_id, body.damage);
			} else if (route === "POST /boss/claim") {
				result = await room.claim(token);
			} else if (route === "GET /arena") {
				result = await room.arenaState(token);
			} else if (route === "POST /arena/team") {
				result = await room.arenaTeam(token, body.team, body.power);
			} else if (route === "GET /arena/opponents") {
				result = await room.arenaOpponents(token);
			} else if (route === "POST /arena/start") {
				result = await room.arenaStart(token, body.opponent_id);
			} else if (route === "POST /arena/submit") {
				result = await room.arenaSubmit(token, body.fight_id, body.win);
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
		this.sql.exec(`CREATE TABLE IF NOT EXISTS arena (
			player_id TEXT PRIMARY KEY, team TEXT NOT NULL, power INTEGER NOT NULL DEFAULT 0,
			rating INTEGER NOT NULL DEFAULT ${ARENA_START_RATING}, wins INTEGER NOT NULL DEFAULT 0,
			losses INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL)`);
		this.sql.exec(`CREATE TABLE IF NOT EXISTS arena_fights (
			id TEXT PRIMARY KEY, attacker TEXT NOT NULL, defender TEXT NOT NULL, day INTEGER NOT NULL,
			seed INTEGER NOT NULL, issued_at INTEGER NOT NULL, win INTEGER, submitted_at INTEGER)`);
		this.sql.exec("CREATE INDEX IF NOT EXISTS arena_fights_by_attacker ON arena_fights (attacker, day)");
		// Cloud save
		const playerColumns = this.sql.exec("PRAGMA table_info(players)").toArray().map((c) => c.name);
		if (!playerColumns.includes("recovery")) {
			this.sql.exec("ALTER TABLE players ADD COLUMN recovery TEXT");
		}
		this.sql.exec("CREATE UNIQUE INDEX IF NOT EXISTS players_by_recovery ON players (recovery)");
		this.sql.exec(`CREATE TABLE IF NOT EXISTS saves (
			id INTEGER PRIMARY KEY AUTOINCREMENT, player_id TEXT NOT NULL, data TEXT NOT NULL, summary TEXT NOT NULL,
			saved_at INTEGER NOT NULL)`);
		this.sql.exec("CREATE INDEX IF NOT EXISTS saves_by_player ON saves (player_id, id)");
	}

	// ───────── Accounts and cloud save ─────────

	_newCode() {
		for (;;) {
			const bytes = crypto.getRandomValues(new Uint8Array(CODE_GROUPS * 4));
			const chars = [...bytes].map((b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join("");
			const code = "RC-" + chars.match(/.{4}/g).join("-");
			if (!this.sql.exec("SELECT 1 FROM players WHERE recovery = ?", code).toArray().length) return code;
		}
	}

	// The player's recovery code, made on first request for accounts from before cloud save
	_recoveryCode(playerId) {
		const row = this.sql.exec("SELECT recovery FROM players WHERE id = ?", playerId).toArray()[0];
		if (row && row.recovery) return row.recovery;
		const code = this._newCode();
		this.sql.exec("UPDATE players SET recovery = ? WHERE id = ?", code, playerId);
		return code;
	}

	account(token) {
		const player = this._player(token);
		if (!player) return fail(401, "unknown_player");
		return ok({ player_id: player.id, name: player.name, recovery_code: this._recoveryCode(player.id) });
	}

	rename(token, name) {
		const player = this._player(token);
		if (!player) return fail(401, "unknown_player");
		const clean = cleanName(name);
		this.sql.exec("UPDATE players SET name = ? WHERE id = ?", clean, player.id);
		return ok({ name: clean });
	}

	uploadSave(token, data, summary) {
		const player = this._player(token);
		if (!player) return fail(401, "unknown_player");
		if (typeof data !== "string" || data.length < 2) return fail(400, "bad_save");
		if (data.length > SAVE_MAX_CHARS) return fail(413, "save_too_big");
		const summaryText = JSON.stringify(summary && typeof summary === "object" ? summary : {}).slice(0, SUMMARY_MAX_CHARS);
		const now = Date.now();
		this.sql.exec("INSERT INTO saves (player_id, data, summary, saved_at) VALUES (?, ?, ?, ?)",
			player.id, data, summaryText, now);
		// Keep only the newest SAVE_VERSIONS
		this.sql.exec(`DELETE FROM saves WHERE player_id = ? AND id NOT IN
			(SELECT id FROM saves WHERE player_id = ? ORDER BY id DESC LIMIT ?)`, player.id, player.id, SAVE_VERSIONS);
		const version = this.sql.exec("SELECT MAX(id) AS v FROM saves WHERE player_id = ?", player.id).one().v;
		return ok({ version, saved_at: now });
	}

	_latestSave(playerId) {
		const row = this.sql.exec("SELECT id, data, summary, saved_at FROM saves WHERE player_id = ? ORDER BY id DESC LIMIT 1",
			playerId).toArray()[0];
		if (!row) return null;
		return { data: row.data, summary: JSON.parse(row.summary || "{}"), saved_at: row.saved_at, version: row.id };
	}

	downloadSave(token) {
		const player = this._player(token);
		if (!player) return fail(401, "unknown_player");
		return ok(this._latestSave(player.id) || { data: null });
	}

	// A recovery code gets the account (its token) and its newest save back, e.g. on a new device
	recover(code) {
		const clean = String(code || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
		const formatted = clean.startsWith("RC") ? "RC-" + (clean.slice(2).match(/.{1,4}/g) || []).join("-") : "";
		const player = this.sql.exec("SELECT id, token, name, recovery FROM players WHERE recovery = ?", formatted).toArray()[0];
		if (!player) return fail(404, "unknown_code");
		return ok({ player_id: player.id, token: player.token, name: player.name, recovery_code: player.recovery,
			save: this._latestSave(player.id) });
	}

	// ───────── Arena ─────────

	_arenaRow(playerId) {
		return this.sql.exec("SELECT * FROM arena WHERE player_id = ?", playerId).toArray()[0] || null;
	}

	_arenaFightsLeft(playerId, now) {
		const used = this.sql.exec("SELECT COUNT(*) AS n FROM arena_fights WHERE attacker = ? AND day = ?",
			playerId, Math.floor(now / DAY_MS)).one().n;
		return Math.max(ARENA_FIGHTS_PER_DAY - used, 0);
	}

	arenaState(token) {
		const top = this.sql.exec(`SELECT p.name, a.rating, a.wins, a.losses FROM arena a JOIN players p ON p.id = a.player_id
			ORDER BY a.rating DESC, a.updated_at ASC LIMIT ?`, LIST_SIZE).toArray();
		const player = this._player(token);
		let me = null;
		if (player) {
			const row = this._arenaRow(player.id);
			const rating = row ? row.rating : ARENA_START_RATING;
			me = {
				name: player.name, rating, wins: row ? row.wins : 0, losses: row ? row.losses : 0, has_team: !!row,
				rank: row ? this.sql.exec("SELECT COUNT(*) AS n FROM arena WHERE rating > ?", rating).one().n + 1 : 0,
				fights_left: this._arenaFightsLeft(player.id, Date.now()),
				fights_per_day: ARENA_FIGHTS_PER_DAY,
			};
		}
		return ok({ me, top, players: this.sql.exec("SELECT COUNT(*) AS n FROM arena").one().n });
	}

	// The defense team other players will fight. The game sends it before every attack, so it stays current.
	arenaTeam(token, team, power) {
		const player = this._player(token);
		if (!player) return fail(401, "unknown_player");
		const text = JSON.stringify(Array.isArray(team) ? team : []);
		if (text.length > ARENA_TEAM_MAX) return fail(400, "team_too_big");
		this.sql.exec(`INSERT INTO arena (player_id, team, power, updated_at) VALUES (?, ?, ?, ?)
			ON CONFLICT (player_id) DO UPDATE SET team = excluded.team, power = excluded.power, updated_at = excluded.updated_at`,
			player.id, text, Math.max(Math.floor(Number(power) || 0), 0), Date.now());
		return ok({ ok: true });
	}

	// Up to ARENA_OPPONENTS players picked at random from the ARENA_POOL closest in rating (never yourself).
	// The game fills any gap with practice bots.
	arenaOpponents(token) {
		const player = this._player(token);
		if (!player) return fail(401, "unknown_player");
		const mine = this._arenaRow(player.id);
		const rating = mine ? mine.rating : ARENA_START_RATING;
		const pool = this.sql.exec(`SELECT a.player_id, p.name, a.rating, a.power, a.team FROM arena a
			JOIN players p ON p.id = a.player_id WHERE a.player_id != ? ORDER BY ABS(a.rating - ?) ASC LIMIT ?`,
			player.id, rating, ARENA_POOL).toArray();
		for (let i = pool.length - 1; i > 0; i--) {
			const j = Math.floor(Math.random() * (i + 1));
			[pool[i], pool[j]] = [pool[j], pool[i]];
		}
		const opponents = pool.slice(0, ARENA_OPPONENTS).map((o) => ({
			player_id: o.player_id, name: o.name, rating: o.rating, power: o.power, team: JSON.parse(o.team),
		}));
		opponents.sort((a, b) => b.rating - a.rating);
		return ok({ opponents });
	}

	arenaStart(token, opponentId) {
		const player = this._player(token);
		if (!player) return fail(401, "unknown_player");
		if (!this._arenaRow(player.id)) return fail(409, "no_team");
		const defender = String(opponentId || "");
		if (defender !== "bot" && (defender === player.id || !this._arenaRow(defender))) return fail(404, "unknown_opponent");
		const now = Date.now();
		const left = this._arenaFightsLeft(player.id, now);
		if (left <= 0) return fail(409, "no_fights_left");
		const fightId = crypto.randomUUID();
		const seed = crypto.getRandomValues(new Uint32Array(1))[0] & 0x7fffffff;
		this.sql.exec("INSERT INTO arena_fights (id, attacker, defender, day, seed, issued_at) VALUES (?, ?, ?, ?, ?, ?)",
			fightId, player.id, defender, Math.floor(now / DAY_MS), seed, now);
		return ok({ fight_id: fightId, seed, fights_left: left - 1 });
	}

	arenaSubmit(token, fightId, win) {
		const player = this._player(token);
		if (!player) return fail(401, "unknown_player");
		const now = Date.now();
		const fight = this.sql.exec("SELECT * FROM arena_fights WHERE id = ? AND attacker = ?",
			String(fightId || ""), player.id).toArray()[0];
		if (!fight) return fail(404, "unknown_fight");
		if (fight.submitted_at !== null) return fail(409, "already_submitted");
		if (now - fight.issued_at > ATTEMPT_TTL_MS) return fail(409, "fight_expired");
		const won = win === true || win === 1 || win === "true";
		this.sql.exec("UPDATE arena_fights SET win = ?, submitted_at = ? WHERE id = ?", won ? 1 : 0, now, fight.id);

		const me = this._arenaRow(player.id);
		const bot = fight.defender === "bot";
		const them = bot ? null : this._arenaRow(fight.defender);
		const theirRating = them ? them.rating : me.rating - ARENA_BOT_GAP;
		const expected = 1 / (1 + Math.pow(10, (theirRating - me.rating) / 400));
		const k = bot ? ARENA_BOT_K : ARENA_K;
		const change = Math.round(k * ((won ? 1 : 0) - expected));
		const rating = Math.max(me.rating + change, 0);
		this.sql.exec(`UPDATE arena SET rating = ?, wins = wins + ?, losses = losses + ? WHERE player_id = ?`,
			rating, won ? 1 : 0, won ? 0 : 1, player.id);
		if (them) {
			this.sql.exec("UPDATE arena SET rating = MAX(rating - ?, 0) WHERE player_id = ?", Math.round(change / 2), them.player_id);
		}
		return ok({ rating, change, wins: me.wins + (won ? 1 : 0), losses: me.losses + (won ? 0 : 1) });
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
		const recovery = this._newCode();
		this.sql.exec("INSERT INTO players (id, token, name, created_at, recovery) VALUES (?, ?, ?, ?, ?)",
			id, token, cleanName(name), Date.now(), recovery);
		return ok({ player_id: id, token, recovery_code: recovery });
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
