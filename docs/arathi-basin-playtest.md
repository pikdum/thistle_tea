# Arathi Basin acceptance

Native build-5875 acceptance on 2026-09-23, using fresh local servers and isolated
GPU clients. The implementation follows `refs/vmangos/src/game/Battlegrounds/BattleGroundAB.cpp`
and `BattleGroundAB.h`; no dungeon scripts or runtime database queries were added.

## Gameplay

Level-50 Debugmage (Alliance, GUID 5) and Debugshaman (Horde, GUID 8) entered
Arathi Basin through `.bg join arathi` and the client's **Enter Battle** button.
Both occupied map 529, instance 1. `.bg start` shortened preparation only;
Opening casts, capture delays, resources, resurrection waves, and victory ran
through their normal gameplay paths.

| Check | Observed result |
| --- | --- |
| Initial spawns | Neutral banners appeared without the competing faction banners or guards. |
| Neutral claim | An Opening cast claimed the Stables; both clients saw the contested Alliance banner and announcement. |
| Counter-assault | Horde replaced the neutral claim, then Alliance counter-assaulted. Each claim waited a new minute. |
| Capture and defense | Alliance captured the Stables. Horde's subsequent assault suspended control; Alliance's defense restored control immediately and credited one defended base. |
| Graveyards | During the assault, the Alliance graveyard fell back to its base. Defense restored the Stables graveyard at `{1201.8695, 1163.1306, -56.2860}`. |
| Death and resurrection | `.die`, **Release Spirit**, and the Alliance Spirit Guide queued a normal resurrection wave. The client displayed the countdown; health returned to `1875/1875` at the Stables graveyard. |
| Other nodes | Blacksmith, Farm, Lumber Mill, and Gold Mine accepted real Opening casts and completed their capture timers. |
| Quest objectives | Quest 8105 reached `:complete` with all four required objective counts at one; the client displayed the objective updates. |
| Pickups | Speed appeared on the client and its pickup disappeared. A later read observed its respawn. A second run sampled the live speed aura and movement output immediately after pickup. |
| Opponent presentation | The Horde map showed the same controlled nodes. Its final scoreboard showed Alliance victory at 2000 resources and awarded one Arathi Basin Mark of Honor. |

The first reconnect test exposed a shared login defect: `Player.Instances.restore/3`
sent battleground copies through dungeon admission, returning the character to
their home bind. Restoration now asks the battleground owner to resume its
reservation. Regression coverage includes Warsong and Arathi, plus expired
reservations falling back safely.

A fresh server verified the fix: logout preserved the pending Stables claim;
login restored the exact map, instance, position, assault count, and original
return destination. The player became `:inside` again and the claim completed.

The fresh five-base match ended at 2000 resources with the player still inside.
The native scoreboard showed five assaulted bases and 1323 bonus honor. The
realm honor ledger independently recorded `1323.0` contribution with no kills;
inventory contained three marks (20559), and League of Arathor reputation (509)
was 110, including the human racial bonus. The pickup owner was absent after
victory. The immediate Speed probe recorded spell 23451 and run speed `14.0`.
After the normal two-minute exit countdown, the player returned to the original
Programmer Isle position. Match lookup returned `nil`, battleground status was
`:none`, the world had zero entities, and both its event selection and pickup
registry entries were absent.

The same fresh server also passed a Warsong regression: map 489, instance 2,
restored its exact saved position on reconnect; native Horde flag pickup applied
23333 and changed the flag to `:carried`; returning it to the Alliance base
scored `1–0` and entered the normal flag respawn state. Leaving returned to
Programmer Isle and removed the remaining world entities.

## Evidence

- First Alliance session: `/home/pikdum/.cache/thistle-wow-playtest.hyTFZp`.
- First Horde session: `/home/pikdum/.cache/thistle-wow-playtest.7SNb6a`.
- Fresh follow-up session: `/home/pikdum/.cache/thistle-wow-playtest.sZ6MXC`.
- Server logs: `/tmp/thistle-arathi-server.log` and `/tmp/thistle-arathi-fixed-server.log`.

Screenshots include `opening-stables`, `stables-claimed`, `stables-counterassault`,
`stables-defended`, `arathi-resurrection-queue`, `arathi-resurrected`,
`arathi-node-map`, `arathi-horde-victory`, `fixed-reconnect`, and `fixed-speed`.
Final evidence includes `fixed-victory`, `fixed-auto-exit`, `warsong-reconnect`,
`warsong-carried`, and `warsong-captured`.
Each session's WoW process recorded active AMD DRM engine counters on the RX 7900 XT.

The first run includes one expected duplicate-character login rejection while
selecting Debugshaman in the second client. Unimplemented account-data, raid-info,
GM-ticket, and meeting-stone requests are existing login warnings. No gameplay
owner crashes or unsupported Arathi interactions occurred.

## Automated coverage

Tests cover neutral counterclaims, immediate defense, obsolete capture/banner
timers, all five resource rates, retained resource progress across ownership
changes, normal/weekend reward thresholds, score clamping, victory idempotence,
quest credits, graveyard selection, resurrection cleanup, and complete initial
world states. Spawn tests cover shared event members, independent copies,
activation, refresh, delayed reactivation, and teardown. Pickup tests cover
rotation, delayed respawn, and owner-lifetime cleanup.

Final validation passed with all playtest clients and servers stopped:

- `mix test.all`: 5,198 passed, seed 578668, including DBC, VMangos, and map tests.
- `mix compile --warnings-as-errors` and `mix format --check-formatted`: passed.
- `mix credo --strict`: zero issues.
- `git diff --check`: passed.

Final reference review aligned the pickup activation radius with VMangos's
three-yard battleground trap behavior. Weekend rewards are covered by automated
tests; native acceptance used normal rewards and level-50 characters.
