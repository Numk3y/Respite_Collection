# After Hours: endless roguelite mode (plan)

Status: **Phase 1 built (2026-11-18); phases 2–4 planned.** Picked ideas: Stranger at the bar, Casino node,
Animatronic ambush, Rival ghosts, Night twists, Run recap card.

### What phase 1 built (and where it differs from the plan below)

- Code: `Scripts/autoload/endless.gd` (`Endless`), `Scripts/ui/endless_screen.gd`, `Scripts/resources/drink_data.gd`,
  `Scripts/resources/endless_event.gd`; data in `Data/drinks/` (21 Drinks + 13 Hangovers), `Data/endless_events/`
  (9 Events), `Data/equipment/ah_*.tres` (6 shop-only gear, `shop_only = true`, hidden from the Workshop).
- Engine: unit-level rules merged on top of side rules (`FormationBattleEngine.merge_rules`), plus `lifesteal`,
  `thorns`, `crit_chance`, `start_energy`, `start_taunt`, `start_wounded`, `last_stand`, `heal_power`,
  `damage_taken`; allies can start with `hp_share` / `energy`.
- Opens after clearing **1-5**. Home tile next to the Weekly Challenge.
- Tuning after bot runs (`Tools/endless_sim.tscn -- <runs> <level>`; back up the desktop save around it):
  start with **50 Tips**; fights pay 20 / 40 / 70 (+15% per Night); everyone standing heals **10% after a won
  fight**; enemy count **scales with the number of friends still standing** (so a small squad meets small groups);
  Battles get a second wave from floor 7; enemy levels Night 1: 2→6, Night 2: 8→12, Night 3: 11→15, Afterparty
  15+2/Night. Bot medians: Lv.15 → floor 10, Lv.25 → floor 19, Lv.35 → floor 24.
- Night 1's 4th floor is a guaranteed Bar row (early hiring).
- A lost Boss fight with friends still on the bench can be retried; other lost fights just move on.
- Harsh Hangover "can't field a friend next Night" was replaced by **Speed Freaks** (enemies +15% Speed).
- Milestones paid once: Night 1 boss 3 Credit Cards, Night 2 boss 5, Night 3 boss 8 + 1 SR Ticket, later Nights 3.
- Shop: Recruit Ticket 150 (10/month), SR Ticket 600 (2/month), 3 gear pieces a week (SR 500 / SSR 1,200),
  coffee x3 for 60 and gossip x1 for 45 as Token sinks.

## The pitch

The night that never ends. A squad of friends climbs from bar to bar on a branching map, damage carries over
between fights, and Drinks (power-ups) stack up along the way. The run ends when the whole squad is down. You start
the next one with a bit more to show for it.

## Core loop

1. **Start small**: pick just **2 owned friends, 1 vanguard + 1 rearguard**. No cost limit, no rarity limit.
2. **Grow the squad during the run**: **hire friends you own at the Bar**, or meet **the Stranger** for one you
   don't own. There's **no squad size limit**: everyone you pick up stays for the run (see *Squad and bench*).
3. **Pick a route** on the Night's map, one node at a time.
4. **Fight / choose / shop** at each node. HP, KOs and Ultimate gauges **carry over** between nodes.
5. **Strong Drinks come with a hangover**: take a powerful one and you're forced to pick a debuff too
   (see *Hangovers*).
6. **Boss** at the end of each Night, then the next Night starts on a fresh map.
7. **Run over** when every friend is down → Run recap card → rewards.

## Squad and bench

- The engine fields at most **3 vanguard + 3 rearguard** per battle (`FormationBattleEngine.ROW_SIZE`), so
  "no squad limit" means an unlimited **bench**: friends past six wait on the bench with their own HP and gauge.
- Before each battle node, a **lineup screen** lets you swap bench friends in and out (row rules still apply). The
  last lineup is kept, so it's one tap when nothing changes.
- A battle is lost when the fielded friends are all down. If anyone healthy is still on the bench, the run goes on:
  the KO'd friends stay down and you field the bench next time. **The run ends only when nobody is left standing.**
  So a big squad is a real advantage, and it's what you spend Tips on.
- Bench friends heal 10% of max HP per node they sit out (resting at the back of the bar).

### Getting friends

| Source | Who | Price |
|---|---|---|
| 🛒 **Bar: Hire** | 2 random **owned** friends not in the squad yet, at your account's levels and gear | Tips, by rarity: R 40 · SR 80 · SSR 150 *(to tune)* |
| 🍸 **Stranger** | 1 random **unowned** friend from the main gacha pool (rarity weighted like a pull) | Free, or a small favour (an Event-style choice) |
| ❓ **Events** | some events offer a friend as a reward | |

Early on, Tips decide whether you hire a friend or buy a Drink. That's the main decision the shop asks for.

## The map

Each **Night** is one branching map of 15 floors, shown whole from the start so players can plan a route. Same visual
language as the story map (`MapSelect.Route`: glowing paths, nodes, the current one bouncing).

```
            👑  BOSS                      floor 15
          /  |  \
        🛏   🛒   🛏                      floor 14: always Rest / Bar
        |  /   \  |
        💀  ⚔    ❓
        | \  |  / |
        ⚔  ❓  💀  ⚔
        |   \ |   |
        🎰  ⚔  🍸  ⚔
         \  |  /  |
          ⚔  ⚔   ❓                      floors 1-2: Battles only
           \ | /
           START
```

### Generation rules

- 7 columns × 15 floors; 6 paths walked from floor 1 to 14, each step moving to the same column or a neighbour.
  Paths can merge but **never cross** (a path can't jump over another's edge).
- Node types are rolled per node with weights, then these rules are enforced:
  - Floors 1–2: Battle only. Floor 14: Rest or Bar only. Floor 15: Boss.
  - No Elite before floor 5; no two Elites, Rests or Bars in a row on one path.
  - At least one Elite and one Rest reachable on every Night.
- Seeded per run (`run_seed + night`), so reloading the game can't reroll the map or an offer.

### Starting weights (to tune)

| Node | Weight | Notes |
|---|---|---|
| ⚔ Battle | 45% | |
| ❓ Event | 22% | 10% of these are an **Animatronic ambush** |
| 💀 Elite | 12% | 25% of Elites are a **Rival ghost** when online |
| 🛏 Rest | 10% | |
| 🛒 Bar | 5% | |
| 🎰 Casino | 3% | |
| 🍸 Stranger | 3% | |

## Nodes

| Node | What happens |
|---|---|
| ⚔ **Battle** | 2-3 waves from this Night's enemy pool. Win: pick 1 of 3 Drinks, plus Tips. |
| 💀 **Elite** | One strong wave (a boss-flagged lineup, +1 enemy level band). Win: 1 of 3 Drinks, Rare or better, plus extra Tips. |
| ❓ **Event** | A short story card with 2-3 choices (risk vs reward). Can turn into a fight. |
| 🛏 **Rest** | Choose one: heal the squad 30% of max HP, **or** revive one KO'd friend at 50%, **or** train one friend (+10% stats this run). |
| 🛒 **Bar** | Shop: **hire 2 owned friends**, 3 Drinks, a heal, a revive, cure a Hangover. Paid in **Tips**. |
| 🎰 **Casino** | Gamble Tips (see below). |
| 🍸 **Stranger** | A friend you don't own offers to join (see below). |
| 👑 **Boss** | The Night's boss wave. Win: 2 Drinks, full heal of 25%, next Night. |

## Endless structure and scaling

| Night | Enemy pool | Notes |
|---|---|---|
| 1 | Chapters 1–2 enemies, boss from 1-5 / 2-5 | |
| 2 | Chapters 3–4 | |
| 3 | Chapters 5–6 | Beating Night 3 is the "you made it" moment |
| 4+ (**Afterparty**) | All chapters mixed | Each Afterparty Night adds a **Night twist** |

- Enemy level grows per floor: `level = base_for_night + floor * step` (curve tuned with the balance tool, below).
- Enemy pools come from the story stages: every enemy used on a chapter's maps belongs to that chapter's pool.
  Waves are built at runtime as `WaveData` (front 1-3, back 0-3), so new story enemies join automatically.

## Drinks (the power-ups)

A `DrinkData` resource per Drink in `Data/drinks/*.tres` so new ones are added like characters:
`id, display_name, description, rarity (Common/Rare/Legendary), filter (all / class / row), rules`.

Most Drinks are bundles of the engine's **side rules** that the Weekly Challenge already uses
(`stat_mult`, `heal_mult`, `rear_damage_taken`, `wound`; see `FormationBattleEngine._add_side`), applied to the
units the filter picks. New rule keys needed for the first set: `lifesteal`, `start_energy`, `start_taunt`,
`crit_chance`, `thorns`, `last_stand` (the first KO each battle survives at 1 HP).

Starter list (about 20 for phase 1), for example:

- **Common:** Team +10% Attack · Rearguard +15% Speed · Vanguard +15% Defense · Healers heal +20%
- **Rare:** Berserkers +10% lifesteal · Tanks start each battle taunting · Ultimates start 25% charged ·
  Marksmen +10% crit chance
- **Legendary:** First KO each battle comes back at 1 HP · Every hit Wounds · Thorns: 20% of damage taken is
  dealt back

## Hangovers (forced debuffs)

Strong Drinks have a price. Taking one sometimes forces a **Hangover** pick: choose **1 of 3** debuffs. You **can't
skip** it, and it lasts the rest of the run unless you cure it at a Bar.

**When it triggers**
- **Legendary Drink**: always.
- **Rare Drink**: 35% chance.
- **Tolerance**: every 5 Drinks taken, the next Rare is a guaranteed Hangover. A squad that has stacked a lot of
  power has to pay for it.
- Some Events and the Animatronic ambush's Legendary also count.

**Offers scale with the Drink**: a Legendary rolls from the harsh list, a Rare from the mild one. The three
options always come from different categories (squad, enemies, economy), so you choose *what kind* of pain.

| Mild (Rare) | Harsh (Legendary) |
|---|---|
| Enemies +10% HP | Enemies +20% HP and +10% Attack |
| Squad −10% Speed | Squad −15% Defense |
| Rest heals 20% instead of 30% | No healing at Rest (revive/train only) |
| Tips earned −20% | Bar prices +50% |
| Bench heals nothing | Your squad is Wounded at the start of every battle |
| Hire prices +25% | One random squad friend can't be fielded next Night |

**Curing**: the Bar sells one cure per visit (Tips; harsh Hangovers cost more). Some Events also offer a cure.

*Tech:* a Hangover is a `DrinkData` with `curse = true` and negative rules, so it uses the same rule keys and
recap card list (shown in red).

## Picked features

### 1. 🍸 Stranger at the bar
A random **unowned** friend (from the main gacha pool, rarity weighted like a pull) offers to join for this run only.
Uses your current highest friend level, base gear. They join the squad, or the bench (there's no squad limit). This
is a try-before-you-pull hook, so the recap card notes "Recruit {name} in the Recruit tab".
Owned friends come from the Bar's **Hire** instead (see *Getting friends*).
*Tech:* the engine takes `CharacterData.battle_unit(stats)`, so a guest friend needs no owned uid; the run state
stores it as `{"guest": id, "level": n}`.

### 2. 🎰 Casino node
Bet Tips on the existing **Blackjack** or **Roulette** (`Scripts/minigames/`). Bet capped at 50% of current Tips.
A rare jackpot can pay a Rare Drink instead of Tips.
*Tech:* the minigames need a "currency source" option so they bet run Tips instead of Money.

### 6. 👻 Animatronic ambush
10% of ❓ Events are a trap: lights flicker, the jumpscare plays and the Freddy & co. wave
(`Data/waves/animatronics.tres`, `Combat.ANIMATRONIC_WAVE`) attacks. Winning pays a guaranteed **Legendary** Drink;
losing is a normal fight loss (KOs carry on).
*Tech:* reuse `JumpscareOverlay` and the wave as-is.

### 7. ⚔ Rival ghosts
25% of Elites (when online) are a real **Arena player's defense team**, shown with their name and rating
("Ghost of {name}"). Scaled to the Night's enemy level. Offline or on server error it falls back to a normal Elite.
*Tech:* reuse `Arena` opponent fetching and `Arena.enemy_team()`; one new server endpoint for a random team
near a power band, or reuse the opponents list. The user runs the deploy (see the World Boss server notes).

### 9. 🌙 Night twists (Afterparty Nights)
Every Night from 4 on picks a twist, shown on the map's banner. Twists **stack**: Night 5 keeps Night 4's.

| Twist | Effect |
|---|---|
| Power outage | Map is dark: nodes are hidden until you're next to them |
| Happy hour | Bar prices −50%, enemies +25% Attack |
| Karaoke night | The squad is Wounded at the start of every battle |
| Lock-in | No Rest nodes this Night; Elites drop 2 Drinks |
| Bouncer strike | Enemies +40% HP, Tips ×2 |
| Speed run | Enemies +25% Speed, every win gives +1 Drink choice |

Several of these are existing Weekly Challenge rules (`Challenge.BATTLE_RULES`), so reuse them.

### 11. 🧾 Run recap card
At run end: squad portraits (KO'd ones greyed), floor and Night reached, the Drinks taken (Legendaries highlighted),
MVP (most damage), best tank (most taken), best healer, Tips earned, cause of the final defeat, and **new best**
stamp if it is one. Sized as a clean screenshot. A "Copy summary" button puts a text version on the clipboard.

## Run currency and rewards

- **Tips**: earned in the run and spent at Bars and the Casino. At the end of the run, any Tips left over are
  converted into Night Tokens (below), so spending them and saving them are both reasonable choices.

### Night Tokens (permanent currency)

When a run ends, it pays **Night Tokens** based on **how far you got** and **how many Tips you were holding**. Night
Tokens are kept between runs and spent in the **After Hours shop**.

**Payout at run end** *(numbers to tune)*

| Source | Tokens |
|---|---|
| Each floor cleared | 2 |
| Each Elite won | 5 |
| Each Night boss won | 20 (Night 1) · 30 (Night 2) · 40 (Night 3) · 50 each Afterparty Night |
| Tips left over | 1 per 10 Tips |
| New personal best floor | +25% of the run's total |

**Cash out or push on**: after every boss, the squad can **Call it a night**. That ends the run on purpose and
converts **100%** of the Tips left. If the run ends with everyone knocked out, only **50%** of the Tips convert;
floors, Elites and bosses always pay in full. So each boss asks the player whether to cash out now or risk the
Tips for more floors.

The run-over screen and the Run recap card show the breakdown line by line, so players see why they got what they got.

### After Hours shop

A new shop (tab on the After Hours screen) paid in Night Tokens.

**Roll tickets** (monthly limits so the mode can't replace the gacha economy):

| Item | Price | Limit |
|---|---|---|
| Recruit Ticket | 150 | 10 per month |
| SR Recruit Ticket | 600 | 2 per month |

These use the tickets that already exist (`GameState.add_tickets("recruit_ticket" / "sr_ticket", n)`, the same as
Daily rewards).

**Special gear: the "After Hours" line.** Exclusive gear that only drops from this shop: a nightlife set across all
three slots (weapon / armor / accessory), SR and SSR versions.
- **Step 1 (just data):** strong stat lines in `Data/equipment/after_hours_*.tres`, a little above the best story
  drops of the same rarity, with their own icon style. `EquipmentData` today has stat modifiers only, so this
  needs no code changes.
- **Step 2 (gear perks, later):** give special gear one small passive, e.g. "Bouncer's Jacket: the wearer takes
  10% less damage from Elites and bosses" or "Neon Sign: +5% crit chance". This needs an `effect` field on
  `EquipmentData` and support in the engine, so it's a separate piece of work.
- **Stock rotates weekly:** 3 gear pieces on offer each week (seeded by week, like the Weekly Challenge), 1 of
  each per week. SSR pieces cost about 1,200 Tokens, SR about 500.

**Other ideas for the shop:** materials (coffee / gossip) as a sink for extra Tokens, and an After Hours profile
frame/title for reaching Night 3 / Night 5.

**Pacing target:** an average run (into Night 2, about 20 floors) pays ~100–150 Tokens, so a Recruit Ticket every
run or two and an SSR gear piece about every 1–2 weeks of regular play. Tune together with the Credit Card budget.

### Other rewards
- **First-time milestones** (once per account): Night 1 boss, Night 2 boss, Night 3 boss, then every Afterparty Night.
  Credit Cards + gear. *(Amounts: decide with the weekly Credit Card budget in mind.)*
- **Weekly best**: small reward for your best floor this week (Money + materials), capped.
- **Personal best** saved and shown on the Home tile.

## Run state and saving

`GameState.data.endless` holds the whole run, so closing the game mid-run resumes it:

```
{
  "seed": int, "night": int, "floor": int, "node": int,
  "map": [...],                       # generated nodes and edges for this Night
  "squad": [{"uid" | "guest", "hp", "energy", "ko", "train"}],   # everyone picked up, any size
  "lineup": {"vanguard": [squad index], "rearguard": [squad index]},  # up to 3 + 3 fielded
  "drinks": [ids], "hangovers": [ids], "drinks_since_hangover": int, "twists": [ids],
  "tips": int, "pending": {...},       # an open offer (Drink pick, event card) so reloads can't reroll it
  "stats": {...}                       # for the recap card
}
```
Plus `best_floor`, `milestones_claimed`, `week_best`, `tokens`, and the shop's purchase counts
(`shop_month`, `shop_week`, bought per item) outside the run.

## Code plan

| Piece | Where |
|---|---|
| Run state, map generation, offers, rewards | new autoload `Scripts/autoload/endless.gd` (`Endless`) |
| Drinks | new resource `Scripts/resources/drink_data.gd`, `Data/drinks/*.tres` |
| Events | new resource `Scripts/resources/endless_event.gd`, `Data/endless_events/*.tres` (text, choices, outcomes) |
| Engine support | `FormationBattleEngine`: allies can start with HP below max, KO'd (left out) and with energy; new Drink rule keys; read HP and energy back from `result()` |
| Battles | `Combat.start_endless()` / report path, same pattern as `start_challenge` |
| UI | `Scripts/ui/endless_map.gd` (Night map), `endless_squad.gd` (starting pair pick + lineup/bench screen), `drink_picker.gd` (also the forced Hangover pick), `endless_rest.gd`, `endless_shop.gd` (hire, drinks, cures), `run_recap.gd`; Home tile in `Main.gd` |
| Night Tokens + shop | `Endless` (payout, balance, purchases, weekly stock); `Scripts/ui/endless_shop_tokens.gd`; gear in `Data/equipment/after_hours_*.tres`; Token icon in `CurrencyChip` |
| Text | `Terms` keys `endless_*` |
| Tuning | `Tools/balance_check.gd -- endless`: the benchmark team (Ami, Kai, Mika, Nana) plays 100 simulated runs with random routes and Drinks. **Target: median about floor 15–20 for the benchmark team** (into Night 2), 30+ for a strong roster. |

## Build phases

1. **Playable core**: starting pair pick, Night map with Battle / Elite / Event / Rest / Boss / **Bar (hire + Drinks)**,
   Tips, squad bench and lineup screen, HP carryover, about 20 Drinks with **Hangovers**, about 8 Events, 3 Nights
   plus the Afterparty loop (no twists yet), run-over screen, best floor, milestones, and saving the run so it can
   be resumed. *(Bar and hiring move into phase 1: starting with 2 friends needs a way to grow the squad.)*
   Night Tokens payout (with Call it a night) and the After Hours shop with tickets and step-1 special gear.
   *(Also phase 1: without them a finished run gives nothing to keep.)*
2. **Night out**: 🎰 Casino, 🍸 Stranger, 👻 Animatronic ambush.
3. **Endless flavour**: 🌙 Night twists, 🧾 Run recap card, weekly best reward.
4. **Online and tuning**: ⚔ Rival ghosts (server endpoint), balance_check endless simulation, curve and
   Drink tuning, more Drinks and Events.

## Open decisions

- **Hire prices and Bar frequency:** with only 2 starting friends, Bars may need to be more common early
  (e.g. one guaranteed by floor 4 of Night 1). Tune once it's playable.
- **Token prices and ticket limits:** the numbers above are first guesses; check them against how many tickets
  the game gives out today.
- **Special gear art:** icons for the After Hours line (or reuse existing icons with a neon tint at first).
- **Credit Card budget:** how many per week this mode can pay. The Weekly Challenge pays 6.
- **Ending:** a big reward for beating Night 3 and Afterparty forever after (proposed), or a hard cap?
- **Rival ghosts:** OK to add a server endpoint (you deploy)?

## Ideas parked for later

- **Cocktail sets**: 3 Drinks of a family (Whiskey = attack, Coffee = speed, Milk = defense) mix into a set bonus.
- **Hype meter**: wins with nobody KO'd raise the odds of Rare and Legendary Drinks; a KO resets it.
- **Character events**: events that only appear with a certain friend in the squad.
- **Hangover levels**: difficulty ladder unlocked by beating Night 3.
- **Daily seeded run**: same map for everyone each day, with a leaderboard.
