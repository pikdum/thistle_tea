# Underwater breathing

Players have a 60-second breath reserve. Submersion starts the client breath
bar; surfacing restores breath at ten times normal speed. Diving again retains
the partially recovered reserve. Leaving water, dying, or enabling god mode
stops the timer. Expiration deals one-fifth of maximum health plus a random
amount from zero to level minus one, followed by a pulse every two seconds.
Late owner ticks apply one pulse rather than a burst of accumulated damage.

Water Breathing and Unending Breath replenish breath underwater. Removing or
expiring protection resumes the reserve. Percentage breathing auras extend the
maximum multiplicatively; the Forsaken passive gives a four-minute reserve.
Physical immunity suppresses drowning, while damage shields do not absorb it.
Health loss uses the existing death lifecycle and environmental combat log.

Movement and behavior-tree boundaries supply terrain liquid height and random
rolls to pure breathing logic. Stationary swimmers and players with an active
reserve remain scheduled. Client mirror timers are owner-local typed effects.
Model collision heights are preloaded into ETS, including display/model scale;
movement and ticks perform no model database queries. The pinned DBC converter
calls column 15 `mount_height`, so the schema maps Vanilla collision height to
that column instead of mistakenly reading collision width from column 14.

Reference rules are in `refs/vmangos/src/game/Objects/Player.cpp`
(`UpdateMirrorTimers`, `OnMirrorTimerExpirationPulse`, `EnvironmentalDamage`),
`MirrorTimer.cpp`, `Unit.cpp` (`UpdateModelData`), and
`refs/vmangos/src/game/Database/DBCStructure.h`. Packet layouts come from
`refs/wow_messages/wow_message_parser/wowm/world/spell/`.

The feature covers breath and drowning. Ocean fatigue and lava/slime hazards
need liquid-type information beyond the current Namigator surface-height API.

## Follow-up fixes

The initial fixed waterline threshold was replaced with per-model geometry.
A separate spell-learning bug found during acceptance left newly learned
passives inactive until login. The shared learning boundary now applies them
immediately, with regression coverage for extended breathing and for active
spells remaining uncast.

Further live sampling found that movement-only timer effects could wait behind
a long aura wake. Movement now drains those effects and re-evaluates the next
wake without requiring a unit-field broadcast. A map integration regression
also covers aura expiry while standing underwater with no swimming flag.
Changing the maximum reserve preserves the time already spent underwater.

## Real-client acceptance

Used the isolated build-5875 client with Debugwarrior in Crystal Lake, map 0,
near `-9500 -220 55.47`. Liquid surface was `57.6738`; the character's cached
model height was `1.913`. Inputs were ordinary movement, inventory use, buff
cancellation, and existing developer commands. Runtime probes only read owner
state.

- The client displayed a draining Breath bar underwater. A stationary character
  took repeated drowning damage, including a visible 499-point hit, then died.
  The breath bar disappeared; spirit release and client corpse reclamation
  completed successfully.
- Consuming item 5996 through the client's `UseContainerItem` applied aura 7178.
  On the final build, the remaining reserve switched to recovery (`scale: 10`)
  and then cleared while the player remained underwater.
- After 93 seconds submerged with the elixir, health remained at 2489 and no
  breath timer was active. Right-click cancellation restarted the 60-second
  reserve without movement. Holding the swim-up key switched it to recovery;
  the bar then disappeared at full reserve, with health still 2489. Screenshots
  `final-protected.png`, `final-cancelled.png`, and `final-surfaced.png` show the
  client presentation, and timed owner samples record the transitions.
- Learning passive 5227 immediately applied it without relogging. A subsequent
  dive displayed the Breath bar and owner state showed a `240000` ms maximum.
- Final-build stationary sampling showed the reserve decreasing each second
  with scheduled owner wakes, rather than waiting for another movement packet.

The first attempted spell 11789 is passive and cannot be actively cast; it
helped expose the learning bug. Vanilla also lacks the attempted `/use` macro
command, so the successful consumable check used `UseContainerItem` instead.
Neither unsuccessful input is counted as acceptance.

Validation: `mix compile --warnings-as-errors`, `mix test.all` (2,893 passing),
`mix credo --strict`, formatting, and diff checks. Default tests cover timer
transitions, damage/death, modifiers, immunity, packet bytes, owner-local
projection, and scheduling. DBC tests cover actual spell effects and collision
height extraction; map tests cover stationary underwater aura expiry.

Evidence remains in:

- `/home/pikdum/.cache/thistle-wow-playtest.APWlmQ/screenshots/`
- `/tmp/thistle-breath-server.log` (initial drowning and corpse recovery)
- `/tmp/thistle-breath-server-final.log` (model heights and extended breathing)
- `/tmp/thistle-breath-server-acceptance.log` (final code)
- `/tmp/thistle-breath-drowning.txt`
- `/tmp/thistle-breath-extended.txt`
- `/tmp/thistle-breath-final-stationary.txt`
- `/tmp/thistle-breath-final-protected.txt`
- `/tmp/thistle-breath-final-protected-end.txt`
- `/tmp/thistle-breath-final-cancelled.txt`
- `/tmp/thistle-breath-final-surface.txt`
- `/tmp/thistle-breath-final-surfaced.txt`
- `/tmp/thistle-breath-tests-final.log`

The final server log had no gameplay/owner errors. It still reports unsupported
client housekeeping opcodes such as account-data updates and time queries;
those are not evidence of a clean protocol surface overall.
