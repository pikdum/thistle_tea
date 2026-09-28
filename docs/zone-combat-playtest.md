# Dungeon-wide creature combat pulses

Creatures can now put every eligible player in their dungeon copy into combat.
Two sources start this state. The first is static flag 2 `FORCE_RAID_COMBAT`
(0x2), which applies on aggro by a player-controlled unit. The second is script
command 49, `ZONE_COMBAT_PULSE`, including EventAI and waypoint scripts. The
first pulse attacks the nearest hostile player if the creature has no victim.
It then enrolls every living, attackable player in the same `WorldRef`, along
with their hunter or summoned pet. After that, the creature pulses every three
seconds while it remains in combat. These repeat pulses only recruit players
who are not already in combat, so late arrivals join the encounter.

`Logic.ZoneCombat` owns the pure admission and pulse rules. `Engagement.enter`
starts the state and `Engagement.leave` clears it. It therefore ends through
the same funnel as death, evade, and reset. The creature's tick plan schedules
the pulses. `Server.CombatZone` supplies a snapshot of the exact copy's players
and pets through the AI perception request. Nothing outside that copy can be
recruited. A creature that is due to evade under its hard leash stops pulsing.
Totems, creatures without threat lists, player-owned pets, and player-charmed
creatures are ineligible. `.debug combatpulse` requests a pulse from the
selected creature through the ordinary script path.

Reference: VMangos revision `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Creature::SetInCombatWithZone`, the `CSTATE_COMBAT_WITH_ZONE` pulse in
`Creature::Update`, `Map::ScriptCommand_ZoneCombatPulse`, and the
`CREATURE_STATIC_FLAG_2_FORCE_RAID_COMBAT` checks in `Unit.cpp`.

Implementation commit: `c6d23e53`.

## Native acceptance

Two isolated build-5875 GPU clients ran against a fresh server at `c6d23e53`:

- Debugwarrior, GUID 1, session `/home/pikdum/.cache/thistle-wow-playtest.707QLL`.
- Debugbuyer, GUID 10, session `/home/pikdum/.cache/thistle-wow-playtest.PI7CmS`.

Both were level 50 with god mode. Each player entered Uldaman through open-world
area trigger 286 at `{-6053.73, -2954.63, 213.69}` on map 0. The trigger
placed each player at the entrance, `{-228.86, 46.10, -46.02}`. Tidewave probes
and samplers were read-only.

The native trigger was imported EventAI. Earthen Sculptor, entry 7012, runs
aggro event 701201 containing command 49. Two sculptors took part: spawn 28372
(GUID `17379391079677166244`) and spawn 28373 (GUID `17379391079677166220`).
The entrance is about 220 yards from their hall.

| Step | Observed result |
| --- | --- |
| Warrior enters solo | Map 70, copy 1, owned by player 1. |
| Buyer enters solo | Map 70, copy 2, owned by player 10. |
| Warrior targets a sculptor and starts attacking | Both sculptors entered combat with a combat-zone state and a scheduled next pulse. Nearby creatures also engaged: a Stone Steward and two Earthen Rocksmashers. The buyer in copy 2 stayed out of combat with no threat refs. |
| Warrior invites; buyer accepts and re-enters | The group adopted copy 1. The buyer arrived at the entrance in copy 1 and entered combat with sculptor refs; the client showed the combat icon. |
| Buyer leaves the dungeon | The buyer left combat. All five engaged creatures dropped GUID 10 from their threat lists. |
| Buyer re-enters during the fight (sampled) | The world changed to copy 1, then combat began **572 ms** later with a ref to sculptor 28373. The warrior never came within 200 yards. |
| Warrior kills sculptor 28372 | Its ref was removed from the buyer. Sculptor 28373 kept the buyer in combat. |
| Warrior kills sculptor 28373 | The buyer's refs emptied in the same 100 ms sample, and `in_combat` became false 102 ms later. The buyer stayed out of combat for the remaining 282 seconds. |

The warrior stayed in ordinary combat with the Rocksmashers after both
sculptors died. That combat repeatedly evaded and re-aggroed on a roughly
24-second cycle while the god-mode warrior stood beside them. This is
pre-existing melee behavior, not pulse recruitment: those creatures have no
combat-zone state.

Once, the buyer received refs from both sculptors on entry. The sculptors
aggroed in the same tick, so their pulses are nearly in phase. Both saw the
buyer as out of combat before the buyer's owner published `in_combat`. This
adds a zero-threat entry, the same as a VMangos pulse on a player not yet in
combat, and cleared normally on death.

An earlier run on the same commit used Taragaman the Hungerer in Ragefire Chasm
(map 389), started by `.debug combatpulse`. It showed the same copy isolation:
the buyer's solo copy 2 stayed out of combat. It also showed late recruitment
2.85 seconds after the buyer entered the warrior's copy 1. That server was
left idle for five hours. The warrior's client then repeated
`CMSG_LOGOUT_REQUEST` (AFK auto-logout refused while in combat) about 970,000
times. That server was discarded and does not count toward this acceptance.

Automated coverage additionally exercises activation by player and player-pet
contact but not NPC contact, nearest-target selection, dead, friendly,
untargetable, foreign-copy, and charmed exclusions, pet enrollment, repeat-pulse
filtering, passive reactions, empty snapshots, hard-leash suppression,
incarnation-scoped references on reset, nested scripts, aborts, and General
Rajaxx's imported pulse.

## Validation

- `mix test.all`: 7,546 passed, seed 173992, in 70.5 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2,633 files.
- Logs: `/tmp/thistle-zone-combat-final-{tests,compile,credo}.log`.

## Artifacts and cleanup

- Server log: `/tmp/thistle-zone-combat-final-server.log`; it has no
  error-level entries. The only warnings are the known unimplemented
  `CMSG_UPDATE_ACCOUNT_DATA` and `CMSG_GMTICKET_GETTICKET`.
- State evidence: `/tmp/thistle-zone-combat-final-isolation.txt`,
  `/tmp/thistle-zone-combat-final-late-entry.txt`, and
  `/tmp/thistle-zone-combat-final-kill.txt`.
- Screenshots: `uld-entry.png`, `aggro.png`, and `fight7.png` (warrior);
  `uld-solo.png`, `late-entry.png`, and `buyer-released.png` (buyer).
- Both WoW processes used `amdgpu`. Their graphics-engine counters increased
  from 16.46 to 22.67 billion ns and from 18.83 to 26.09 billion ns during the
  kill checks (`/tmp/thistle-zone-combat-final-gpu.txt`).
- Earlier Ragefire evidence: `/tmp/thistle-zone-combat-{copies,isolation,late-entry,recruited}.txt`
  and sessions `thistle-wow-playtest.ZmovId` and `thistle-wow-playtest.VfnAgW`.
- All four owned client services are stopped. Both servers exited, and ports
  4000, 3724, and 8085 were closed before the final test suite.
