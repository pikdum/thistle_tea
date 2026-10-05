# Alterac Valley cavalry and captured animals

Build-5875 acceptance on 2026-10-04 used an isolated GPU client and a fresh local
server. References were `refs/vmangos/src/scripts/battlegrounds/battleground_alterac.cpp`,
`refs/vmangos/src/game/Battlegrounds/BattleGroundAV.cpp`, and the generated quest,
spell, creature, and waypoint catalogs.

Both teams now collect enemy hides and return captured mounts. Twenty-five of
each resource and Honored reputation permit one cavalry launch per commander
life. Launch consumes the stock, empties the stable displays, summons eight
mounted riders, and starts the commander route, rally speech, and formation.
Captured animals use shared aura transitions for following and cleanup.

## Native acceptance

Level-60 Debugwarrior, Alliance GUID 1, entered Alterac Valley instance 1 through
the queue invitation and native battlefield-port action. Existing developer
commands supplied levels, godmode, hides, source items, travel, and initial
quest fixtures. To make repeated capture
checks practical, `.move` staged seeded wild rams near the stable master and
moved the stable master. Subsequent repeatable acceptance, capture pulses, stable delivery,
quest rewards, and launch used the client. A temporary Lua frame automated
repeatable quest dialogs. Tidewave probes read state without changing it.

| Check | Observed result |
| --- | --- |
| Capture and follow | The Stormpike Training Collar's real item-use action produced tracking aura 21863, with the ram as caster, and following at approximately three yards. |
| Lost animal | Moving beyond the 50-yard leash removed tracking and hid the ram. |
| Mount contributions | Twenty-five captures and native stable deliveries increased authoritative Alliance mount stock from zero to 25, one per quest reward. |
| Hide contributions | Twenty-five native Ram Riding Harnesses rewards consumed 25 Frostwolf Hides and increased hide stock to 25. |
| Reputation gate | At standing 8,999 the commander offered no launch option. At 9,000, Honored, he offered the cavalry launch. |
| Launch | Native gossip selection consumed both stocks, changed phase to marching, and produced exactly eight riders with mount display 2786. |
| Formation | The group had nine members, advanced through authored waypoints, and all eight rider warcries appeared in native chat. |
| Commander death | The existing `.damage` command killed the commander. All eight riders entered their survivor phase; a rider inherited the commander route at waypoint 44. |
| Player death | With a captured ram present, `.die` removed tracking and hid the ram. Its seed owner remained available for ordinary respawn. |
| Logout | Logging out with a newly captured ram removed tracking before saving the character and hid the ram while the match remained running. |
| Reconnect and exit | Reconnect restored no captured-animal aura. Leaving the match returned the character to map 451 and removed the commander owner, all rider owners, and group membership. |

Horde quest mappings, contribution thresholds, scripts, routes, mounts, and
lifecycle transitions have automated coverage. This run did not drive a native
Horde cavalry launch or a hostile-player combat encounter. Tests assert the
one-time 600,000 ms survivor cleanup request and combat dismount/remount
transitions; the native run did not observe that timeout expiring.

## Repairs and automated coverage

Riders now register for commander-death notification before the rally, without
starting formation movement. A rider whose commander dies before the rally, or
is already unavailable at spawn, starts its own route and cleanup request.
Runtime groups retain waypoint routes and cursors that started before group
membership. Joining a leader that died during the join also delivers its death
to the new member and promotes a formed survivor. These final edge cases were
verified with deterministic tests after the native server was stopped.

Captured-animal tests cover two-second checks, dead or missing casters, distance,
world changes, ghosts, release, and live caster-position refresh. A delivery
regression verifies that dismissal retains the creature's original world after
a player map change, so the receiver accepts its cleanup command. Catalog tests
check VMangos routes and repeatable quest requirements separately from DBC
item-use spells.

Repeated native input exposed two helper faults: cursor movement followed
immediately by a click could drag the camera, and Ctrl+A did not reliably select
existing login-field text. The helper now pauses after cursor movement and
clears fields with Home, Shift+End, and Backspace. Repeated mount returns and a
login with deliberately populated fields verified both repairs. Helper cleanup
regressions, Bash syntax checks, and ShellCheck passed.

WoW's own AMD DRM counters confirmed GPU rendering. The owned client service and
retained server were stopped. The final native server had no gameplay-owner,
network, movement, or unsupported-command errors. Its earlier login failures
preceded the helper fix; an attempted Death Touch while out of range produced
the expected validation warning.

## Retained local evidence

- Server: `/tmp/thistle-av-cavalry-server2.log`.
- Mount returns: `/tmp/thistle-av-return-rams2.log`.
- Launch and survivors: `/tmp/thistle-av-cavalry-native-launch.txt` and
  `/tmp/thistle-av-cavalry-native-survivors2.txt`.
- Death, logout, and world cleanup: `/tmp/thistle-av-cavalry-native-death-release.txt`,
  `/tmp/thistle-av-cavalry-native-logout-release.txt`, and
  `/tmp/thistle-av-cavalry-native-world-cleanup.txt`.
- Client screenshots: `/home/pikdum/.cache/thistle-wow-playtest.P7LQ9R/screenshots/`.
- Helper cleanup: `/tmp/thistle-av-cavalry-helper-cleanup.log`.
