# Player fear and confusion movement

Players now use the shared fear and confusion behaviors instead of retaining
movement control while these auras restrict their abilities. The owner resolves
navigation intents, broadcasts splines, and publishes authoritative positions.
Creatures and pets use the same confusion behavior; possessed creatures also
revoke their controller's movement input while affected.

## Implementation

`Logic.ControlMovement` derives fleeing/confused flags, selects the current
behavior, stops superseded paths, and emits typed client-control changes from
the aura transition. Confusion takes precedence while both effects are active.
Removing one overlapping effect does not briefly return control. Roots and
stuns pause movement without ending fear or confusion; fleeing prevention
suppresses fear until its preventing aura is removed.

Confusion walks within four yards of its application point. Destinations are
bounded before pathfinding, and resolved paths that leave that region are
rejected. Fear retains its separate bounded panic runs and pauses. Both use
the existing behavior-tree context and navigation resolver.

Player movement packets and movement-acknowledgement payloads cannot overwrite
server-owned movement. Acknowledgements still retire their pending counters.
Unreleased corpses reject movement; released ghosts retain ordinary movement
and unroot acknowledgement handling. Control acquisition closes loot, and
affected players cannot reopen corpse or item-container loot.

Teleport/logout cancellation clears navigation progress and queued movement
projection, preserving aura deadlines. Login restores control from the saved
auras after behavior initialization. A teleport starts subsequent confusion
movement around the new location. Fresh navigation memory uses the current
tick time, including negative monotonic timestamps.

Reference: `refs/vmangos/src/game/Objects/Unit.cpp`, particularly
`SetFeared`, `SetConfused`, `ModConfuseSpell`, and `UpdateControl`.

## Automated validation

After the final source change:

- `mix test.all`: **4,358 passed**.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.

Coverage includes overlapping controls, caster replacement, fleeing prevention,
root pauses, expiry, damage/death cleanup, bounded paths and rejected detours,
negative-clock recovery, login restoration, teleport cancellation, stale charge
timers, owner/observer packets, possession input, loot availability, and corpse
versus ghost movement acknowledgements. Possession and root-overlap coverage is
automated; the native scenarios below exercise player characters.

Logs: `/tmp/thistle-player-control-ack-{all,compile,credo}.log`.

## Native client acceptance

Used two isolated build-5875 clients on separate accounts: level-50
Debugwarlock and Debugbidder (Mage), on Programmer Isle, map 451. God mode was
off. Control effects came from ordinary duel casts; existing `.go xyz` and
`.die` commands exercised relocation and death. Tidewave probes only read
owner state and world projections.

| Scenario | Observed result |
| --- | --- |
| Fear 6213 | The Mage visibly ran and paused, with a fear aura and disabled abilities. Held forward input did not replace the forced path. The other client observed the feared player. |
| Fear expiry | Aura, fleeing flag, spline, and fear memory cleared. Forward input moved the Mage normally afterward. |
| Curse of Recklessness 7659 | Fear remained on the Mage with about 9.4 seconds left, while movement stopped and control returned. |
| Replace with Curse of Weakness 11707 | The preventing curse disappeared and fleeing resumed with about 6.1 seconds left on the original Fear. |
| Polymorph 12825 | Both clients displayed the sheep and its walking movement. Sampling measured a maximum anchor distance of **4.000 yards** across multiple paths and pauses. Held movement input did not take control. |
| Teleport during Polymorph | The old path stopped, the anchor changed to `{16345.2, 16323.1, 69.44}`, and walking resumed there. Remaining duration decreased from about 36.9 to 31.5 seconds rather than restarting. |
| Fire Blast interruption | Fire Blast 10197 reduced the Warlock from 2,059 to 1,677 health and removed Polymorph, confusion memory, and the path. Ordinary forward input then moved the Warlock about 7.25 yards. |
| Death while feared | The Mage died with Fear still active. Health became zero; fear, confusion, spline, and navigation memory cleared. After the acknowledgement fix, the corpse owner position and world projection were exactly equal at `{16356.8841, 16320.4247, 69.4444}`. |
| Spirit release and reconnect | The Mage released, logged out, re-entered as a ghost, and moved normally. Owner and world positions agreed before and after movement; no control state returned. Corpse reclaim also succeeded. |

The native runs exposed and verified fixes for three issues: random navigation
points outside the requested confusion circle, zero-initialized deadlines on
a negative monotonic clock, and root acknowledgements replacing the stopped
corpse position with a stale spline endpoint.

No gameplay owner errors or cast-validation failures appeared in the final
server log. The client still emitted existing unimplemented account-data,
raid-info, GM-ticket, meeting-stone, and `CMSG_MOVE_NOT_ACTIVE_MOVER`
notifications. Movement ownership and the tested lifecycle completed despite
those ignored notifications; this work does not implement those codecs.

## Retained evidence

- Initial Fear/expiry: `/tmp/thistle-player-control-fear-{sample3,active3,expired,manual-recovery}.txt`;
  clients `7J3Omz` and `6SRGE6` under `/home/pikdum/.cache/thistle-wow-playtest.*`.
- Bounded Polymorph, teleport, damage interruption, and fear suppression:
  `/tmp/thistle-player-control-final-{bounded-sample,before-teleport,after-teleport,damage-break,manual-movement,fear-active,suppressed,resumed}.txt`;
  server `/tmp/thistle-player-control-clock-server.log`; clients `0wvO77` and `kaBBxO`.
- Final death and acknowledgement replay:
  `/tmp/thistle-player-control-ack-live-{fear2,death2,ghost,reconnect,ghost-move}.txt`;
  server `/tmp/thistle-player-control-ack-server.log`; clients `Ch5f0z` and `1DKlaO`.
- Useful screenshots in those session directories include
  `fear-before-death-final.png`, `fear-corpse-final.png`,
  `polymorph-after-teleport.png`, `polymorph-after-teleport-observer.png`,
  `polymorph-damage-break.png`, and `reconnected-ghost-movement.png`.

All helper-owned clients, displays, and retained servers were stopped after
acceptance. No changes were pushed.
