# Molten Core hound packs

Core Hounds (entry 11671) now use a reusable scripted feigned-death lifecycle.
Lethal damage leaves them at one health with the dead pose and dynamic dead
flag, removes their auras, stops casting and movement, and applies Pacify Self
(19951). Threat, tap, and combat remain intact. Additional damage, healing,
and regeneration cannot disturb the fallen state.

After ten seconds, a fighting Core Hound above one health within 100 yards in
the same world copy causes a full-health revival, removes pacify, and runs the
revival visual and text. Without that peer, the fallen hound kills itself and
despawns. Losing the opponents resets the fallen state through normal evade;
respawn creates a fresh configuration. Serrated Bite (19771) runs every four
to seven seconds while fighting.

The reference is `mob_core_houndAI` in
`refs/vmangos/src/scripts/eastern_kingdoms/burning_steppes/molten_core/molten_core.cpp`.
The pure `Creature.LinkedFeignDeath` rule consumes behavior-tree perception;
the script supplies entry, range, delay, pacify spell, and fall/revival hooks.
It uses the shared damage, engagement, effects, and entity-owner paths.

## Native acceptance

Tested on 2026-10-10 with the build-5875 client and a fresh local server.
Debugshaman (GUID 8), level 60 with god mode, entered Blackrock Depths through
area trigger 1466, then Molten Core through trigger 2886. A raid was assembled
through the existing Party API. The resulting world was map 409, instance 2.
The test used the seeded five-hound pack, database GUIDs 56629 through 56633.

After entry, the character moved to `{1036, -977, -181.254}` in the existing
copy. Lucifron and his two Flamewaker Protector guards were killed through
the existing damage API to isolate this pack from Dominate Mind. Autorun was
stopped before the timed runs. Read-only owner samplers started before the
native client actions.

- A native `.damage 100000` caused collapse at sampler time 1,990 ms: health
  1, stand state 7, dynamic flags 36, pacify present, and combat retained.
  At 11,989 ms it revived with health 47,160, stand state 0, flags 4, pacify
  absent, and its 100,000 threat against the player retained. The client
  displayed both collapse and reignition text and resumed combat.
- Killing pack members too slowly produced successive revivals. Sending the
  five commands through chat took longer than the first revival deadline.
- A native action-bar macro selected the nearest enemy and issued the same
  damage command. Five presses downed the pack between 872 and 2,253 ms.
  Each hound died and was removed after its own ten-second deadline; all
  five were removed by 12,231 ms. Their owners remained alive, health was
  zero, corpse removal was complete, and their world positions were absent.
  Twenty nearby idle Core Hounds did not revive the defeated pack.
- The existing `respawn_creature` script command restored all five: health
  47,160, no fallen deadline or pacify, death finalization cleared, corpse
  removal cleared, and world/health metadata published in the same copy.
  The native client showed the pack fighting again.

Earlier attempts were excluded from timer acceptance because autorun and a
mid-timer teleport reset combat. The final stationary run retained combat
through the complete revival timer. The fresh server log contains no warnings,
owner crashes, unsupported commands, or network/visibility errors.

## Repair found during playtesting

The seeded Core Hound template also supplies a one-health invincibility
threshold. Applying that clamp before scripted lethal prevention hid the
lethal hit, leaving a hound at one health without entering the fallen state.
The shared damage funnel now applies scripted prevention before the template
clamp. A regression covers this exact combination.

Implementation: `9be3fa79`; damage-order repair: `84f3ed59`.

## Validation and retained evidence

`devenv shell mix test.all`: 8,796 passed. Compilation with warnings as errors,
strict Credo, formatting, and `git diff --check` passed. Pure tests cover lethal
and nonlethal hits, protection while fallen, timing, revival, no surviving
peer, range, entry, copy isolation, wipe/reset, and respawn. Owner integration
tests cover spell hooks, update packets, metadata, corpse removal, and reuse.

Final GPU session: `/home/pikdum/.cache/thistle-wow-playtest.RpZ3zR`.
WoW PID 88181 belonged to that session's recorded service cgroup and used
amdgpu client 231; its graphics counter increased from 6,419,295,990 to
6,965,748,328 ns. The helper-owned client service and retained server PTY were
stopped after acceptance.

Retained local evidence:

- Screenshots in the session's `screenshots/`: `molten-core-entry.png`,
  `hound-fallen-stationary.png`, `hound-revival-view.png`,
  `pack-fallen-fast.png`, `pack-removed.png`, and `pack-respawned.png`.
- `/tmp/thistle-core-hound-accepted-revival-stationary.json`
- `/tmp/thistle-core-hound-accepted-pack.json` (slow kills and revivals)
- `/tmp/thistle-core-hound-accepted-pack-fast.json`
- `/tmp/thistle-core-hound-accepted-defeat.json`
- `/tmp/thistle-core-hound-accepted-respawn.json`
- `/tmp/thistle-core-hounds-accepted-server.log`
- `/tmp/thistle-core-hounds-final-tests.log`
- `/tmp/thistle-core-hounds-final-credo.log`
