# Fall damage

The pure `Entity.Logic.Falling` rule tracks the highest received airborne
position, using transport-local height when attached to a transport. A
`MSG_MOVE_FALL_LAND` packet consumes that fall once. Swimming, grounded
movement, teleports, server-driven paths, and death discard tracked falls.

The height threshold, minimum fall time, and damage formula follow
`Player::HandleFall` in `refs/vmangos/src/game/Objects/Player.cpp`:

- Require a long-fall movement flag, at least 1,229 ms, and 14.57 yards.
- Subtract Safe Fall aura amounts from the height before computing
  `(0.018 * height - 0.2426) * maximum_health`.
- Apply physical damage percentage modifiers and cap at maximum health.
- Ignore dead players, ghosts, god mode, taxi flights, Slow Fall, hover,
  and physical immunity.
- Bypass absorption shields and damage splitting, matching the 1.12
  environmental-damage path. Use the existing health and death transition.

The combat-log packet follows
`refs/wow_messages/wow_message_parser/wowm/world/combat/smsg_environmentaldamagelog.wowm`.
Slow Fall changes use the existing movement sequence and consume
`CMSG_MOVE_FEATHER_FALL_ACK` only for the matching character, counter, and
enabled state. The build-5875 client sends `0x3F800000` when enabling;
the apply word is interpreted as nonzero, as in VMangos's
`MoveFlagChangeAck::ReadFromWorldPacket`.
This slice does not implement other environmental hazards or durability loss.

## Repeatable client checks

Use the isolated client helper and a fresh local server. Wait for
`Debug seed ready` before logging into `debug/debug`.

1. Enter as Debugwarrior, with god mode off, and record health.
2. Run `.go xyz 16303.2 16318.1 79.44 451`. Tap jump to start falling if
   needed. The ground is near 69.445; health should remain unchanged.
3. Repeat from height 99.44. The landing should reduce health once and
   produce a falling-damage combat-log entry. Sample owner health during
   the landing because out-of-combat regeneration starts soon afterward.
4. Repeat from height 169.44. Expect zero health, the death animation,
   a falling-damage entry, and the Release Spirit dialog.
5. Log into Debugmage, add Light Feathers with `.additem 17056 5`, and
   cast Slow Fall before dropping from height 99.44. Confirm the aura is
   active through landing, god mode is off, and health remains unchanged.

Actual received heights can be below the teleport height because the first
airborne movement packet arrives after falling has started. Expected damage
must use the recorded fall height rather than the teleport destination.

Automated tests cover Safe Fall reductions, physical immunity, absorption
bypass, damage modifiers, repeated landings, negative elevations, swimming,
transport changes, teleport resets, server movement, death, and packet bytes.

## Observed on 2026-09-16

The isolated build-5875 client exercised all five steps against the local
server. A read-only owner sampler recorded the landing health transitions.

| Scenario | Observed result |
| --- | --- |
| Short warrior drop | Stayed at 2,489/2,489 HP. |
| Damaging warrior drop | Recorded height 97.0286, ground 69.4449; HP fell from 2,489 to 1,858. Client combat log displayed 631 falling damage. |
| Lethal warrior drop | HP fell from 2,489 to zero; death finalized, with the death animation and Release Spirit dialog. |
| Mage with Slow Fall | Stayed at 1,875/1,875 HP through descent and landing, with god mode off. |
| Slow Fall acknowledgments | A fresh session consumed enable and disable acknowledgments; no pending movement acknowledgments remained. |

Client screenshots and server/probe logs were retained in the helper session
`/home/pikdum/.cache/thistle-wow-playtest.IkJyqS`. The client and local server
were stopped afterward. No player-owner crash occurred during the gameplay
checks. The initial login preceded debug-account seeding and was retried;
unrelated unimplemented login/UI packet warnings remain. The Slow Fall ACK
warning encountered during the first pass was fixed and retested.
