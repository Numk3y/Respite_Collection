@tool
class_name GachaPool
extends Resource

@export var id: StringName
@export var display_name: String
@export var banner: Texture2D  # background image for the banner; leave empty to use a theme_color gradient
@export var theme_color: Color = Color("#7c3aed")
@export var cost: int = 150
@export var pity_threshold: int = 80  # pull that guarantees an SSR; 0 = no pity
## A new player's one free pull (Gacha.beginner_pull): free, shown only until it's used, and it skips friends the
## player already owns (so it never hands back the starter)
@export var beginner: bool = false
@export_group("Rarity Weights")  # shares of each pull; R 82 / SR 14 / SSR 4 reads as percentages
@export var weight_r: int = 82
@export var weight_sr: int = 14
@export var weight_ssr: int = 4
@export_group("Rate Up")
## Share of the pulls of a rarity that go to that rarity's Pick Up friend (when the pool has one). 0 = Pick Up is
## only shown on the banner, with no better odds.
@export_range(0.0, 1.0, 0.05) var rate_up_share: float = 0.5
## Weekly Pick Up: every week (Monday 4:00 local time) one SSR and one SR from this pool become its Pick Up friends,
## going round the pool in a fixed order. Overrides the "featured" ticks.
@export var weekly_rotation: bool = false
## Use another pool's friends instead of this pool's own entries (e.g. a weekly banner that always has the same
## lineup as the Common Pool, so new friends only need adding there)
@export var entries_from: GachaPool
@export_group("")
@export var entries: Array[PoolEntry] = []  # tick "featured" on an entry to show it as a Pick Up on the banner

const WEEK_RESET_HOUR := 4  # matches Daily.RESET_HOUR

func weight_for(rarity: int) -> int:
	match rarity:
		CharacterData.Rarity.R: return weight_r
		CharacterData.Rarity.SR: return weight_sr
		CharacterData.Rarity.SSR: return weight_ssr
	return 0

func featured_characters() -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	if weekly_rotation:
		return rotation_for_week(current_week())
	for entry in entries:
		if entry.featured and entry.character and entry.character.enabled:
			out.append(entry.character)
	return out

## The week's Pick Up friends for a weekly pool: the SSR first (the banner's lead), then the SR. Each rarity goes
## round its friends sorted by id, so the order only changes when friends are added.
func rotation_for_week(week: int) -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for rarity in [CharacterData.Rarity.SSR, CharacterData.Rarity.SR]:
		var pick: Array[CharacterData] = []
		for entry in entries:
			var c := entry.character
			if c and c.enabled and entry.weight > 0 and c.rarity == rarity and not pick.has(c):
				pick.append(c)
		if pick.is_empty():
			continue
		pick.sort_custom(func(a, b): return String(a.id) < String(b.id))
		# The SR list is walked in a different order (x7) so the same pair doesn't come back together every lap
		var step := 1 if rarity == CharacterData.Rarity.SSR else 7
		out.append(pick[posmod(week * step, pick.size())])
	return out

## Weeks since 1970 starting Monday at WEEK_RESET_HOUR local time (the same weeks as the Daily autoload)
static func current_week() -> int:
	var local := int(Time.get_unix_time_from_datetime_dict(Time.get_datetime_dict_from_system(false)))
	var day := floori(float(local - WEEK_RESET_HOUR * 3600) / 86400.0)
	return floori(float(day + 3) / 7.0)

## Seconds until the next weekly change
static func seconds_to_next_week() -> int:
	var local := int(Time.get_unix_time_from_datetime_dict(Time.get_datetime_dict_from_system(false)))
	var next_monday := (current_week() + 1) * 7 - 3
	return maxi(next_monday * 86400 + WEEK_RESET_HOUR * 3600 - local, 0)
