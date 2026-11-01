extends Node
## Every piece of player-facing text lives here. Autoload name: Terms
##
## TERMS is the game's vocabulary. Change a word here and every line that uses it follows,
## e.g. set "team" to "Squad" and "{team}" becomes "Squad" everywhere.
## TEXT holds full UI lines. They can use any TERMS key as {key}; other {placeholders}
## (like {amount} or {name}) are filled in by the game, so keep those as they are.

const TERMS := {
	"game_title": "Respite Collection",
	"money": "Money",
	"credit_card": "Credit Card",
	"credit_cards": "Credit Cards",
	"team": "Team",
	"vanguard": "Vanguard",
	"rearguard": "Rearguard",
	"character": "Friend",
	"characters": "Friends",
	"equipment": "Gear",
	"stage": "Map",
	"stages": "Maps",
	"sortie": "Battle",
	"chapter": "Chapter",
	"home": "Home",
	"enemies": "Enemies",
	"level": "Lv.",

	"tab_home": "Home",
	"tab_team": "Team",
	"tab_gacha": "Recruit",
	"tab_collection": "Roster",
	"tab_event": "Event",
	"tab_commission": "Commissions",
	"tab_casino": "Casino",
	"dealer_name": "Bogsy",
	"roulette_host": "Nilla",

	# Classes. Tank/Warrior are vanguard classes, Mage/Shooter rearguard classes.
	"class_tank": "Tank",
	"class_warrior": "Warrior",
	"class_mage": "Mage",
	"class_shooter": "Marksman",
	"class_berserker": "Berserker",
	"class_healer": "Healer",

	"exp": "EXP",
	"ultimate": "Ultimate",
	"ascension": "Ascension",
	"friendship": "Friendship",

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
	"money_label": "{money}: {amount}",
	"credit_cards_label": "{credit_cards}: {amount}",
	"materials_label": "Materials: {list}",
	"back": "Back",
	"settings": "Settings",
	"settings_music": "Music volume",
	"settings_off": "Off",

	# Starter selection
	"starter_title": "Choose your first {character}",
	"starter_pick": "Pick me!",
	"starter_none": "No starter {characters} yet. Tick \"Is Starter\" on a {vanguard} character resource ({class_tank}, {class_warrior} or {class_berserker}).",

	# Home
	"home_welcome": "Welcome {home}.",
	"sortie_button": "{sortie}",
	"home_no_team": "Your {team} is empty. Add {characters} in the {tab_team} tab.",
	# Pieces of the battle result line
	"report_material": ", {material} ×{amount}",
	"report_drop": ", found {item}",

	# Save backups
	"storage_warning": "This browser isn't keeping saved data (private window or blocked storage). Your progress will be lost when you close the tab, so download a backup before you leave.",
	"backup_hint_short": "Progress saves automatically. Keep a backup in case browser data gets cleared.",
	"backup_hint":"Your progress saves automatically in this browser. Download a backup now and then in case the browser's data gets cleared, or to move to another device.",
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
	"reset_save": "Reset save",
	"reset_save_title": "Reset your save?",
	"reset_save_text": "This deletes ALL your progress (friends, gear, {money}, cleared maps) and starts the game over. Download a backup first if you might want it back.",
	"reset_save_ok": "Delete everything",
	"test_mode": "Test mode",
	"test_mode_title": "Test mode",
	"test_mode_hint": "For testing only. Adding a friend you already own raises their Ascension, like pulling a copy.",
	"test_add": "Add",
	"test_owned": "Owned · Asc {rank}",
	"test_money": "+10,000 {money}",
	"test_cards": "+10 {credit_cards}",

	# Map selection
	"map_title": "Choose a {stage}",
	"map_go": "{sortie}",
	"map_need_team": "You need at least one {team} member before you can {sortie}.",
	"map_section_test": "Test {stages}",
	"map_chapter": "{chapter} {number}",
	"map_chapter_named": "{chapter} {number}: {name}",
	"map_heading": "{code}  {name}",
	"map_boss_tag": "BOSS",
	"map_recommended": "Recommended: {level}{lv}",
	"map_cleared": "Cleared",
	"map_locked": "Locked: clear {previous} first.",
	"map_chapter_locked": "Locked: defeat the {chapter} {previous} boss ({code}) to open this {chapter}.",
	"map_coming_soon": "{code}  Coming soon",

	# Commissions (part-time jobs)
	"commission_intro": "Send a {character} on a part-time job. They can still {sortie} while on shift. Finished shifts pay out the next time you come back.",
	"commission_duration": "Shift: {duration}",
	"commission_requirement": "Needs: {requirement}",
	"commission_req_any": "anyone",
	"commission_req_class": "a {class}",
	"commission_req_stat": "{stat} {value}+",
	"commission_pay": "Pay: {amount} {money}{materials}",
	"commission_material": ", {material} {min}-{max}",
	"commission_card_chance": "Rare: {chance}% chance of a {credit_card}",
	"commission_open": "Open",
	"commission_working": "{name} is on shift: {time} left",
	"commission_send": "Send a {character}",
	"commission_recall": "Call back",
	"commission_recall_confirm": "Call {name} back early? They won't be paid for this shift.",
	"commission_picker_title": "Who takes the {job} shift?",
	"commission_picker_ok": "Send",
	"commission_busy": "on another job",
	"commission_unfit": "doesn't meet the requirement",
	"commission_report_title": "Shifts finished",
	"commission_report": "{worker} finished {job}: {amount} {money}{extras}",
	"commission_report_cards": ", +{amount} {card_word}",
	"commission_report_exp": ", +{amount} {exp}",
	"commission_report_level": ", reached {level}{lv}",
	"commission_report_friendship": ", +{amount} {friendship}",
	"card_on_shift": "Working: {job}",
	# VRChat-style status tags (CommissionData.status_tag)
	"status_open": "[Available]",
	"status_in_world": "[In World]",
	"status_mirror_mode": "[Mirror Mode]",
	"status_busy": "[Busy / Do Not Disturb]",
	"commission_time_left": "{time} left",
	"details_friendship": "{friendship}: {amount}",

	# Casino. Banter keys ending in _1.._3 are picked at random.
	"casino_intro": "Pick your poison. Every game takes your bet up front and pays out when the round ends.",
	"casino_play": "Play",
	"casino_back": "Back to Casino",
	"casino_bet": "Bet: {amount} {money}",
	"casino_not_enough": "Not enough {money} for that bet.",

	# Blackjack against Bogsy
	"bj_title": "Blackjack with {dealer_name}",
	"bj_blurb": "Classic Blackjack. Beat {dealer_name}'s hand without going over 21. Steady odds, small swings.",
	"bj_rules": "Get closer to 21 than {dealer_name} without going over. A win pays 1:1, a Blackjack pays 3:2, a tie returns your bet. {dealer_name} stands on 17.",
	"bj_deal": "Deal",
	"bj_hit": "Hit",
	"bj_stand": "Stand",
	"bj_double": "Double Down",
	"bj_again": "Next Hand",
	"bj_total": "{who}: {value}",
	"bj_you": "You",
	"bj_result_player_blackjack": "Blackjack! +{amount} {money}",
	"bj_result_win": "You win! +{amount} {money}",
	"bj_result_dealer_bust": "{dealer_name} busts! +{amount} {money}",
	"bj_result_push": "Push. Your {amount} {money} is returned.",
	"bj_result_lose": "You lose {amount} {money}.",
	"bj_result_player_bust": "Bust! You lose {amount} {money}.",
	"bj_result_dealer_blackjack": "{dealer_name} has Blackjack. You lose {amount} {money}.",
	"bogsy_idle_1": "Feeling lucky? Put your money where your mouth is.",
	"bogsy_idle_2": "House always wins. But hey, prove me wrong.",
	"bogsy_idle_3": "Pull up a chair. I don't bite. Much.",
	"bogsy_deal_1": "Cards are out. Your move.",
	"bogsy_deal_2": "Let's see what you've got.",
	"bogsy_deal_3": "Hit or sit, friend.",
	"bogsy_player_won_1": "Tch. Beginner's luck.",
	"bogsy_player_won_2": "Fine, take it. I'll win it back.",
	"bogsy_player_won_3": "Enjoy it while it lasts.",
	"bogsy_player_lost_1": "Thanks for the donation!",
	"bogsy_player_lost_2": "Better luck next time. Or not.",
	"bogsy_player_lost_3": "Don't cry, it's just Money.",
	"bogsy_push_1": "A tie? Boring. Again.",
	"bogsy_push_2": "Nobody wins. My favourite kind of loss.",
	"bogsy_push_3": "Run it back.",
	"bogsy_blackjack_1": "Blackjack?! Are you counting cards?",
	"bogsy_blackjack_2": "...I'm checking your sleeves after this.",
	"bogsy_blackjack_3": "Okay, that one was clean. Respect.",

	# Russian Roulette against Nilla ({min}, {max}, {best}, {chambers}, {bullets}, {chance}, {payout} come from RouletteGame)
	"rr_title": "Russian Roulette with {roulette_host}",
	"rr_blurb": "Load {min}-{max} bullets into {chambers} chambers and take turns with {roulette_host}, you first. More bullets, bigger payout: up to {best}x your bet.",
	"rr_rules": "Take turns pulling the trigger with {roulette_host}, you first. More bullets: worse odds, bigger payout.",
	"rr_bullets": "Bullets:",
	"rr_odds": "Win {chance}%  ·  Pays {payout}x",
	"rr_load": "Load the Gun",
	"rr_again": "Load Again",
	"rr_trigger": "Pull the Trigger",
	"rr_your_turn": "Your turn",
	"rr_host_turn": "{roulette_host}'s turn...",
	"rr_click_you": "*click* You survive.",
	"rr_click_host": "*click* {roulette_host} survives.",
	"rr_bang": "BANG!",
	"rr_result_win": "{roulette_host} got shot! +{amount} {money}",
	"rr_result_lose": "You got shot. You lose {amount} {money}.",
	"nilla_idle_1": "Six chambers. You pick the bullets. Wanna feel alive?",
	"nilla_idle_2": "Don't worry, you'll respawn. Your Money won't.",
	"nilla_idle_3": "Bogsy's table is for cowards. Sit down.",
	"nilla_load_1": "Spinning... you go first. Obviously.",
	"nilla_load_2": "Your turn first. Don't flinch.",
	"nilla_load_3": "Loaded. Try not to blink.",
	"nilla_her_turn_1": "My turn. Watch and learn.",
	"nilla_her_turn_2": "Heh. I never miss... wait, that's bad.",
	"nilla_her_turn_3": "Okay okay okay okay...",
	"nilla_player_won_1": "Ugh. Respawning. Take your Money.",
	"nilla_player_won_2": "That's it, I'm rejoining the instance.",
	"nilla_player_won_3": "...rematch. Right now.",
	"nilla_player_lost_1": "Oops. See you at spawn!",
	"nilla_player_lost_2": "Thanks for the Money, ghost.",
	"nilla_player_lost_3": "Told you to sit at Bogsy's table.",

	# Event
	"tab_locked": "{name} (Locked)",
	"event_locked": "Events are coming soon.",

	# Battle
	"battle_title": "{sortie}: {name}",
	"battle_allies": "Your {team}",
	"battle_enemies": "{enemies}",
	"battle_again": "{sortie} Again",
	"battle_home": "Return {home}",
	"battle_victory": "Victory! {rewards}",
	"battle_defeat": "Defeat. No rewards this time.",
	"battle_rewards": "+{amount} {money}{materials}{drops}",
	"battle_exp": "Every {team} member gained {amount} {exp}.",
	"battle_level_up": "{name} reached {level}{lv}!",
	"battle_first_clear": "First clear! +{amount} {credit_cards}.",
	"battle_card_drop": "Lucky! Found {amount} {card_word}.",
	"battle_speed": "{speed}x",
	"battle_miss": "MISS",
	"battle_wave": "{sortie} {current}/{total}",
	"battle_wave_banner": "{sortie} {current}/{total}",
	"battle_wave_boss": "{sortie} {current}/{total}: BOSS!",
	"battle_crit": "CRIT! -{damage}",
	"battle_off_balance": "OFF-BALANCE!",
	"battle_sleep": "Zzz...",
	"battle_assist_banner": "ASSIST! {name}",
	"battle_counter_banner": "COUNTER! {name}",
	"battle_guard_charge": "+{ultimate}",
	"battle_energy": "{ultimate}",

	# Team
	"team_title": "{team} 1",
	"team_hint": "{class_tank}s, {class_warrior}s and {class_berserker}s fight in the {vanguard} and take the hits. {class_mage}s, {class_shooter}s and {class_healer}s fight from the {rearguard}, which enemies only attack once the whole {vanguard} is down (unless a skill says it targets the back row). The battle is lost when every {team} member is down. {class_mage}s hit 2-3 enemies at once; {class_shooter}s hit one enemy very hard; {class_healer}s hit weakly but keep the {team} alive with their skills.",
	"slot_empty": "Empty\n\n+ Assign\n({classes})",
	"slot_change": "Change",
	"slot_remove": "Remove",
	"details_button": "Details",
	"picker_title": "Choose a {character} for the {row}",
	"picker_ok": "Assign",
	"in_team": "{row}",

	# Recruit
	"gacha_balance": "{money}: {amount}    {credit_cards}: {cards}",
	"gacha_pick_up": "PICK UP",
	"gacha_more_inside": "More {characters}\ninside!",
	"gacha_rates": "Rates: {rates}",
	"gacha_pity": "Guaranteed SSR in {count} pulls",
	"gacha_pull": "Recruit ×{count}",
	"gacha_cost": "{cost} {money} + {cards} {card_word}",
	"gacha_no_money": "Not enough {money}. You need {amount}.",
	"gacha_no_cards": "Not enough {credit_cards}. You need {amount}. Win on a {stage} you haven't cleared yet for {bonus}, or get lucky with a rare drop.",
	"gacha_reveal_all": "Reveal all",
	"gacha_empty_pool": "This pool has no {characters} to pull.",
	"gacha_result": "Recruited {count} from {name}!",
	"gacha_no_characters": "(no {characters} in this pool)",
	"new_badge": "NEW!",
	"gacha_ascend": "{ascension} up! Rank {rank}/{max}",
	"gacha_overflow": "Max {ascension}: +{amount} {money}",

	# Character details & gear
	"details_title": "{name}",
	"details_class": "{class} · {row}",
	"details_level": "{level}{lv}   {exp} {current} / {next}",
	"details_level_max": "{level}{lv} (max)",
	"details_ascension": "{ascension} Rank {rank}/{max}: +{bonus}% {stats}",
	"details_ultimate_gauge": "{ultimate} gauge: {amount}",
	"asc_short": "Asc. {rank}/{max}",
	"level_up_button": "+{count} {level} ({cost} {money})",
	"level_up_max": "Max level reached",
	"skill_line": "{kind}: {name} — {description}",
	"skill_missing": "{kind}: (not set)",
	"equip_none": "(none)",
	"equip_worn_by": "{item} [on {owner}]",
	"stat_line": "{stat}: {value}",
	"stat_line_mod": "{stat}: {value} ({mod})",

	# Battle log
	"log_hit": "{attacker} hits {target} for {damage}.",
	"log_miss": "{attacker} attacks {target} but misses.",
	"log_crit": "{attacker} lands a critical hit on {target} for {damage}!",
	"log_off_balance": "{target} is off-balance!",
	"log_assist": "{attacker} jumps in with an assist on {target} for {damage}!",
	"log_guard_charge": "{name} holds the line, charging the {rearguard}'s {ultimate} gauges!",
	"log_aoe": "{attacker} unleashes an area attack!",
	"log_ultimate": "{attacker} unleashes {skill}!",
	"log_heal": "{target} recovers {amount} {stat_hp}.",
	"log_buff_end": "{target}'s {buff} wore off.",
	"buff_hangover": "Hangover",
	"log_down": "{target} is down!",
	"log_wave": "--- {sortie} {current}/{total} ---",
	"log_passive": "{name}'s {skill} kicks in!",
	"log_lucky_break": "{name} feels lucky ({skill}): the next attack will hit every enemy!",
	"log_all_enemies": "{attacker} swings wildly at every enemy!",
	"log_undying": "{name} refuses to fall ({skill})! Hanging on at 1 {stat_hp} for {turns} turns...",
	"log_undying_end": "{name} finally collapses.",
	"log_cleave": "{attacker}'s swing carries through the whole row ({skill})!",
	"buff_asleep": "Asleep",
	"log_cancer": "{name} loses {amount} {stat_hp} to {skill}.",
	"buff_blinded": "Blinded",
	"log_blinded": "{target} is blinded by {skill}! (-50% {stat_accuracy})",
	"battle_blinded": "BLIND",
	"buff_its_raw": "Shaken",
	"log_its_raw": "{name} screams \"{skill}\" at {target}! {target} is Shaken (-25% {stat_attack} and {stat_defense}).",
	"battle_its_raw": "IT'S RAW!",
	"buff_berserk": "Berserk",
	"log_berserk": "{name} panics ({skill}) and goes Berserk! (+40% {stat_attack}, -20% {stat_defense})",
	"battle_berserk": "BERSERK!",
	"log_idle": "{name} watches from above.",
	"buff_drunk": "Drunk x{stacks}",
	"battle_drunk": "HIC!",
	"log_drunk": "{name} gets drunker! (Drunk x{stacks})",
	"log_swig": "{name} takes a long swig from his bottle.",
	"log_rally": "{name} orders a double ({skill})!",
	"battle_idle": "Supervising...",
	"log_counter": "{attacker} retaliates for {skill}, hitting {target} for {damage}!",
	"log_explode": "{name}'s mandate expires: a shockwave sweeps the enemy lines!",
	"log_winnie": "{name}'s hamster scurries over to {target} ({skill})!",
	"battle_winnie": "Winnie!",
	"log_heal_turn": "{name} and Winnie patch up the team ({skill}).",
	"battle_heal_turn": "Patching up!",
	"log_put_to_sleep": "{attacker} lulls {target} to sleep! (takes more damage while asleep)",
	"log_nod_off": "{name} can't keep his eyes open ({skill})...",
	"log_wake_plain": "{name} wakes up.",
	"battle_slept": "Sleepy...",
	"log_kick_vote": "{name} starts a vote kick against {target} ({skill})!",
	"log_kicked": "{target} got kicked from the instance and is stuck rejoining!",
	"buff_kicked": "Rejoining",
	"log_rejoined": "{name} finally loads back into the instance.",
	"log_close_instance": "{name} closes the instance on everyone!",
	"log_buffs_stripped": "{target}'s buffs are wiped!",
	"log_brain_rot": "{name} turns into a brain rot avatar and starts yelling \"67\" and \"tung tung tung sahur\"! Every enemy starts to decay.",
	"log_brain_rot_cringe": "{name}'s own front row cringes too (-10% damage and {stat_defense}).",
	"buff_brain_rot": "Decaying",
	"buff_cringe": "Cringing",
	"battle_decay": "DECAY",
	"battle_cringe": "cringe...",
	"log_grubbed": "{name} grubs {amount} {stat_attack} off {target} for his next turn!",
	"buff_grubbed": "Grubbed",
	"battle_grubbed": "GRUBBED",
	"log_balloon_boy": "\"A-HAHAHA-HAHA\" {name} turns into Balloon Boy and haunts the enemy line!",
	"buff_bleed": "Bleeding",
	"log_bleed": "{name} bleeds for {amount}.",
	"battle_bleed": "BLEED!",
	"log_sus_plants":"{name} passes around some suspicious green plants ({skill}).",
	"log_fall_asleep": "{name} dozes off...",
	"log_sleeping": "{name} is asleep. Zzz...",
	"log_wake": "{name} wakes up refreshed! Full {stat_hp}, debuffs gone.",
	"log_win": "Victory!",
	"log_lose": "Defeat... the whole {team} is down.",
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

## Story chapter names. A chapter's battle background is Art/backgrounds/<name without spaces>.*
## (e.g. "Poppy Street" -> PoppyStreet.png), so add the picture with the matching name.
const CHAPTER_NAMES := {
	1: "Poppy Street",
	2: "Drinking Night",
}

## "" for chapters without a name yet
func chapter_name(chapter: int) -> String:
	return CHAPTER_NAMES.get(chapter, "")

## "Chapter 1: Poppy Street", or "Chapter 2" before the chapter has a name
func chapter_title(chapter: int) -> String:
	var chapter_title_name := chapter_name(chapter)
	if chapter_title_name.is_empty():
		return t("map_chapter", {"number": chapter})
	return t("map_chapter_named", {"number": chapter, "name": chapter_title_name})

func rarity_name(rarity: int) -> String:
	return term("rarity_" + CharacterData.Rarity.keys()[rarity])

func class_label(cls: int) -> String:
	return term("class_" + CharacterData.CLASS_KEYS[cls])

## "Credit Card" for 1, "Credit Cards" otherwise
func credit_card_word(count: int) -> String:
	return term("credit_card" if count == 1 else "credit_cards")

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
