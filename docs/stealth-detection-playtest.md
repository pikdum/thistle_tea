# Observer-specific stealth detection

Player visibility now applies stealth detection independently for each observer.
The shared pure rules account for level, stealth skill, detection bonuses,
facing, collision distance, stuns, and Vanish's temporary detection immunity.
Perception, Paranoia, and Track Hidden contribute their actual DBC bonuses;
Detect Traps' separate detection type does not reveal stealthed units.
Hunter's Mark reveals a concealed target to its caster. Existing party and
owner visibility exceptions remain available.

The reference is `Unit::CanDetectStealthOf` and the surrounding visibility
checks in `refs/vmangos/src/game/Objects/Unit.cpp`. At equal skill, a player
detects another player at nine yards and a creature at 21 yards. Skill
differences adjust the range, capped at 30 yards before the nine-yard rear
penalty. Collision detection applies below 1.5 yards. Ordinary stealth
detection also requires line of sight.

The entity owners publish concealment and detection metadata. Each observer
reevaluates nearby stealthed entities every 500 milliseconds using current
positions, including projected movement within the same cell. Aura changes
publish immediately through the existing visibility transition. Timer
references reject stale messages after world changes; leaving the world
cancels the timer. Hidden entities are removed from the tracked set when
their destroy packet is queued, allowing subsequent detection to recreate them.

Melee swings, Auto Shot, and creature aggro consume the same detection rules
through immutable behavior-tree observations. The follow-up attack fix closes
an older invisibility-only check that could continue attacking a hidden target.
Spell validation already uses the observer's visibility check.

## Automated acceptance

Coverage includes player/creature ranges, detection types and stacks, the
range cap, facing, collision distance, stun and Vanish restrictions,
caster-specific marks, invisibility interactions, Perception expiry and
cancellation, death cleanup, creature aggro, and retained melee/Auto Shot
targets. Map-tagged visibility tests cover create/destroy transitions,
movement by either side within a cell, client aura cancellation, and timer
teardown and stale-message rejection. The architecture ratchet is unchanged.

Final validation passed: `mix test.all` (3,309 tests),
`mix compile --warnings-as-errors`, and `mix credo --strict` (zero issues).

## Two-client acceptance

Two isolated build-5875 clients controlled level-50 Debugwarlock and
Debugrogue on Programmer Isle. Actions came from the clients; Tidewave
probes only read owner state, metadata, and world positions.

- At 20 yards, Debugrogue was visible before Stealth. Casting Stealth hid
  the model and removed GUID 3 from the observer's tracked set. Metadata
  reported stealth skill 250 and no observer detection bonus.
- Casting Perception revealed the stealthed rogue at the same position.
  The client showed the translucent model, target frame, and Perception
  buff. A sampler recorded detection bonus 50 and tracked membership,
  followed about 20 seconds later by bonus zero and removal. Expiry hid
  the rogue without movement.
- Moving the rogue to eight yards revealed them without Perception.
  Turning the observer to orientation 3.0535 hid them; turning back restored
  visibility. Walking the observer backward to 16.35 yards hid them again.
- Cancelling Stealth through the rogue client cleared stealth metadata
  and recreated the rogue for the observer.
- The observer learned Hunter's Mark using the existing `.learn` command.
  During an accepted duel, marking the detected rogue and moving them to
  40 yards preserved visibility. The rogue remained stealthed and metadata
  contained `stalked_by: [6]`. Forfeiting the duel removed the mark and hid
  the rogue again.
- Using `.die` on the still-stealthed rogue produced health zero, removed
  Stealth, and revealed the corpse. Stopping both clients removed both
  entity owners and their metadata. The local server was then stopped.

The attack follow-up was validated with deterministic behavior-tree tests;
the live duel verified mark visibility and cleanup rather than damage delivery.
The server reported no stealth, visibility, movement, or owner crashes. The
second client's initial automatic selection of the already logged-in warlock
was rejected normally; selecting the rogue succeeded. Existing unsupported
client housekeeping requests were also logged.

## Evidence

- Observer screenshots: `/home/pikdum/.cache/thistle-wow-playtest.k0L5nL/screenshots/`.
- Rogue screenshots: `/home/pikdum/.cache/thistle-wow-playtest.TMOuQM/screenshots/`.
- Authoritative snapshots: `/tmp/thistle-stealth-hidden.txt`,
  `/tmp/thistle-stealth-perception-timeline.txt`, `/tmp/thistle-stealth-facing.txt`,
  `/tmp/thistle-stealth-movement.txt`, `/tmp/thistle-stealth-cancelled.txt`,
  `/tmp/thistle-stealth-mark.txt`, `/tmp/thistle-stealth-mark-removed.txt`,
  `/tmp/thistle-stealth-death.txt`, and `/tmp/thistle-stealth-logout.txt`.
- Server log: `/tmp/thistle-stealth-server.log`.
- Final checks: `/tmp/thistle-stealth-final-tests.log`,
  `/tmp/thistle-stealth-final-compile.log`, and `/tmp/thistle-stealth-final-credo.log`.
