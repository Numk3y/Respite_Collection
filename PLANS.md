# Plans

Features that are designed but not built yet.

## Team synergies (planned, not started)

Bonuses for putting certain friends together, so building a team is a puzzle on top of the team cost limit.

### Kinds of synergy
- **Friend groups**: named groups of friends who know each other in real life, e.g. "Bald Squad"
  (Bald Ramsay, Baldguy, BaldVegeta). Two tiers: 2 members and 3+ members, e.g. ATK +5% / +12% for the members.
  *Open question: which real friend circles should be groups?*
- **Class sets**: 2+ of a class in the team, e.g. 2 Tanks: Vanguard DEF +8%; 2 Mages: Mage damage +8%;
  Healer + Tank: heals +10% on the Tank.
- **Underdogs**: 3+ R friends in the team: everyone +6% stats. This makes the R slots worth more than
  "the cheap filler" under the cost limit, and fits "the best team at max cost is 3 SSR + 2 SR + 1 R".

### Rules
- Bonuses only count members actually in the team (any row).
- Keep the total from all synergies to about +15% of any one stat, so synergies help but don't decide fights.
- Synergies don't change team cost.

### How to build it
- Data: a `SynergyData` resource in `Data/synergies/*.tres`: name, description, members (character ids) or a
  class or rarity rule, tiers (count -> stat mods).
- `GameState.team_synergies(index)` returns the active ones with their tier; `get_battle_team()` applies the
  stat mods when it builds each unit (the same way Bond and Ascension bonuses go in).
- Team tab: a row of synergy chips under the summary: lit when active, dim with "1/2" when one friend short.
  Hover for what it does.
- Character details and the team picker: list the friend's groups, and highlight picker tiles that would
  turn a synergy on.
- `Tools/balance_check.gd`: report the strongest synergy team per cost limit to catch anything too strong.
