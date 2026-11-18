# Plans

Features that are designed but not built yet.

## Team synergies: built

Built as planned: `Data/synergies/*.tres` (SynergyData), `GameState.team_synergies()` / `synergy_bonuses()`
(capped at `GameState.SYNERGY_CAP` = 15% per stat), chips on the Team tab, "+ Synergy" hints in the team picker,
and `balance_check.tscn -- synergies` for the worst-case stacks.

**Still open:** which real friend circles should be groups? Only two exist so far: **Bald Squad** (Bald Ramsay,
Baldguy, BaldVegeta) and **Astolfo Brothers** (Spijette, Gobby), taken from the combos. To add one, copy
`Data/synergies/bald_squad.tres`, then change the id, the name, the members and the bonuses.

## After Hours (endless roguelite mode)

Planned in [PLAN_AFTER_HOURS.md](PLAN_AFTER_HOURS.md): branching Night maps, Drinks, Stranger, Casino node,
Animatronic ambush, Rival ghosts, Night twists, Run recap card. **Phase 1 built**; phases 2–4 still to do.

## Chapter 4+

Account levels are paced for 7 chapters; 3 exist. Needs story, maps, enemies and a background per chapter.
