# Trap detection and disarming acceptance

Hostile stealthed traps now require trap detection before they appear to a
player. Owners and friendly players can still see them. The visibility gate
uses the trap template's `data9` flag and invisibility detection type three,
including changes while the observer stands still. Owned traps use their
owner's hostility rules. Hidden objects remain visibility candidates so
learning or losing detection can create or destroy the client model.

Disarm Trap (1842) now deactivates a valid trap through the existing open-lock
path without triggering it, opening loot, or consuming Thieves' Tools. Both
initial targeting and completion check visibility, range, world, and lock
requirements. The object marks itself depleted before removal, preventing
stale activation or open requests. Temporary traps use the existing despawn
and owner-monitor cleanup. Static traps use the spawn pool's respawn delay;
ordinary finite-charge activation now uses that same transition.

No new packets, developer commands, database queries in gameplay paths, or
architecture allowlist entries were added.

Reference: VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`src/game/Objects/GameObject.cpp:1128` (visibility), `:2076` (hostility),
`:603` (deactivation), and `src/game/Spells/SpellEffects.cpp:2017`
(`SendLoot`, including disarm lock type four).

## Native acceptance

Two isolated build-5875 GPU clients ran against implementation commit
`c54dc71b`: Debughunter (GUID 7, level-50 dwarf hunter) and Debugrival
(GUID 12, level-50 orc warrior). The opposing-faction observer received
Disarm Trap (1842), Stealth (1784), and Detect Traps (2836) through native
`.learn` commands. This exercises the shared spell system with developer
learned rogue abilities; it does not test rogue trainer progression.

Both players stayed on Programmer Isle, map 451. The trap site was
`{16303.2, 16257.1, 69.44}`; the observer stood at
`{16299.2, 16255.1, 69.44}`, about 4.47 yards away, within disarm range and
outside the trap's activation radius. All gameplay mutations used native
client input. Tidewave probes were read-only.

- Freezing Trap (1499, object entry 2561) created GUID
  `17370383805747036263`. The hunter tracked it immediately; the hostile
  observer retained it as a candidate but neither tracked nor saw it.
  Native `.learn 2836` made that same trap appear without moving the
  observer. See `hidden-trap.png`, `detected-trap.png`, `hidden.txt`, and
  `detected.txt`.
- The first disarm attempt correctly displayed “Requires Thieves' Tools”
  before sending a cast. Native `.additem 5060` supplied the verified item.
  This attempt was not a successful disarm; the first trap expired later.
- A fresh trap, GUID `17370383805747036324`, was targeted with native
  `/cast Disarm Trap` while the observer remained stealthed. The client
  displayed its two-second cast bar, and the server received spell 1842
  against that exact object. After completion, both clients showed empty
  ground. The object process, registry entry, position, metadata, owner
  monitor, and observer candidate were absent 42.916 seconds after creation,
  before its 60-second expiry. Health remained 2,669, stealth and Detect
  Traps remained active, one Thieves' Tools remained, and no loot session
  opened. See `disarm-cast.png`, `disarm-complete.png`,
  `disarm-complete-owner.png`, `before-disarm.txt`, `after-disarm.txt`, and
  `disarm-proof.txt`. The `after-disarm.txt` probe captured the in-progress
  cast; `disarm-proof.txt` records completion.
- Native logout removed the observer's player process. Reconnect created a
  new owner process with Detect Traps still active, the same health, and no
  loot or cast in progress. A newly placed hostile trap appeared immediately.
  See `logged-out.png`, `reconnected.png`, `reconnect-detection.png`,
  `logged-out.txt`, `reconnected.txt`, and `reconnect-trap.txt`.

Native coverage establishes hostile detection, disarming, stealth retention,
tool requirements, and reconnect behavior. Static respawn timing, detection
loss, changing owner hostility, guessed hidden GUIDs, and invalid completion
contexts are covered by automated tests.

The live log contains no errors or trap-related warnings. Existing unsupported
account-data, ticket, and meeting-stone requests were the only warnings.

## Automated checks

- `mix test.all`: 6,806 passed in 62.7 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2,459 source files.
- Focused visibility, disarming, object, pool, and DBC checks: 60 passed.
- Formatting and pre-commit checks passed.

The 12 added tests cover trap construction, hostile and friendly visibility,
exact detection type, stationary reevaluation, hidden candidate retention,
safe open-lock completion, stale requests, owner-monitor cleanup, and delayed
static respawn after both disarming and activation. Spell and lock data
checks use the DBC tag; gameplay tests requiring geometry use the map tag.
Default tests use synthetic data.

Build and runtime used
`NAMIGATOR_SRC=/nix/store/3nds85i5fyjgpqcgjnk03fdfgs798vfn-namigator-with-wmo-metadata`.

## Retained evidence and cleanup

Client sessions, including their `screenshots/` directories:

- Hunter: `/home/pikdum/.cache/thistle-wow-playtest.EelgPS`.
- Observer: `/home/pikdum/.cache/thistle-wow-playtest.jyoIa3`.

Probe, gate, server, and GPU logs use `/tmp/thistle-trap-detection-`.
Screenshots named `disarming.png`, `disarmed.png`, and `disarmed-owner.png`
belong to the rejected attempt. `disarm-success.png` captured the later cast
in progress. The `disarm-complete` screenshots show the accepted result.

Hunter WoW PID 1906458 used AMD DRM client 5742; its graphics counter advanced
from 1,726,384,499 ns to 20,557,698,499 ns. Observer WoW PID 1907520 used DRM
client 5770, advancing from 922,077,955 ns to 21,553,383,701 ns. Duplicate
descriptors were counted once.

The helper stopped matching service invocations
`077a0184fd124080a39d014ac4166b68` and
`740a517c0f604f3097bf622541afcfa5`. Both units became inactive with empty
cgroups. Both players and all three observed trap GUIDs were absent from
registry, position, and metadata projections. Server PTY shutdown completed;
server PID 1906672 and both WoW PIDs were absent, and ports 4000, 3724, and
8085 were free. All evidence was retained.
