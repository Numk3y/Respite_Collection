# Retention update: what's built and what's left for you

You said "do it all", so every recommendation from the first version of this file is now built.
Below is what's waiting on you, then where to tune each feature.

## Needs you

1. **Deploy the server** (the Arena needs it). Double-click `server\deploy.bat`. Until then the Arena tab says it
   can't reach the server, and nothing else is affected. The new routes were tested locally with `wrangler dev`:
   register, team upload, matchmaking, start/submit, the daily fight limit and resubmit protection.
2. **Friend groups for synergies.** There are only two: Bald Squad and Astolfo Brothers. Tell me (or copy
   `Data/synergies/bald_squad.tres`) which other real friend circles should be groups.
3. **Chapter 4+.** It needs your story, maps and enemies. Account levels are paced for 7 chapters.
4. **Arena art (optional).** Add `Art/backgrounds/Arena.png` for the battle background and `MM_Arena.png` /
   `MM_Workshop.png` for the Home tiles. Until then they use existing backgrounds.

## What's in the game now

| Feature | How it works | Tune it in |
|---|---|---|
| Daily check-in | 7-day calendar. A missed day breaks the streak, not the cycle | `Daily.CHECKIN_REWARDS` |
| **Streak milestones** | Day 7 / 14 / 30 pay 2 / 3 / 5 Credit Cards, then 5 again every 30 days. Paid again in a new streak | `Daily.STREAK_MILESTONES`, `STREAK_REPEAT_DAYS` |
| **Streak freeze** | Once a week, one missed day doesn't break the streak (used up automatically) | `Daily.freeze_ready()` |
| **Free daily recruit** | One free single pull a day from any regular banner, once the streak is 2+ days and today's check-in is done. "FREE" badge on Home | `Daily.FREE_PULL_STREAK` |
| Daily / weekly missions | As before, plus "Fight 2 times in the Arena" in the rotation (only for registered players at account Lv.5+) | `Daily.MISSIONS`, `WEEKLY` |
| **Achievements** | 14 lifetime goals with 3-4 tiers each, mostly paying Credit Cards. Third tab of the Daily window, with a toast when one is reached | `Scripts/achievements.gd` |
| **Weekly Pick Up banner** | A new banner with the Common Pool's lineup (shared automatically). Each Monday 4:00 one SSR and one SR become Pick Up, and get 50% of their rarity's pulls. Own pity. The Common Pool is unchanged | `Data/pools/weekly_pickup.tres` (rate_up_share) |
| **Team synergies** | 9 synergies: 2 friend groups, 6 class sets, Underdogs (3+ R). Chips on the Team tab, a "+ Synergy" hint in the picker, max +15% per stat | `Data/synergies/`, `GameState.SYNERGY_CAP` |
| **Arena** | New tab and Home tile. Fight other players' Team 1, Elo rating, 5 fights a day (00:00 UTC), top-10 board. Practice bots fill in when there are few players. Win 600 / lose 150 Money. Opens at account Lv.5. Uses the World Boss name | `Scripts/autoload/arena.gd`, `server/src/index.js` (`ARENA_*`) |
| Home | Arena and Workshop tiles added (2x3 grid) | `Main._build_home_tab` |

## Credit Card income now (a daily player)

About **13 a week** from the daily loop, plus streak milestones (about 10 in the first month), plus one-time
achievements (about 40 in total over a long time), plus a free single pull each day.
If pulls start feeling too easy, the first things to trim are the daily 100-point chest's Credit Card
(`Daily.CHESTS`) or the free pull's streak requirement.

## Balance check

`Godot --headless --path . res://Tools/balance_check.tscn -- synergies` lists every synergy and the friends whose
worst-case stack goes past the 15% cap. Right now that's the bald friends and Gobby, so the cap is doing the work.
