# Alterac Valley objective acceptance

Native build-5875 acceptance on 2026-09-24 and 2026-09-25, using fresh local
servers and isolated GPU clients. References were
`refs/vmangos/src/game/Battlegrounds/BattleGroundAV.cpp`, `BattleGroundAV.h`,
`BattleGroundMgr.cpp`, and the generated VMangos spawn catalog.

This covers the objective engine: banners, graveyards, towers, mines, captains,
generals, rewards, and match lifecycle. Armor scrap donations and troop upgrades
now have [separate acceptance coverage](alterac-armor-playtest.md). Other resource
turn-ins and player-launched assaults remain future work; this is not full
Alterac Valley or vanilla feature parity.

## Native gameplay

Level-60 Debugmage (Alliance, GUID 5) and Debugshaman (Horde, GUID 8) joined via
`.bg join alterac` and the client's **Enter Battle** button. Both occupied map
30, instance 1. `.bg start` shortened preparation only. Existing developer
commands supplied levels, quests, godmode, and Death Touch, and moved characters
within the same instance. Actual Opening casts and Death Touch casts drove
objectives; capture and resurrection timers ran normally. This verifies the
objective transitions, not the difficulty or balance of the NPC encounters.

| Check | Observed result |
| --- | --- |
| Banner assault and defense | Horde assaulted Stonehearth Graveyard; Alliance defended it. After the banner reset fix, the stationary Horde player immediately assaulted again without moving or jumping. Counts became two assaults and one defense. |
| Tower lifecycle | Alliance assaulted Iceblood Tower, Horde defended, and Alliance assaulted again. The normal five-minute timer destroyed the tower, displayed fire, announced the loss to both clients, and awarded 396 bonus honor. |
| Assault quests | Quests 7081 and 7102 completed when the player's graveyard and tower Opening casts finished, without waiting for the capture timer. |
| Graveyard control | Alliance captured Iceblood Graveyard after five minutes. Death and **Release Spirit** routed the mage to `{-531.2178, -405.2314, 49.5514}`. The resurrection wave restored `2460/2460` health, cleared the ghost flag and queue, and applied Honorless Target. |
| Mine ownership | Killing the currently active mine boss replaced its faction population and supply entries. Both factions captured Irondeep through real client casts. An earlier long-running match returned to neutral while unattended; exact twenty-minute timing is covered by deterministic tests. |
| Mine quest | Taking Irondeep completed quest 7122 in the earlier objective run. |
| Supply collection | Alliance looted entry 178789 and Horde looted entry 178788 while each owned Irondeep. Both sent `CMSG_AUTOSTORE_LOOT_ITEM`; each inventory increased from zero to one item 17522. |
| Supply respawn | After Alliance looted a chest, the live Alliance supply count fell from nine to eight, returned to nine, and the same location opened with fresh loot. |
| Ownership loss with loot open | Horde took Irondeep while the mage's loot window was open. The old chest disappeared, the client closed the loot window, and the mage retained only the previously collected item. The enemy-faction replacement was not interactable in the client. |
| Captain buffs and deaths | Both faction captain buffs applied with the AV navigation data loaded. Killing Galvangar and Balinda awarded 594 bonus honor to their opposing teams and incremented the killers' leader counters. |
| General victory | Death Touch killed Drek'Thar and ended the match for Alliance. Both native scoreboards displayed the same winner and all seven AV objective columns correctly. |
| Marks and exit | The winning mage received three marks (20560); the losing shaman received one. Both clicked **Leave Battleground** and returned to their original Programmer Isle position. Match registrations, player reservations, and remaining instance entities were all empty. |

The final seven-minute match showed these scoreboard values on both clients:

| Player | Graveyards assaulted | Mines captured | Leaders killed | Secondary objectives | Bonus honor | Marks |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Debugmage | 0 | 1 | 2 | 0 | 696 | 3 |
| Debugshaman | 1 | 1 | 1 | 0 | 680 | 1 |

Other objective counters, killing blows, honorable kills, and deaths were zero.
End-of-match objective honor uses the match duration modifier, so these totals
differ from the earlier long-running match.

The native ownership-loss check demonstrates source removal and client loot
closure. It does not demonstrate a delayed autostore packet after revocation:
the client had already closed the loot window. Automated tests independently
verify that revoked access blocks visibility, gold, item reservation, and a
previously pending transfer. Earlier attempts clicked the loot label rather
than the icon and sent no autostore request; those are not acceptance evidence.

## Bugs found and fixed

- `3b90d6c2`: typed spell failure effects now retain area, focus, and equipment
  requirements. A captain aura failing its area restriction previously reached
  the packet codec with a nil area and crashed the player owner.
- `89d161fd`: enemy graveyard and tower assault quest credit belongs to the
  player who completes the Opening cast. It no longer waits for a team capture.
- `b247f9cb`: Namigator loads map 30, and the declarative map generator includes
  `PVPZone01`. Missing AV geometry left area context unavailable. The local
  bake completed 8,960 tiles; its Recast warnings are retained in the bake log.
  Tests and native probes cover relevant areas, not every tile's quality.
- `9fdf1ab4`: slow-opening banners send `SMSG_GAMEOBJECT_RESET_STATE` after
  reappearing, allowing stationary players to interact again. AV score rows
  now encode seven fields, including mine and leader counters; the prior
  five-field rows produced invalid client columns.
- `6d1784bd`: supply access recognizes all six neutral and faction chest entries.
  The database swaps these variants on mine ownership changes. A shared entry
  mapping now drives both match policy and loot actor access checks.

## Retained evidence

The main objective, tower, quest, graveyard, and first victory run used Alliance
session `/home/pikdum/.cache/thistle-wow-playtest.vdHnmn`, Horde session
`/home/pikdum/.cache/thistle-wow-playtest.i3yuEt`, and server log
`/tmp/thistle-av-fixed-server.log`. Runtime probes include
`/tmp/thistle-av-fixed-tower-timer.log`, `/tmp/thistle-av-fixed-tower-destroyed.log`,
`/tmp/thistle-av-fixed-ghost.log`, `/tmp/thistle-av-ghost-queue.log`,
`/tmp/thistle-av-fixed-victory.log`, and `/tmp/thistle-av-fixed-exit.log`.
Screenshots include `resurrected-at-new-graveyard`, `alliance-victory`, and
`horde-defeat`; these older victory images precede the score encoding fix.

The stationary banner regression used Alliance session
`/home/pikdum/.cache/thistle-wow-playtest.uudwBr` and Horde session
`/home/pikdum/.cache/thistle-wow-playtest.UTg4OX`. Evidence is in
`/tmp/thistle-av-final-server.log`, `/tmp/thistle-av-final-repeat-assault.log`,
and Horde screenshots `repeat-opening` and `repeated-assault-complete`.

The final supply and scoreboard run used Alliance session
`/home/pikdum/.cache/thistle-wow-playtest.z2QAjG`, Horde session
`/home/pikdum/.cache/thistle-wow-playtest.mbFkBZ`, and server log
`/tmp/thistle-av-supply-server.log`. Runtime evidence:

- `/tmp/thistle-av-supply-entry.log`: active match and shared world.
- `/tmp/thistle-av-supply-owner-loot.log`: Alliance collection.
- `/tmp/thistle-av-supply-after-loot-count.log` and
  `/tmp/thistle-av-supply-respawn.log`: chest removal and respawn.
- `/tmp/thistle-av-supply-horde-capture.log` and
  `/tmp/thistle-av-supply-stale-click.log`: ownership change and retained item count.
- `/tmp/thistle-av-supply-horde-loot.log`: Horde collection.
- `/tmp/thistle-av-supply-before-victory.log` and
  `/tmp/thistle-av-supply-victory.log`: captain counters, rewards, and final state.
- `/tmp/thistle-av-supply-exit.log`: both original positions, status `:none`,
  zero matches, empty reservations, and zero remaining instance entities.

Final screenshots include `alliance-loot-ready`, `stale-loot-before-takeover`,
`stale-loot-after-takeover`, `horde-loot-ready`, `final-alliance-score`,
`final-horde-score`, `returned-from-victory`, and `returned-from-defeat`.
`/tmp/thistle-av-supply-gpu.log` records AMD DRM engine activity for both WoW
processes and their separate helper-owned cgroups. Both clients and the server
were stopped after the run; artifacts remain available locally.

The final run had no error-level messages or spell validation failures.
Unimplemented account-data, GM-ticket, and meeting-stone requests are existing
login warnings. One test setup cast selected the shaman itself because the
captain's full name was required; godmode prevented damage, and the subsequent
correctly targeted cast killed Balinda.

## Automated validation

Coverage includes all node state transitions, obsolete timers, neutral Snowfall,
permanent tower destruction, mine ownership and reclamation, all six supply
variants, captain/general reward idempotence, incarnation-aware creature credit,
seven-field score packets, graveyard selection, banner reset ordering, spawn
respawn suspension, copy isolation, and teardown. VMangos tests pin actual
objective and supply bindings; map tests require AV geometry and area context.

Validation for `6d1784bd` passed with playtest processes stopped before the final
native run. No source changed afterward:

- `mix test.all`: 5,976 passed, including DBC, VMangos, and Namigator tests.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2,247 files.
- `mix format --check-formatted` and `git diff --check`: passed.

Logs are `/tmp/thistle-av-supply-all.log`, `/tmp/thistle-av-supply-compile.log`,
and `/tmp/thistle-av-supply-credo.log`. The map bake log is
`/tmp/thistle-av-map-bake.log`.
