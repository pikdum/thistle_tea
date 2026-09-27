# Consumable stacking acceptance

Recovery and lasting consumable buffs now follow vanilla exclusivity rules.
New food replaces existing food while retaining a separate drink. A combined
meal replaces both, and either separate recovery replaces the entire combined
holder. Well Fed buffs replace one another without cancelling eating or
drinking. Flasks replace other flasks while ordinary elixirs remain eligible
to coexist.

`Spell.Consumable` classifies raw DBC recovery effects, their standing
interruption flag, retained-item buffs, and the priest-family fruit buffs.
The new `SpellElixir` loader preloads build-5875 masks at boot; gameplay uses
cached data. The shared aura application path handles replacement, stat
recomputation, projection, and cleanup. No separate consumable state or
architecture allowance was added. Vanilla's ordinary elixirs do not receive
the later battle/guardian restrictions.

Reference: VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`src/game/Spells/SpellEntry.cpp` `GetSpellSpecific`, `SpellEntry.h`
`IsSingleFromSpellSpecificPerTarget`, `SpellMgr.h` `GetSpellElixirSpecific`,
and `Objects/Unit.cpp` aura replacement. At this acceptance commit, named
food bonuses such as Grilled Squid's Increased Agility lacked the Well Fed
classification and retained their existing stacking behavior. The subsequent
[explicit spell group implementation](spell-groups-playtest.md) supplies
their exclusivity rules and verifies Grilled Squid replacement natively.

## Native acceptance

An isolated build-5875 GPU client ran against commit `38adeafc`.
Debughunter (GUID 7) was raised to level 60 on Programmer Isle, map 451.
Native developer commands granted test items and set health and mana deficits.
All gameplay mutations used native client input; Tidewave probes were read-only.
Item uses called `UseContainerItem` for verified inventory slots.

- Tough Jerky (117, spell 433) and Refreshing Spring Water (159, spell 430)
  produced two active recovery holders. Dalaran Sharp (414, spell 434)
  replaced the jerky, retaining the drink's original application and expiry.
  `food-and-drink.png` shows both recovery icons and the seated player.
- Graccu's Mince Meat Fruitcake (21215, spell 25990) replaced both holders
  with one combined effect. Using jerky again removed that entire effect and
  left only food. Movement cleared recovery and restored standing posture.
  Every use consumed exactly one item; health and mana increased during
  recovery. `combined-recovery.png` shows the single combined icon.
- Spiced Wolf Meat (2680) applied food 5004, then Well Fed 19705 after
  10,010 ms. Stamina rose from 161 to 163, Spirit from 91 to 93, and maximum
  health from 2,897 to 2,917. Tender Wolf Steak (18045) replaced the eating
  effect immediately, preserving the earned bonus until its own ten-second
  threshold. Then 19710 replaced 19705: Stamina became 173, Spirit 103, and
  maximum health 3,017. The bonuses did not accumulate. Standing removed
  food 10256 while retaining only the new Well Fed holder. The sampler
  records these transitions; `well-fed-replaced.png` shows the resulting
  character sheet and buff.
- Elixir of Lesser Agility (3390, spell 3160) raised Agility from 170 to
  178. Flask of the Titans (13510, spell 17626) added 1,200 maximum health,
  bringing it to 4,217 alongside Well Fed and the elixir. Distilled Wisdom
  (13511, spell 17627) replaced Titans: maximum health returned to 3,017 and
  maximum mana rose from 2,400 to 4,400. Agility and Well Fed remained
  unchanged. Each flask and elixir consumed one item. See
  `titans-with-elixir.png` and `wisdom-replaced-titans.png`.
- Normal logout removed the player process, metadata, and projected position.
  CharacterStore retained the three earned buffs and item counts. Reconnect
  created a new owner with the same application and expiry timestamps,
  maximum health 3,017, maximum mana 4,400, and Agility 178.
  `reconnected-buffs.png` shows the restored client state.
- Native `.die` removed Well Fed and the agility elixir. Stamina, Spirit,
  Agility, and maximum health returned to 161, 91, 170, and 2,897. Distilled
  Wisdom retained its original expiry and kept maximum mana at 4,400.
  Titans did not return. `death-retained-flask.png` shows the death dialog
  with only the retained flask visible.

## Automated checks

- `mix test.all`: 6,744 passed in 75.3 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2,441 source files.
- Focused suite: 145 passed; formatting and pre-commit checks passed.

Coverage includes both replacement directions for combined recovery,
cross-caster Well Fed replacement, expiration and stat restoration, standing
interruption, preventing removed food from triggering a later buff, ordinary
elixir coexistence, and death retaining only the replacement flask. Separate
DBC and VMangos integration tests verify recovery and buff classification,
the five actual flask masks, and unrestricted ordinary elixir rows. Native
acceptance does not claim every flask or food variant, a second observer,
or waiting through the full lasting-buff durations.

Build and runtime used
`NAMIGATOR_SRC=/nix/store/3nds85i5fyjgpqcgjnk03fdfgs798vfn-namigator-with-wmo-metadata`.

## Retained evidence

Client session: `/home/pikdum/.cache/thistle-wow-playtest.MjTYpF`.
Screenshots are under its `screenshots/` directory.
Evidence files use `/tmp/thistle-consumable-stacking-` with these suffixes:

- `server.log`, `baseline.txt`, `food-drink.txt`, and `food-replaced.txt`.
- `combined.txt`, `combined-replaced.txt`, and `standing.txt`.
- `well-fed-trace.txt`, `well-fed-low.txt`, `well-fed-high.txt`, and `well-fed-standing.txt`.
- `titans.txt`, `wisdom.txt`, `logged-out.txt`, and `logout-presence.txt`.
- `reconnected.txt`, `death.txt`, and `cleanup.txt`.
- `gpu-start.txt`, `gpu-end.txt`, `test-all.log`, `compile.log`, and `credo.log`.

An initial login used the character name as the account name and failed.
Acceptance began only after logging into the seeded `debug` account and
selecting Debughunter.

WoW PID 1837495 used AMD DRM client 5538. Its graphics counter advanced
from 1,194,899,793 ns to 16,692,049,652 ns; duplicate descriptors were counted
once. This confirms rendering by the game process independently of Gamescope.
The server log had no errors or consumable validation warnings. Existing
unsupported account-data, ticket, and meeting-stone requests remained.

The helper stopped `thistle-wow-playtest.MjTYpF.service` using recorded
invocation `fbddd81b392b43f495c92227a7f0fd08`. The unit became inactive with
an empty cgroup. The player was absent from its registry, metadata, and world
projection. The retained server PTY exited, both owned game/server PIDs were
absent, and ports 4000, 3724, and 8085 were free. Artifacts were retained.
