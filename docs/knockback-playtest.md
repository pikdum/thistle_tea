# Spell knockback

Implemented and tested on 2026-09-21. Two isolated build-5875 clients ran against
`8fcd87a7`. The subsequent possession delivery fix in `d44d3fa3` received automated
acceptance.

## Behavior and reference

DBC effect 98 now launches players and possessed creatures away from the caster.
Self-targeted launches move backward relative to facing. Horizontal speed comes
from the effect's miscellaneous value divided by ten; vertical speed uses the
rolled effect amount divided by ten with the reference's integer rounding.

The pure core emits a typed `Knockback` effect. The owning connection sequences
`SMSG_MOVE_KNOCK_BACK`, validates `CMSG_MOVE_KNOCK_BACK_ACK` against the issued
mover, counter, direction, and speeds, and consumes each acknowledgement once.
Accepted movement uses the shared player movement boundary for presence,
visibility, transport reconciliation, landing, and movement interruption rules.
Nearby clients receive the separate `MSG_MOVE_KNOCK_BACK` projection.

Preparing casts, channels, and auto-repeat attacks are interrupted. Applying a
self-launch does not interrupt its own spell during impact. Roots, stuns, death,
taxi flight, and server-controlled movement suppress launches. Existing effect
immunity also applies. Dream Fog is removed before the control check, matching
the reference. Ordinary creatures keep server-owned movement while retaining
cast interruption, as in VMangos's player-controlled knockback implementation.

Teleports and worldports invalidate earlier launches. Death or loss of control
prevents late movement relocation. A possessed creature's controller receives
the launch request but is excluded from its observer packet, avoiding a duplicate
launch. Dead possessed creatures also reject subsequent movement packets.

Reference checkout: `refs/vmangos` at `8f4e60845`:

- `src/game/Spells/SpellEffects.cpp`, `EffectKnockBack`: speed inputs and Dream Fog.
- `src/game/Objects/Unit.cpp`, `KnockBackFrom` and `KnockBack`: direction,
  restrictions, interruption, and client-controlled delivery.
- `src/game/Movement/MovementPacketSender.cpp`: controller and observer formats.
- `src/game/Handlers/MovementHandler.cpp`, `HandleMoveKnockBackAck`: pending
  impulse validation and acknowledged movement projection.
- `refs/wow_messages` supplies the build-5875 controller and acknowledgement
  layouts; the observer layout follows VMangos's supported-build writer.

## Automated acceptance

After the possession fix, `mix test.all` passed **4,598 tests**. Compilation with
warnings as errors passed, and strict Credo reported zero issues across 1,803
source files.

Coverage includes direction, self-launching, separate speed inputs and rounding,
cast interruption, Dream Fog removal, root/stun/death/taxi restrictions, immunity,
possessed movement, wire formats, packet dispatch, counter and impulse validation,
replay rejection, teleport invalidation, authoritative position updates, observer
delivery, fall reset, landing, and control loss. DBC tests load actual Knockback,
Wing Flap, Amnennar's Wrath, and Launch effects with cached rank fixtures.

The architecture dependency ratchet passed without expanding its allowlist.
Existing ordinary movement, fall damage, and possession tests also passed after
moving movement orchestration out of the packet codec into `Player.Movement`.

## Native client acceptance

Debugwarrior (GUID 1) and Debugpaladin (GUID 2) were level 60 on Programmer Isle.
Native `.learn` commands taught Knockback 10689 to both and Hearthstone 8690 to
the Warrior. `.go` positioned them in a clear area. God mode was not enabled;
Tidewave probes only read state.

The Warrior self-cast Knockback while facing east. The sampler first captured
the pending impulse `{-1.0, approximately 0.0, 10.0, -10.0}`, then its successful
acknowledgement. The movement counter advanced from one to two and the pending
map became empty. Observed positions were:

| Stage | X | Z |
| --- | ---: | ---: |
| Before launch | 16,330.000 | 69.440 |
| Airborne sample | 16,325.000 | 72.029 |
| Landing | 16,319.642 | 69.445 |

The displacement was about 10.36 yards backward. Health stayed at 3,299.

The Paladin moved to X 16,314, behind the Warrior, and targeted it. The Warrior
began Hearthstone. Approximately 2.23 seconds later, the Paladin's native cast of
Knockback interrupted it. The Warrior displayed **Interrupted**, its authoritative
cast became nil, and the acknowledged impulse had direction `{1.0, 0.0}`.
The Paladin's client showed the Warrior airborne and landing farther away.

This launch moved the Warrior from X 16,319.642 to 16,329.990, with an airborne
sample at Z 72.034 and ground height 69.445. Its movement counter advanced to
three with no pending acknowledgements. It remained on Programmer Isle beyond
the original Hearthstone completion time; no teleport occurred.

A subsequent native forward keypress moved the Warrior to X 16,333.749. The final
probe showed matching owner and public world positions, movement flags zero,
no active cast, no fall state, and no pending movement acknowledgements. Health
remained 3,299. These observations prove normal control resumed after landing.

Possession routing, duplicate controller suppression, dead-mover rejection,
immunity, and stale acknowledgements were checked automatically rather than in
the native session. The possession follow-up does not change the tested player
launch path.

No server errors, spell-validation failures, or unsupported knockback packets
appeared. Only the existing account-data, raid-info, GM-ticket, and meeting-stone
login warnings were present. Both helper-owned clients, Xvfb processes, and the
server were stopped, retaining the evidence below.

## Local evidence

- Warrior session: `/home/pikdum/.cache/thistle-wow-playtest.VVDcC9`, screenshots
  `self-airborne.png`, `self-landed.png`, `cast-interrupted.png`, and
  `walking-after-landing.png`.
- Paladin session: `/home/pikdum/.cache/thistle-wow-playtest.4CeHfQ`, screenshots
  `observer-before.png`, `observer-airborne.png`, and `observer-landed.png`.
- Server log: `/tmp/thistle-knockback-server.log`.
- Samplers: `/tmp/thistle-knockback-self-sample.txt` and
  `/tmp/thistle-knockback-interrupt-sample.txt`.
- Final state: `/tmp/thistle-knockback-cleanup.txt`.
- Gates: `/tmp/thistle-knockback-{focused,dbc,possession,all,compile,credo}.log`.
