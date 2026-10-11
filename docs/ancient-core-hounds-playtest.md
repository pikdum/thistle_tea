# Ancient Core Hound acceptance

Tested on 2026-10-10 with the native 1.12.1 build-5875 client against a
fresh local server. The source is `mob_ancient_core_houndAI` in
`refs/vmangos/src/scripts/eastern_kingdoms/burning_steppes/molten_core/molten_core.cpp`.

## Implemented behavior

Ancient Core Hounds (entry 11673) replace their ordinary main-hand swings
with triggered Vicious Bite (19319), using the existing attack timer,
reach, control, and target checks. The shared scripted-melee configuration
falls back to normal attacks when the creature is charmed and preserves
queued next-swing spells. Automatic calls for assistance are disabled.

Cone of Fire (19630) starts after 4–7 seconds and repeats every 6–8 seconds.
Serrated Bite (19771) starts after four seconds, waits until its victim is
in melee in the same world copy, and then consumes its six-second cooldown
even if the cast fails. Each reset selects one of Ground Stomp, Ancient
Dread, Cauterizing Flames, Withering Heat, Ancient Despair, and Ancient
Hysteria. That choice stays fixed for the fight, first firing after 12–15
seconds and repeating every 14–24 seconds after a successful cast.

The generic spell list is disabled on combat entry. Existing Molten Core
instance guards suppress these spawns after Magmadar is defeated.

## Native acceptance

Debugshaman (GUID 8, level 60) entered Blackrock Depths through its real
entrance and then walked through the Molten Core portal in a raid. The
resulting world was map 409, instance 2. Nearby unrelated enemies were
cleared through the existing damage API to isolate the seeded hound,
database GUID 56860, runtime GUID 17379391157875774243.

- A 46-second owner packet trace recorded 22 Vicious Bites at approximately
  two-second intervals and zero ordinary white swings. Serrated Bite
  repeated approximately every six seconds; Cone of Fire repeated within
  its 6–8-second range at the AI tick's resolution.
- The first fight retained phase 6, Ancient Hysteria (19372). Its casts
  occurred at 15.422 and 37.450 seconds. The client displayed the debuff,
  the hound's target frame, and its fire attacks.
- A native teleport reset combat, cleared the victim, and selected phase 1,
  Ground Stomp (19364). Re-engagement retained that new choice; Ground Stomp
  cast at 14.802 and 31.820 seconds of the reset trace. The client displayed
  the stun, and the packet trace again contained zero ordinary white swings.
- Temporarily disabling god mode proved damage reached the player. Vicious
  Bite dealt 1,101 physical damage, Serrated Bite dealt two 250-damage ticks,
  and Cone of Fire dealt 1,583 fire damage. Health changed from 3,230 to
  1,879 and then 46 before god mode was restored.
- Native `.damage 200000` caused ordinary death: health zero, death finalized,
  combat cleared, and no linked feigned-death state. Selecting the corpse
  and using `.respawn` restored all 113,295 health, cleared finalized death,
  and retained Vicious Bite and assistance suppression. The client displayed
  the revived hound; subsequent packets included all three attacks and
  Ground Stomp, with the owner visible in the same copy.
- The fresh server log contained no warnings or errors.

## Repairs and validation

The playtest found that `.go xyz x y z here` rejected an omitted facing
angle despite advertising it as optional. The parser now accepts that form
and keeps the current instance copy; a regression checks the teleport
message's world reference.

Source review also caught Serrated Bite retrying failed casts immediately.
A shared EventAI melee gate now checks reach before consuming the timer,
independently of cast-result checking. Regressions cover distance, copy
isolation, and a busy caster consuming the cooldown once in melee.

Focused combat, EventAI, script, and architecture checks: 68 passed.
`devenv shell mix test.all`: 8,811 passed. Compilation with warnings as
errors, strict Credo, formatting, and `git diff --check` passed.

Implementation: `0e06691e`, `559cb3ad`; parser repair: `bb8e6bfe`;
cooldown repair: `17f15fed`.

## Retained evidence

GPU session: `/home/pikdum/.cache/thistle-wow-playtest.JIs4IH`, unit
`thistle-wow-playtest.JIs4IH.service`. WoW PID 121237 belonged to its service
cgroup and used amdgpu client 352; its graphics counter increased from
4,993,680,121 to 17,725,373,157 ns. The helper-owned client service and retained
server PTY were stopped after acceptance.

The session retains `server.log`, screenshots including
`ancient-hound-debuff.png`, `ancient-hound-repull.png`,
`ancient-hound-damage.png`, `ancient-hound-death.png`, and
`ancient-hound-respawn-accepted.png`, and these accepted traces:

- `thistle-ancient-hound-native.json`
- `thistle-ancient-hound-reset-native.json`
- `thistle-ancient-hound-live-damage-accepted.json`
- `thistle-ancient-hound-respawn-native.json`

Final test, compile, Credo, formatting, and focused-check logs are retained
alongside those traces with the `thistle-ancient-hounds-` prefix.
