extends Node
## Talks to the world boss server (Respite_Collection/server, on Cloudflare). Autoload name: WorldBoss
## The server keeps the shared HP and everyone's damage; this game runs the fights and grants the rewards.
## Each player gets a server account the first time they open the Event tab (a name, then a token kept in the save).
##
## Testing against `npx wrangler dev` on this PC: add ?localboss to the web address, or set the environment
## variable RESPITE_BOSS_URL=http://localhost:8787 for desktop runs.

const SERVER_URL := "https://respite-boss.numk3y.workers.dev"
const LOCAL_URL := "http://localhost:8787"
## Raise this together with MIN_VERSION in server/wrangler.toml when an update changes how boss damage works:
## builds older than MIN_VERSION are then told to refresh instead of reporting damage under the old rules
const GAME_VERSION := 1
const TIMEOUT_SEC := 10.0
const NAME_MAX := 16

var update_required := false  # the server turned this build away (see GAME_VERSION)
var _claiming := false
var _submitting := false

func _url() -> String:
	if OS.has_feature("web"):
		if str(JavaScriptBridge.eval("window.location.search", true)).contains("localboss"):
			return LOCAL_URL
		return SERVER_URL
	var override := OS.get_environment("RESPITE_BOSS_URL")
	return override if not override.is_empty() else SERVER_URL

func _save() -> Dictionary:
	return GameState.data.world_boss

func is_registered() -> bool:
	return not str(_save().token).is_empty()

func player_name() -> String:
	return str(_save().name)

## One call to the server. Returns {"ok": bool, "status": int, "data": Dictionary}; status 0 = couldn't connect.
func call_server(method: HTTPClient.Method, path: String, body: Dictionary = {}) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SEC
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json", "X-Game-Version: %d" % GAME_VERSION])
	if is_registered():
		headers.append("Authorization: Bearer %s" % _save().token)
	var payload := JSON.stringify(body) if method == HTTPClient.METHOD_POST else ""
	if http.request(_url() + path, headers, method, payload) != OK:
		http.queue_free()
		return {"ok": false, "status": 0, "data": {}}
	var response: Array = await http.request_completed
	http.queue_free()
	var status: int = response[1] if response[0] == HTTPRequest.RESULT_SUCCESS else 0
	var parsed = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if status == 426:
		update_required = true
	return {"ok": status == 200, "status": status, "data": parsed if parsed is Dictionary else {}}

## Makes the server account. Returns false if the server couldn't be reached.
func register(display_name: String) -> bool:
	var clean := display_name.strip_edges().left(NAME_MAX)
	var r := await call_server(HTTPClient.METHOD_POST, "/register", {"name": clean})
	if not r.ok:
		return false
	_save().player_id = str(r.data.player_id)
	_save().token = str(r.data.token)
	_save().name = clean
	GameState.save_game()
	return true

## The live event: {"ok", "status", "data": {event, top, recent, me}}. Reports any fights still waiting first.
func fetch() -> Dictionary:
	await submit_pending()
	return await call_server(HTTPClient.METHOD_GET, "/boss")

## Uses up one of today's attempts. data = {attempt_id, seed, attempts_left}
func start_attempt() -> Dictionary:
	return await call_server(HTTPClient.METHOD_POST, "/boss/start")

## Keeps a finished fight in the save until the server has it, then sends it.
## Returns the server's answer ({damage, hp, defeated}) or {} if it has to wait for a later try.
func report_fight(attempt_id: String, damage: int) -> Dictionary:
	_save().pending.append({"attempt_id": attempt_id, "damage": damage})
	GameState.save_game()
	return await submit_pending(attempt_id)

## Sends every fight not yet reported. A fight the server refuses (expired, already in) is dropped; one that
## couldn't be sent stays for the next try. Returns the answer for `wanted`, if given and sent.
func submit_pending(wanted: String = "") -> Dictionary:
	if _submitting:
		return {}
	_submitting = true
	var answer := {}
	var pending: Array = _save().pending
	for fight in pending.duplicate():
		var r := await call_server(HTTPClient.METHOD_POST, "/boss/submit", fight)
		if r.status == 0 or r.status >= 500 or r.status == 426:
			break  # offline or server trouble: keep the rest for later
		pending.erase(fight)
		if r.ok and str(fight.attempt_id) == wanted:
			answer = r.data
	GameState.save_game()
	_submitting = false
	return answer

## Rewards from finished events the player hit at least once, granted here. Results for an event this build
## doesn't have yet are kept in the save until it does. Returns [{event, rank, players, rewards: [EventReward]}].
func collect_rewards() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _claiming or not is_registered():
		return out
	_claiming = true
	var r := await call_server(HTTPClient.METHOD_POST, "/boss/claim")
	var waiting: Array = _save().unclaimed
	if r.ok:
		waiting.append_array(r.data.get("rewards", []))
	for result in waiting.duplicate():
		var event: EventData = DB.events.get(StringName(str(result.boss_key)))
		if event == null:
			continue
		waiting.erase(result)
		if not result.defeated or int(result.damage) <= 0:
			continue
		var rank := int(result.rank)
		var rewards: Array[EventReward] = []
		for reward in [event.reward_all, event.top_reward(rank)]:
			if reward and not reward.is_empty():
				reward.grant()
				rewards.append(reward)
		out.append({"event": event, "rank": rank, "players": int(result.players), "damage": int(result.damage), "rewards": rewards})
	GameState.save_game()
	_claiming = false
	return out
