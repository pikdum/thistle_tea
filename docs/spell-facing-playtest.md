# Spell facing at initiation and launch

Implemented in `d97a19cf` and tested on 2026-09-27 with the native build-5875
client, Debugmage (GUID 5, level 50), and a fresh local server.

## Rules and ownership

Combat-range abilities require their target in front of the caster. Other
player spells use the existing VMangos `face_target` custom flag: Fireball,
Frostbolt, Smite, and similar spells require facing, while Corruption, Renew,
and Lesser Heal do not. Queued next-swing abilities defer to swing readiness;
triggered casts bypass the forward-target requirement. Creature ranged spells
retain their existing AI turning behavior.

Spell facing uses a 180-degree arc, with a planar center-distance exception
strictly below 1.4 yards. Backstab's behind-target rule and Gouge's requirement
that the target face the caster remain distinct from the caster's facing.
The client receives `UNIT_NOT_INFRONT` (0x7C) for a backwards caster, while
the existing positional failures retain their separate codes.

The pure `Spell.Facing` module serves initiation validation and the existing
cast-requirements flow. At launch, the boundary snapshots current target
position through `World.position/1` and orientation through Metadata. The
owner validates those facts against its current orientation before paying
costs, resolving ammunition, starting recovery cooldowns, or launching effects.
No new world or process dependencies were added to the functional core.

Compared with VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`, principally
`Spell::CheckCast`, `Spell::CheckRange`, and `WorldObject::IsFacingTarget`.
The failure code matches the vanilla `SMSG_CAST_RESULT` definition in
`refs/wow_messages`.

## Automated acceptance

All **7,276 tests** passed, including database/map integration tests and the
architecture dependency ratchet. Compilation with warnings as errors passed;
strict Credo found zero issues across 2,568 source files.

Eleven new tests cover wrapped angles, the semicircle boundary, exact overlap
distance, triggered and queued exceptions, player/creature differences,
Backstab/Gouge directionality, Auto Shot initiation, authored VMangos flags,
and exact failure payloads. Boundary tests move or turn during preparation,
verify the current target snapshot, and exercise owner delivery of the failure.
Failed launch preserves mana and recovery cooldowns; turning back permits a
successful retry that spends power and starts the configured cooldown.

## Native Fireball acceptance

The mage stood at `{16626.2, 16268.1, 69.45}` on map 451, approximately 27 yards
west of the seeded level-four Defias Thug
`17379390962661271572`. Godmode remained disabled. Rank-one Fireball (133) had
custom flag 128, a 1,500-ms cast time, 30-mana cost, and 35-yard range.

A read-only 25-ms sampler observed both owners. Native held turn keys changed
facing during the first cast, then restored facing for the next cast:

| Relative time | Authoritative result |
| --- | --- |
| 3,471 ms | Fireball prepares facing east; mana 3,693; target health 86 |
| 4,635 ms | Caster faces west at 3.19176 radians; cast still preparing |
| 4,976 ms | Cast fails; mana remains 3,693; target remains 86; no combat |
| 8,665 ms | Retry prepares facing east at 6.28004 radians |
| 10,182 ms | Successful launch spends 30 mana and enters combat |
| 11,310 ms | Projectile hits for 25; target health becomes 61 |
| 13,312 ms | Fireball's first periodic tick leaves target health 60 |
| 14,636 ms | Retreat clears combat and the creature resets to 86 health |

The client displayed **Target needs to be in front of you**, a red Failed cast
bar, and `SPELLCAST_FAILED` at 318180.519 seconds. On retry it displayed
`SPELLCAST_STOP` at 318185.719 and the 25-point Fireball hit at 318186.852.
The successful screenshot includes the target's Fireball debuff.

An earlier Lua turning attempt was blocked by the client and produced a normal
forward cast; it was excluded from turning acceptance. The accepted sequence
used native keyboard input. A preliminary successful rejection sampled the
cleared selected-target field after teleport; the final sampler used the
known creature GUID and established both actors' state throughout.

## Native unrestricted spell control

The existing `.learn 172` command taught rank-one Corruption for the control.
Its custom flags were zero. The mage remained facing west at 3.19176 radians
while targeting the same creature to the east.

Corruption began preparing at 2,351 ms, completed its two-second cast at
4,353 ms, spent 35 mana, and appeared on the target. Its first two ticks dealt
13 each at 7,349 and 10,361 ms. The client showed a successful cast and the
Corruption debuff while the character faced away. Retreat at 11,328 ms cleared
combat and the creature's aura during its normal reset. This confirms that
hostility alone does not impose facing.

## Cleanup and retained evidence

After retreat, the mage had full mana, no active cast, and no combat state.
Normal logout returned to character selection and removed the owner, position,
and metadata. Stored character state had no cast or combat. The helper-owned
client and retained server were stopped. No server errors occurred; warnings
were the existing account-data updates and GM-ticket query.

WoW PID 2531384 ran in the helper's owned cgroup. Its own amdgpu graphics
counter advanced from 1,520,934,957 to 17,403,231,425 ns during acceptance.

- Session: `/home/pikdum/.cache/thistle-wow-playtest.IHqPH1`.
- Screenshots: `screenshots/facing-failure-verified.png`,
  `screenshots/forward-success.png`, `screenshots/unrestricted-success.png`,
  and `screenshots/logged-out.png`.
- Samples: `/tmp/thistle-spell-facing-verified-sample.log` and
  `/tmp/thistle-spell-facing-unrestricted-sample.log`.
- Setup and cleanup: `/tmp/thistle-spell-facing-native-before.log`,
  `/tmp/thistle-spell-facing-retreated.log`, and
  `/tmp/thistle-spell-facing-logout.log`.
- Server, warning audit, GPU proof, and final gates:
  `/tmp/thistle-spell-facing-{server,warnings,gpu-before,gpu-after,all,compile,credo}.log`.
