extends Node
## Cloud save on the game server (the same account as the World Boss and Arena). Autoload name: CloudSave
## - Uploads the save every UPLOAD_EVERY seconds, but only when its content changed since the last upload
##   (GameState.updated_at), so a game left open on Home costs nothing
## - Uploads soon after the moments that would hurt most to lose (a recruit, a level up) and when the tab or
##   window loses focus (the player may be closing it)
## - At startup, check_cloud() says whether the cloud has a newer save than this device, so Main can ask which to keep
## - recover(code) brings an account and its newest save to a new device with the recovery code from Settings
## Nothing here ever overwrites the local save by itself: restoring is always the player's choice.
## The last upload is remembered in GameState.data.cloud = {"uploaded_at": the save's updated_at, "at": unix time}.

signal status_changed  # an upload finished (or failed): Settings shows the last cloud save

const UPLOAD_EVERY := 300.0  # 5 minutes
const SOON_DELAY := 20.0  # after a recruit or a level up
const FOCUS_OUT_MIN_GAP := 30  # seconds since the last upload before leaving the tab uploads again
const CONFLICT_MARGIN := 5  # seconds of difference that still count as "the same save"

var last_error := ""  # "" when the last upload worked; otherwise a short reason for Settings
var _uploading := false
var _soon: SceneTreeTimer

func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = UPLOAD_EVERY
	timer.autostart = true
	timer.timeout.connect(upload_if_changed)
	add_child(timer)
	Gacha.pulled.connect(func(_r): upload_soon())
	GameState.account_changed.connect(upload_soon)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _cloud().get("at", 0) < Time.get_unix_time_from_system() - FOCUS_OUT_MIN_GAP:
		upload_if_changed()

func _cloud() -> Dictionary:
	return GameState.data.get_or_add("cloud", {})

## Unix time of the last successful upload (0 = never)
func last_upload() -> int:
	return int(_cloud().get("at", 0))

func has_unsaved_changes() -> bool:
	return GameState.updated_at() > int(_cloud().get("uploaded_at", -1))

func upload_soon() -> void:
	if _soon == null or _soon.time_left <= 0.0:
		_soon = get_tree().create_timer(SOON_DELAY)
		_soon.timeout.connect(upload_if_changed)

## A few numbers to tell two saves apart when the player has to pick one
static func summary_of(save: Dictionary) -> Dictionary:
	var stats: Dictionary = save.get("stats", {})
	return {
		"account_level": int(save.get("account_level", 1)),
		"friends": (save.get("owned", []) as Array).size(),
		"pulls": int(stats.get("pulls", 0)),
		"cleared": (save.get("cleared_stages", {}) as Dictionary).size(),
		"updated_at": int(save.get("updated_at", 0)),
	}

## Sends the save if it changed since the last upload (and there's an account; it's made here if the player has
## a name but no account yet). Returns true if the cloud now has this save.
func upload_if_changed() -> bool:
	if _uploading or not GameState.data.get("starter_chosen", false):
		return false
	if not has_unsaved_changes():
		return true
	if not await WorldBoss.ensure_registered():
		last_error = "offline" if not WorldBoss.player_name().is_empty() else "no_name"
		status_changed.emit()
		return false
	return await upload_now()

## Uploads right away, changed or not (Settings' "Save to cloud now")
func upload_now() -> bool:
	if _uploading or not await WorldBoss.ensure_registered():
		return false
	_uploading = true
	GameState.save_game()  # stamps updated_at if anything changed since the last local save
	var stamp := GameState.updated_at()
	var r := await WorldBoss.call_server(HTTPClient.METHOD_POST, "/save",
		{"data": GameState.export_text(), "summary": summary_of(GameState.data)})
	_uploading = false
	if r.ok:
		var cloud := _cloud()
		cloud.uploaded_at = stamp
		cloud.at = int(Time.get_unix_time_from_system())
		last_error = ""
		GameState.request_save()  # remember the upload ("cloud" isn't part of the content, so updated_at stays)
	else:
		last_error = "too_big" if r.status == 413 else "offline"
	status_changed.emit()
	return r.ok

## The cloud's newest save if it's newer than this device's: {"data": Dictionary, "summary": Dictionary}, else {}.
## Called at startup; offline or nothing newer means {}.
func check_cloud() -> Dictionary:
	if not WorldBoss.is_registered():
		return {}
	var r := await WorldBoss.call_server(HTTPClient.METHOD_GET, "/save")
	if not r.ok or not (r.data.get("data") is String):
		return {}
	var parsed = JSON.parse_string(str(r.data.data))
	if not (parsed is Dictionary):
		return {}
	var cloud_time := int(parsed.get("updated_at", 0))
	if cloud_time <= GameState.updated_at() + CONFLICT_MARGIN:
		return {}
	return {"data": parsed, "summary": summary_of(parsed)}

## Uses a cloud save in place of this device's (the old one stays as the local backup file)
func use_cloud_save(save: Dictionary) -> String:
	var error := GameState.import_text(JSON.stringify(save))
	if error.is_empty():
		_cloud().uploaded_at = GameState.updated_at()  # it's the cloud's copy, nothing new to send
		_cloud().at = int(Time.get_unix_time_from_system())
		GameState.save_game()
	return error

## A recovery code from another device: signs in to that account and returns its newest save.
## Returns {"ok": true, "save": Dictionary or {}} or {"ok": false, "error": "unknown_code" | "offline"}.
## The account is only switched on this device when the player then takes the save (use_recovered).
func recover(code: String) -> Dictionary:
	var r := await WorldBoss.call_server(HTTPClient.METHOD_POST, "/recover", {"code": code.strip_edges()})
	if not r.ok:
		return {"ok": false, "error": "unknown_code" if r.status == 404 else "offline"}
	var save = {}
	var sent = r.data.get("save")
	if sent is Dictionary and sent.get("data") is String:
		var parsed = JSON.parse_string(str(sent.data))
		if parsed is Dictionary:
			save = parsed
	return {"ok": true, "save": save, "account": {"player_id": str(r.data.player_id), "token": str(r.data.token),
		"name": str(r.data.name), "recovery_code": str(r.data.recovery_code)}}

## Takes a recovered account's save onto this device (or just the account, if it had no cloud save yet)
func use_recovered(result: Dictionary) -> String:
	var save: Dictionary = result.get("save", {})
	if not save.is_empty():
		var error := use_cloud_save(save)
		if not error.is_empty():
			return error
	var account: Dictionary = result.account
	var wb: Dictionary = GameState.data.world_boss
	for key in account:
		wb[key] = account[key]
	GameState.save_game()
	return ""
