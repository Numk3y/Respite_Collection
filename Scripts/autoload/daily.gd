extends Node
## The daily loop: a 7-day check-in calendar with a streak, daily missions that fill an activity bar with five
## chests, weekly missions, and a bonus that changes with the day of the week. Autoload name: Daily
##
## Days reset at RESET_HOUR local time (gacha style, so a late night still counts as "today"); weeks reset on
## Monday at the same hour. Progress comes from GameState.add_stat: every lifetime counter that goes up also counts
## toward today's and this week's missions (see GameState.stat_added), so a mission only needs a stat key.
## Daily missions need no claiming: finishing one adds its points to the activity bar, and the chests on the bar are
## claimed. Weekly missions are claimed one by one.
##
## Rewards are lists of [kind, amount] where kind is "money", "credit_card", "parts" or a material key, the same
## kinds CurrencyChip draws icons for.
##
## Save data: GameState.data.daily (see _defaults()). Text: Terms "daily_*".

signal changed  # anything here changed: a mission moved, something was claimed, or the day/week rolled over
signal mission_completed(title: String, points: int)  # a daily mission just got done (Main shows a toast)
signal weekly_completed(title: String)
signal achievement_reached(title: String)  # a counted achievement just reached its next tier

const RESET_HOUR := 4
const DAY := 86400

# ───────── Check-in ─────────
## One reward per check-in, in a 7-day cycle. A missed day doesn't reset the cycle (only the streak), so nobody
## gets punished out of the big day-7 reward.
const CHECKIN_REWARDS := [
	[["money", 1000]],
	[["snack", 5]],
	[["credit_card", 1]],
	[["parts", 10]],
	[["coffee", 3]],
	[["money", 2500]],
	[["credit_card", 2]],
]

## Streak milestones: paid once each per streak (a broken streak can earn them again)
const STREAK_MILESTONES := [
	{"days": 7, "reward": [["credit_card", 2]]},
	{"days": 14, "reward": [["credit_card", 3]]},
	{"days": 30, "reward": [["credit_card", 5]]},
]
## After the last milestone, every this many more days pays the last milestone's reward again
const STREAK_REPEAT_DAYS := 30
## A free single recruit each day once the streak is at least this long (and today's check-in is done)
const FREE_PULL_STREAK := 2

# ───────── Daily missions ─────────
## stat: the GameState lifetime counter it watches (counted from today's reset); goal; points on the activity bar
const MISSIONS := {
	"checkin": {"stat": "checkins", "goal": 1, "points": 20},
	"wins": {"stat": "wins", "goal": 3, "points": 20},
	"flawless": {"stat": "flawless_wins", "goal": 1, "points": 20},
	"shifts": {"stat": "commissions", "goal": 2, "points": 20},
	"collect": {"stat": "shifts_done", "goal": 2, "points": 20},
	"casino": {"stat": "casino_games", "goal": 3, "points": 20},
	"power_up": {"stat": "power_ups", "goal": 1, "points": 20},
	"gear": {"stat": "gear_work", "goal": 1, "points": 20},
	"recruit": {"stat": "pulls", "goal": 1, "points": 20},
	"ultimates": {"stat": "manual_ultimates", "goal": 3, "points": 20},
	"arena": {"stat": "arena_battles", "goal": 2, "points": 20},
}
const FIXED_MISSIONS := ["checkin", "wins"]  # every day
const ROTATING_COUNT := 3  # plus this many picked from the rest, different each day
const MAX_POINTS := 100
## The activity bar's chests: claimable once today's points reach `points`
const CHESTS := [
	{"points": 20, "reward": [["money", 800]]},
	{"points": 40, "reward": [["snack", 3]]},
	{"points": 60, "reward": [["coffee", 2], ["parts", 5]]},
	{"points": 80, "reward": [["money", 1500]]},
	{"points": 100, "reward": [["credit_card", 1], ["gossip", 1]]},
]

# ───────── Weekly missions ─────────
const WEEKLY := [
	{"id": "w_wins", "stat": "wins", "goal": 20, "reward": [["credit_card", 1], ["money", 2000]]},
	{"id": "w_full", "stat": "full_days", "goal": 5, "reward": [["credit_card", 2]]},
	{"id": "w_checkins", "stat": "checkins", "goal": 6, "reward": [["gossip", 3]]},
	{"id": "w_collect", "stat": "shifts_done", "goal": 10, "reward": [["money", 2500], ["gossip", 2]]},
	{"id": "w_pulls", "stat": "pulls", "goal": 10, "reward": [["money", 1500], ["coffee", 3]]},
	{"id": "w_casino", "stat": "casino_games", "goal": 15, "reward": [["money", 1500]]},
	{"id": "w_gear", "stat": "gear_work", "goal": 5, "reward": [["parts", 25]]},
]

# ───────── Day-of-week bonus ─────────
## weekday: 0 = Sunday. Multipliers: money (battle Money), materials (battle materials), drops (gear drop chance),
## exp (friend EXP from battles), shift_money (commission pay), bond (Friendship from battles and shifts).
## Account EXP is never boosted, so the story's level pacing stays as planned.
const DAY_BONUSES := {
	0: {"key": "weekend", "money": 1.5, "materials": 2.0},
	1: {"key": "money", "money": 1.5},
	2: {"key": "materials", "materials": 2.0},
	3: {"key": "drops", "drops": 2.0},
	4: {"key": "exp", "exp": 1.5},
	5: {"key": "shifts", "shift_money": 1.5},
	6: {"key": "bond", "bond": 2.0},
}

var _last_day := -1  # to notice the 4 a.m. rollover while the game stays open

func _ready() -> void:
	GameState.stat_added.connect(_on_stat_added)
	var timer := Timer.new()
	timer.wait_time = 20.0
	timer.autostart = true
	timer.timeout.connect(_check_rollover)
	add_child(timer)

# ───────── Time ─────────

## Local wall-clock time as unix seconds (the time zone's offset added)
func _local_now() -> int:
	return int(Time.get_unix_time_from_datetime_dict(Time.get_datetime_dict_from_system(false)))

## Days since 1970 in local time, counted from RESET_HOUR
func today() -> int:
	return floori(float(_local_now() - RESET_HOUR * 3600) / DAY)

## Weeks starting on Monday (day 0, 1970-01-01, was a Thursday)
func this_week() -> int:
	return floori(float(today() + 3) / 7.0)

## 0 = Sunday ... 6 = Saturday, for the current game day
func weekday(day: int = -1) -> int:
	return posmod((today() if day < 0 else day) + 4, 7)

func seconds_to_reset() -> int:
	return maxi((today() + 1) * DAY + RESET_HOUR * 3600 - _local_now(), 0)

func seconds_to_weekly_reset() -> int:
	var next_monday := (this_week() + 1) * 7 - 3
	return maxi(next_monday * DAY + RESET_HOUR * 3600 - _local_now(), 0)

func _check_rollover() -> void:
	if today() != _last_day:
		_data()  # rolls the day over and emits changed

# ───────── Save data ─────────

static func _defaults() -> Dictionary:
	return {
		"day": -1, "week": -1,
		"missions": [],  # today's mission ids
		"counts": {},  # stat -> amount since today's reset
		"chests": {},  # chest index (as a string) -> true once claimed today
		"full_counted": false,  # today's 100 points already counted toward the weekly "full_days"
		"week_counts": {}, "week_claimed": {},
		"checkin_last": -999, "checkin_total": 0, "streak": 0, "best_streak": 0,
		"streak_paid": 0,  # the streak length whose milestone was paid last (this streak)
		"freeze_week": -1,  # the week the streak freeze was last used
		"free_pull_day": -1,  # the day the free daily recruit was last used
	}

## The save's daily block, filled in and rolled over to today if needed
func _data() -> Dictionary:
	var d: Dictionary = GameState.data.get_or_add("daily", {})
	var fresh := _defaults()
	for key in fresh:
		if not d.has(key):
			d[key] = fresh[key]
	var day := today()
	var rolled := false
	if int(d.week) != this_week():
		d.week = this_week()
		d.week_counts = {}
		d.week_claimed = {}
		rolled = true
	if int(d.day) != day:
		d.day = day
		d.counts = {}
		d.chests = {}
		d.full_counted = false
		d.missions = _roll_missions(day)
		rolled = true
	_last_day = day
	if rolled:
		GameState.request_save()
		changed.emit.call_deferred()
	return d

## The fixed missions plus ROTATING_COUNT others, picked by the day number so everyone gets the same set that day
## and reloading can't reroll it. Missions that can't be done yet (no Parts for gear, no Credit Card to recruit,
## Auto Ultimate on) are left out of the draw.
func _roll_missions(day: int) -> Array:
	var pool: Array = MISSIONS.keys().filter(func(id): return not FIXED_MISSIONS.has(id) and _can_offer(id))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("respite_daily_%d" % day)
	for i in range(pool.size() - 1, 0, -1):  # Fisher-Yates with our own seeded RNG
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var out: Array = FIXED_MISSIONS.duplicate()
	out.append_array(pool.slice(0, ROTATING_COUNT))
	return out

func _can_offer(id: String) -> bool:
	match id:
		"gear":
			return GameState.get_parts() > 0 or GameState.get_account_level() >= 5
		"recruit":
			return GameState.get_credit_cards() >= GameState.CREDIT_CARDS_PER_PULL
		"ultimates":
			return not bool(GameState.get_setting("auto_ultimate", true))
		"arena":
			return WorldBoss.is_registered() and GameState.get_account_level() >= Arena.MIN_ACCOUNT_LEVEL
		"flawless", "casino", "shifts", "collect", "power_up":
			return true
	return true

func _on_stat_added(key: String, amount: int) -> void:
	var d := _data()
	var before := points()
	d.counts[key] = int(d.counts.get(key, 0)) + amount
	d.week_counts[key] = int(d.week_counts.get(key, 0)) + amount
	for id: String in d.missions:
		var m: Dictionary = MISSIONS.get(id, {})
		if m.is_empty() or String(m.stat) != key:
			continue
		var now := int(d.counts[key])
		if now >= int(m.goal) and now - amount < int(m.goal):
			mission_completed.emit(mission_title(id), int(m.points))
	for w: Dictionary in WEEKLY:
		if String(w.stat) == key:
			var now := int(d.week_counts[key])
			if now >= int(w.goal) and now - amount < int(w.goal):
				weekly_completed.emit(weekly_title(w))
	for a: Dictionary in Achievements.LIST:
		if String(a.get("stat", "")) == key and not Achievements.is_complete(a):
			var total := GameState.get_stat(key)
			var target := Achievements.goal(a)
			if total >= target and total - amount < target:
				achievement_reached.emit(Achievements.title(a))
	# A full bar for the first time today counts toward the weekly mission (which itself goes through add_stat)
	if before < MAX_POINTS and points() >= MAX_POINTS and not bool(d.full_counted):
		d.full_counted = true
		GameState.add_stat("full_days")
	changed.emit()

# ───────── Daily missions ─────────

func today_missions() -> Array:
	return _data().missions

func mission_progress(id: String) -> int:
	var m: Dictionary = MISSIONS.get(id, {})
	if m.is_empty():
		return 0
	return mini(int(_data().counts.get(String(m.stat), 0)), int(m.goal))

func mission_goal(id: String) -> int:
	return int(MISSIONS.get(id, {}).get("goal", 1))

func mission_done(id: String) -> bool:
	return mission_progress(id) >= mission_goal(id)

func mission_points(id: String) -> int:
	return int(MISSIONS.get(id, {}).get("points", 0))

func mission_title(id: String) -> String:
	return Terms.t("daily_m_" + id, {"goal": mission_goal(id)})

## Today's activity points: the points of every finished mission
func points() -> int:
	var total := 0
	for id: String in _data().missions:
		if mission_done(id):
			total += mission_points(id)
	return mini(total, MAX_POINTS)

func chest_claimed(i: int) -> bool:
	return _data().chests.has(str(i))

func chest_ready(i: int) -> bool:
	return i >= 0 and i < CHESTS.size() and points() >= int(CHESTS[i].points) and not chest_claimed(i)

## Pays out a chest; returns its reward, or [] if it isn't ready
func claim_chest(i: int) -> Array:
	if not chest_ready(i):
		return []
	_data().chests[str(i)] = true
	var reward: Array = CHESTS[i].reward
	grant(reward)
	changed.emit()
	return reward

## Every chest that's ready, together; returns everything granted
func claim_all_chests() -> Array:
	var out: Array = []
	for i in CHESTS.size():
		out.append_array(claim_chest(i))
	return out

# ───────── Weekly missions ─────────

func weekly_progress(w: Dictionary) -> int:
	return mini(int(_data().week_counts.get(String(w.stat), 0)), int(w.goal))

func weekly_done(w: Dictionary) -> bool:
	return weekly_progress(w) >= int(w.goal)

func weekly_claimed(w: Dictionary) -> bool:
	return _data().week_claimed.has(String(w.id))

func weekly_title(w: Dictionary) -> String:
	return Terms.t("daily_" + String(w.id), {"goal": int(w.goal)})

func claim_weekly(w: Dictionary) -> Array:
	if not weekly_done(w) or weekly_claimed(w):
		return []
	_data().week_claimed[String(w.id)] = true
	grant(w.reward)
	changed.emit()
	return w.reward

func claim_all_weekly() -> Array:
	var out: Array = []
	for w: Dictionary in WEEKLY:
		out.append_array(claim_weekly(w))
	return out

# ───────── Check-in ─────────

func checked_in_today() -> bool:
	return int(_data().checkin_last) == today()

func checkin_total() -> int:
	return int(_data().checkin_total)

## The streak freeze: once a week, one missed day doesn't break the streak (it's used up by the check-in after it)
func freeze_ready() -> bool:
	return int(_data().freeze_week) != this_week()

## The streak as it stands: days in a row checked in. Still alive if the last check-in was today or yesterday, or
## the day before that while the freeze is ready.
func streak() -> int:
	var d := _data()
	var last := int(d.checkin_last)
	if last >= today() - 1 or (last == today() - 2 and freeze_ready()):
		return int(d.streak)
	return 0

func best_streak() -> int:
	return int(_data().best_streak)

## The next streak milestone not yet paid in this streak: {"days", "reward"}
func next_milestone() -> Dictionary:
	var paid := int(_data().streak_paid)
	for m: Dictionary in STREAK_MILESTONES:
		if int(m.days) > paid:
			return m
	var last: Dictionary = STREAK_MILESTONES.back()
	var days := int(last.days) + STREAK_REPEAT_DAYS
	while days <= paid:
		days += STREAK_REPEAT_DAYS
	return {"days": days, "reward": last.reward}

## Today's check-in: the next reward in the 7-day cycle, plus a streak milestone when one is reached. Returns
## {"day": 1-7, "reward": [...], "streak": n, "milestone": [...] or [], "froze": bool}, or {} if already checked in.
func check_in() -> Dictionary:
	var d := _data()
	if checked_in_today():
		return {}
	var index := int(d.checkin_total) % CHECKIN_REWARDS.size()
	var gap := today() - int(d.checkin_last)
	var froze := false
	if gap == 1:
		d.streak = int(d.streak) + 1
	elif gap == 2 and freeze_ready() and int(d.streak) > 0:
		d.streak = int(d.streak) + 1
		d.freeze_week = this_week()
		froze = true
	else:
		d.streak = 1
		d.streak_paid = 0
	d.best_streak = maxi(int(d.best_streak), int(d.streak))
	d.checkin_last = today()
	d.checkin_total = int(d.checkin_total) + 1
	var reward: Array = CHECKIN_REWARDS[index]
	grant(reward)
	var milestone: Array = []
	var next := next_milestone()
	if int(d.streak) >= int(next.days):
		d.streak_paid = int(next.days)
		milestone = next.reward
		grant(milestone)
	GameState.add_stat("checkins")  # the daily "check in" mission and the weekly one
	GameState.save_game()
	return {"day": index + 1, "reward": reward, "streak": int(d.streak), "milestone": milestone, "froze": froze}

# ───────── Free daily recruit ─────────

func free_pull_unlocked() -> bool:
	return checked_in_today() and streak() >= FREE_PULL_STREAK

func free_pull_available() -> bool:
	return free_pull_unlocked() and int(_data().free_pull_day) != today()

## Marks today's free recruit as used (Gacha.pull does this); false if it isn't available
func use_free_pull() -> bool:
	if not free_pull_available():
		return false
	_data().free_pull_day = today()
	changed.emit()
	return true

# ───────── Day-of-week bonus ─────────

func bonus(kind: String) -> float:
	return float(DAY_BONUSES[weekday()].get(kind, 1.0))

func bonus_key(day: int = -1) -> String:
	return String(DAY_BONUSES[weekday(day)].key)

## "Money x1.5 from battles" for today (or another day)
func bonus_text(day: int = -1) -> String:
	return Terms.t("daily_bonus_" + bonus_key(day))

## The line for the battle results when today's bonus touched battle rewards ("" on a commission day)
func battle_bonus_line() -> String:
	var b: Dictionary = DAY_BONUSES[weekday()]
	for kind in ["money", "materials", "drops", "exp", "bond"]:
		if b.has(kind):
			return Terms.t("daily_battle_bonus", {"bonus": bonus_text()})
	return ""

# ───────── Badges ─────────

## Things waiting in the Daily window: the check-in, ready chests, finished weekly missions and achievements
func claimable_count() -> int:
	var count := 0 if checked_in_today() else 1
	for i in CHESTS.size():
		if chest_ready(i):
			count += 1
	for w: Dictionary in WEEKLY:
		if weekly_done(w) and not weekly_claimed(w):
			count += 1
	return count + Achievements.claimable_count()

# ───────── Rewards ─────────

static func grant(reward: Array) -> void:
	for item: Array in reward:
		var kind := String(item[0])
		var amount := int(item[1])
		match kind:
			"money":
				GameState.add_money(amount)
			"credit_card":
				GameState.add_credit_cards(amount)
			"parts":
				GameState.add_parts(amount)
			_:
				GameState.add_material(kind, amount)

## "1,000 Money", "2 Credit Cards", "5 Snacks"
static func item_text(item: Array) -> String:
	var kind := String(item[0])
	var amount := int(item[1])
	var word: String
	match kind:
		"money":
			word = Terms.term("money")
		"credit_card":
			word = Terms.credit_card_word(amount)
		"parts":
			word = Terms.term("parts")
		_:
			word = Terms.material_name(kind)
	return "%s %s" % [Terms.number(amount), word]

static func reward_text(reward: Array) -> String:
	return ", ".join(PackedStringArray(reward.map(func(item): return item_text(item))))

## "5h 12m"
static func format_time(seconds: int) -> String:
	var days := seconds / DAY
	var h := (seconds % DAY) / 3600
	var m := (seconds % 3600) / 60
	if days > 0:
		return "%dd %dh" % [days, h]
	if h > 0:
		return "%dh %dm" % [h, m]
	return "%dm" % maxi(m, 1)
