extends Node
## Part-time jobs (commissions). A running job only stores who works it and when they started, so nothing
## ticks in the background: finished shifts are paid out by resolve_finished(), which runs at game start,
## when returning Home, and while the Commissions tab is open. Autoload name: Commissions
##
## Save data: GameState.data.commissions = {commission_id: {"uid": int, "started_at": unix seconds}}

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func _jobs() -> Dictionary:
	return GameState.data.commissions

func _now() -> int:
	return int(Time.get_unix_time_from_system())

func get_job(c: CommissionData) -> Dictionary:
	return _jobs().get(String(c.id), {})

func is_active(c: CommissionData) -> bool:
	return not get_job(c).is_empty()

## The commission this friend is working, or null
func worker_commission(uid: int) -> CommissionData:
	for c in DB.commissions:
		if int(get_job(c).get("uid", 0)) == uid:
			return c
	return null

## Seconds until the shift ends (0 = done). If the clock was turned back, the shift restarts from now.
func time_left(c: CommissionData) -> int:
	var job := get_job(c)
	if job.is_empty():
		return 0
	if _now() < int(job.started_at):
		job.started_at = _now()
		GameState.request_save()
	return maxi(int(job.started_at) + c.duration_seconds - _now(), 0)

func requirement_met(c: CommissionData, uid: int) -> bool:
	var friend := GameState.get_character(uid)
	if friend == null:
		return false
	if c.required_class >= 0 and friend.char_class != c.required_class:
		return false
	if not c.required_stat.is_empty() and GameState.get_unit_stats(uid).get(c.required_stat, 0) < c.required_value:
		return false
	return true

func can_assign(c: CommissionData, uid: int) -> bool:
	return not is_active(c) and worker_commission(uid) == null and requirement_met(c, uid)

func start(c: CommissionData, uid: int) -> bool:
	if not can_assign(c, uid):
		return false
	_jobs()[String(c.id)] = {"uid": uid, "started_at": _now()}
	GameState.request_save()
	return true

## Calls the worker back early; they aren't paid
func cancel(c: CommissionData) -> void:
	_jobs().erase(String(c.id))
	GameState.request_save()

## Pays out every finished shift. Returns one report per shift:
## {commission, worker, money, materials, exp, credit_cards, incident, level, friendship}
func resolve_finished() -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	# Drop shifts on commissions that no longer exist (removed from Data/commissions/), freeing their workers
	var known := DB.commissions.map(func(c): return String(c.id))
	for id in _jobs().keys():
		if not known.has(id):
			_jobs().erase(id)
	for c in DB.commissions:
		var job := get_job(c)
		if job.is_empty() or time_left(c) > 0:
			continue
		_jobs().erase(String(c.id))
		var uid := int(job.uid)
		var worker := GameState.get_character(uid)
		if worker:  # skip shifts whose friend no longer exists
			reports.append(_pay(c, uid, worker))
	if not reports.is_empty():
		GameState.save_game()
	return reports

func _pay(c: CommissionData, uid: int, worker: CharacterData) -> Dictionary:
	var report := {
		"commission": c.display_name, "worker": worker.display_name, "money": c.reward_money,
		"materials": {}, "exp": c.exp_reward, "credit_cards": 0, "incident": "", "level": 0, "friendship": 0,
	}
	for key in c.reward_materials:
		var range_v: Vector2i = c.reward_materials[key]
		report.materials[key] = _rng.randi_range(range_v.x, range_v.y)
	if _rng.randf() < c.credit_card_chance:
		report.credit_cards += 1

	var incident := _roll_incident(c, worker)
	if incident:
		report.incident = incident.text.format({"name": worker.display_name})
		report.money = roundi(report.money * incident.money_multiplier) + incident.money_bonus
		report.credit_cards += incident.credit_cards
		for key in incident.materials:
			report.materials[key] = report.materials.get(key, 0) + incident.materials[key]
		report.exp += incident.exp_bonus
		report.friendship = incident.friendship_bonus

	report.money = maxi(report.money, -GameState.get_money())  # docked pay can't push Money below 0
	GameState.add_money(report.money)
	for key in report.materials:
		if report.materials[key] > 0:
			GameState.add_material(key, report.materials[key])
	if report.credit_cards > 0:
		GameState.add_credit_cards(report.credit_cards)
	if report.friendship > 0:
		GameState.add_friendship(uid, report.friendship)
	if GameState.add_exp(uid, report.exp) > 0:
		report.level = int(GameState.get_owned(uid).level)
	return report

## Picks at most one incident: incident_chance decides whether one happens, weights decide which.
## Friend-specific incidents only count for that friend.
func _roll_incident(c: CommissionData, worker: CharacterData) -> CommissionIncident:
	var pool := c.incidents.filter(func(i): return i != null and (i.character_id == &"" or i.character_id == worker.id))
	if pool.is_empty() or _rng.randf() >= c.incident_chance:
		return null
	var total := 0
	for i in pool:
		total += i.weight
	var roll := _rng.randi_range(0, total - 1)
	for i in pool:
		roll -= i.weight
		if roll < 0:
			return i
	return pool.back()
