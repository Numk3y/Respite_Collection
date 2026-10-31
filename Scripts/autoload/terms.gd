extends Node
## Every piece of player-facing text lives here. Autoload name: Terms
##
## TERMS is the game's vocabulary. Change a word here and every line that uses it follows,
## e.g. set "fleet" to "Squad" and "{fleet}" becomes "Squad" everywhere.
## TEXT holds full UI lines. They can use any TERMS key as {key}; other {placeholders}
## (like {amount} or {name}) are filled in by the game, so keep those as they are.

const TERMS := {
	"game_title": "Friend Fleet",
	"money": "Money",
	"fleet": "Fleet",
	"vanguard": "Vanguard",
	"rearguard": "Rearguard",
	"character": "Friend",
	"characters": "Friends",
	"equipment": "Gear",
	"stage": "Map",
	"stages": "Maps",
	"sortie": "Sortie",
	"home": "Home",
	"enemies": "Enemies",
	"level": "Lv.",

	"tab_home": "Home",
	"tab_fleet": "Fleet",
	"tab_gacha": "Recruit",
	"tab_collection": "Roster",

	# Classes. Tank/Warrior are vanguard classes, Mage/Shooter rearguard classes.
	"class_tank": "Tank",
	"class_warrior": "Warrior",
	"class_mage": "Mage",
	"class_shooter": "Marksman",

	"passive_skill": "Passive",
	"active_skill": "Active",

	"stat_hp": "HP",
	"stat_attack": "Attack",
	"stat_defense": "Defense",
	"stat_evasion": "Evasion",
	"stat_accuracy": "Accuracy",
	"stat_speed": "Speed",
	# Short forms used on character cards
	"short_hp": "HP",
	"short_attack": "ATK",
	"short_defense": "DEF",
	"short_evasion": "EVA",
	"short_accuracy": "ACC",
	"short_speed": "SPD",

	"slot_weapon": "Weapon",
	"slot_armor": "Armor",
	"slot_accessory": "Accessory",

	"rarity_N": "N",
	"rarity_R": "R",
	"rarity_SR": "SR",
	"rarity_SSR": "SSR",

	"mat_snack": "Snacks",
	"mat_coffee": "Coffee",
	"mat_gossip": "Gossip",
}

const TEXT := {
	"tray_tooltip": "{game_title} (click to open)",
	"money_label": "{money}: {amount}",
	"materials_label": "Materials: {list}",
	"back": "Back",

	# Starter selection
	"starter_title": "Choose your first {character}",
	"starter_pick": "Pick me!",
	"starter_none": "No starter {characters} yet. Tick \"Is Starter\" on a {class_tank} or {class_warrior} character resource.",

	# Home
	"home_welcome": "Welcome {home}.",
	"sortie_button": "{sortie}!",
	"idle_not_deployed": "Your {fleet} is resting. Press {sortie} to pick a {stage}; afterwards they keep patrolling it automatically.",
	"idle_no_vanguard": "Your {fleet} needs at least one {vanguard} member ({class_tank} or {class_warrior}). Set it up in the {tab_fleet} tab.",
	"idle_status": "Your {fleet} keeps patrolling {stage_name}: one battle every {seconds} seconds. Estimated win rate: {rate}%.",
	"report_none": "No patrol results yet.",
	"report_latest": "Latest patrol: {summary}",
	"report_summary": "{battles} battles in {stage_name}, {wins} won, +{amount} {money}",
	"report_material": ", {material} ×{amount}",
	"report_drop": ", found {item}",
	"welcome_title": "Welcome back",
	"welcome_body": "While you were away: {summary}.",
	"minimize_on_close": "Keep idling in the background when the window is closed (click the tray icon to reopen)",
	"quit": "Save & Quit",

	# Save backups
	"storage_warning": "This browser isn't keeping saved data (private window or blocked storage). Your progress will be lost when you close the tab, so download a backup before you leave.",
	"backup_hint": "Your progress saves automatically in this browser. Download a backup now and then in case the browser's data gets cleared, or to move to another device.",
	"backup_download": "Download backup",
	"backup_copy": "Copy backup to clipboard",
	"backup_copied": "Backup copied to the clipboard.",
	"backup_restore": "Restore backup",
	"backup_restore_title": "Restore a backup",
	"backup_restore_hint": "Choose your backup file, or paste its contents below. This replaces your current progress.",
	"backup_choose_file": "Choose file…",
	"backup_restore_ok": "Restore",
	"backup_invalid": "That doesn't look like a {game_title} backup.",
	"backup_restored": "Backup restored!",

	# Map selection
	"map_title": "Choose a {stage}",
	"map_enemy_row": "{row}: {list}",
	"map_enemy_entry": "{name} ({class})",
	"map_rewards": "Rewards per win: {amount} {money}{materials}",
	"map_material": ", {material} {min}–{max}",
	"map_drops": "{equipment} drop chance: {chance}%",
	"map_win_rate": "Estimated win rate: {rate}%",
	"map_go": "{sortie}!",
	"map_need_vanguard": "You need at least one {vanguard} member before you can {sortie}.",

	# Battle
	"battle_title": "{sortie}: {name}",
	"battle_allies": "Your {fleet}",
	"battle_enemies": "{enemies}",
	"battle_skip": "Skip",
	"battle_again": "{sortie} Again",
	"battle_home": "Return {home}",
	"battle_rear_tag": "{rearguard} (can't be hit)",
	"battle_victory": "Victory! {rewards}",
	"battle_defeat": "Defeat. No rewards this time.",
	"battle_rewards": "+{amount} {money}{materials}{drops}",

	# Fleet
	"fleet_title": "{fleet} 1",
	"fleet_hint": "{class_tank}s and {class_warrior}s fight in the {vanguard}; only they can be hit, and if all of them fall the battle is lost. {class_mage}s and {class_shooter}s fight from the {rearguard}, where they can't be hit. {class_mage}s hit 2-3 enemies at once; {class_shooter}s hit one enemy very hard.",
	"slot_empty": "Empty\n\n+ Assign\n({classes})",
	"slot_change": "Change",
	"slot_remove": "Remove",
	"details_button": "Details",
	"picker_title": "Choose a {character} for the {row}",
	"picker_ok": "Assign",
	"in_fleet": "{row}",

	# Recruit
	"gacha_pool_info": "{name} ({cost} {money} per pull)  {rates}",
	"gacha_pity": "Pity {count}/{max}",
	"gacha_pull": "Pull ×{count}",
	"gacha_no_money": "Not enough {money}. You need {amount}.",
	"gacha_empty_pool": "This pool has no {characters} to pull.",
	"gacha_result": "Pulled {count} from {name}!",
	"gacha_no_characters": "(no {characters} in this pool)",
	"new_badge": "NEW!",

	# Character details & gear
	"details_title": "{name}",
	"details_class": "{class} · {row}",
	"skill_line": "{kind}: {name} — {description}",
	"skill_missing": "{kind}: (not set)",
	"equip_none": "(none)",
	"equip_worn_by": "{item} [on {owner}]",
	"stat_line": "{stat}: {value}",
	"stat_line_mod": "{stat}: {value} ({mod})",

	# Battle log
	"log_hit": "{attacker} hits {target} for {damage}.",
	"log_miss": "{attacker} attacks {target} but misses.",
	"log_aoe": "{attacker} unleashes an area attack!",
	"log_down": "{target} is down!",
	"log_win": "Victory!",
	"log_lose": "Defeat... every {vanguard} member is down.",
	"log_timeout": "The battle dragged on too long. Retreat!",
}

## A full UI line. args fill the game-supplied placeholders; TERMS fill the rest.
func t(key: String, args: Dictionary = {}) -> String:
	var line: String = TEXT.get(key, key)
	if not args.is_empty():
		line = line.format(args)
	return line.format(TERMS)

## A single vocabulary word.
func term(key: String) -> String:
	return TERMS.get(key, key)

func stat_name(stat: String) -> String:
	return term("stat_" + stat)

func stat_short(stat: String) -> String:
	return term("short_" + stat)

func slot_name(slot_key: String) -> String:
	return term("slot_" + slot_key)

func rarity_name(rarity: int) -> String:
	return term("rarity_" + CharacterData.Rarity.keys()[rarity])

func class_label(cls: int) -> String:
	return term("class_" + CharacterData.CLASS_KEYS[cls])

func material_name(key: String) -> String:
	return term("mat_" + key)

func row_name(slot: int) -> String:
	return term("vanguard" if slot < GameState.VANGUARD_SLOTS else "rearguard")

## The row a class fights in, e.g. "Vanguard" for a Tank
func class_row(cls: int) -> String:
	return term("vanguard" if CharacterData.is_vanguard_class(cls) else "rearguard")

## "Tank / Warrior" or "Mage / Marksman"
func row_classes(vanguard: bool) -> String:
	var names: PackedStringArray = []
	for cls in CharacterData.CharClass.values():
		if CharacterData.is_vanguard_class(cls) == vanguard:
			names.append(class_label(cls))
	return " / ".join(names)
