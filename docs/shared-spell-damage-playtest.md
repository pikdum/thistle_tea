# Shared spell damage

Meteor and Shard of the Fallen Star divide their rolled base damage among the
recipients of effect zero. Previously each recipient took the full amount.
The spell loader compiles the VMangos `spell_meteor` label into this rule;
normal and triggered casts retain per-effect recipient counts in their
immutable delivery context. Different effect target sets remain independent.

Recipient selection, range, world, life-state, and target caps are resolved
before counting shares. Launch misses retain their share, as do recipients
that are immune to the spell's school. Damage is not redistributed when a
recipient disappears after launch. Each recipient's integer base share then
passes through the existing bonus, critical, resistance, and absorption paths.
Ordinary area spells retain their existing damage behavior.

## Reference

VMangos checkout `8f4e608450460efe1e38743e4da74397d4773a3a`:

- `src/scripts/spells/spell_special.cpp::MeteorScript` counts effect-zero
  recipients without filtering their spell hit result, then divides the
  effect's integer amount.
- `src/game/Spells/Spell.cpp::HandleEffects` calls the script after calculating
  the effect value and before executing school damage.
- `sql/migrations/20250225150702_world.sql` assigns the script to spells 24340,
  26558, 26789, and 28884. The generated supported-build data retains all four.
- Item 21891, Shard of the Fallen Star, invokes spell 26789. Its DBC base range
  is 400–442 fire damage, with an enemy-centered area and a three-minute item
  cooldown.

## Automated validation

Regressions cover one, multiple, and zero recipients; per-effect target sets;
target limits; dead, distant, and foreign-world exclusions; disappearing
recipients; launch misses; school immunity; normal and triggered delivery;
foreign caster ownership; integer rounding; bonus and critical ordering; and
ordinary area damage. DBC and VMangos checks have separate integration tags.

The full run also exposed a condition-context defect: after building a subject
from the player's current owner state, the default source unnecessarily read
that player's published position again. The default now retains the existing
subject directly. Explicit external sources still enrich their metadata. A
controlled regression publishes an older world position and checks that the
owner's current position is used with exactly one zone lookup; it failed before
the fix and passed afterward.

The architecture dependency allowlist was not expanded.

Implementation commits:

- `8751cc04 fix(conditions): retain the current player source snapshot`
- `8310b404 feat(spells): share Meteor damage across effect recipients`

Final implementation validation:

- `mix test.all --seed 2750`: 7,058 passed, using the seed that exposed the
  condition-context defect.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues; both commits also passed their hooks.
- Formatting and whitespace checks passed.

Logs are retained under `/tmp/thistle-meteor-`: `focused.log`,
`condition-before.log`, `condition-after.log`, `verified-all.log`,
`final-compile.log`, `final-credo.log`, `condition-commit.log`, and `commit.log`.

## Native client acceptance

A fresh server at `8310b404` served one isolated build-5875 GPU client.
Debugwarrior (GUID 1) used the existing level and item commands to reach level
60 and obtain item 21891. The item was equipped in the first trinket slot
through the client's inventory API and retained GUID `4611686018427388164`.
Both measured attacks used `UseInventoryItem(13)` and produced the ordinary
`CMSG_USE_ITEM` and cast paths. Setup, selection, inventory actions, and travel
went through the native client; Tidewave only read owner state.

| Case | Native result | Authoritative result |
| --- | --- | --- |
| One recipient | Chat reported 400 fire damage to Skeletal Flayer. | Spawn 990102 changed from 2,880 to 2,480 health. Neighboring flayers stayed at full health outside the five-yard effect radius. |
| Six recipients | Chat reported six hits of 67, 68, 72, 66, 70, and 67 fire damage, and floating damage appeared over the wolves. | All six Prairie Wolf Alphas lost their corresponding shares, totaling 410 damage. All remained alive. |

The first target was GUID `17379390991937510294`, at
`{16248.2, 16343.1, 69.44}` on map 451. The six-wolf group was centered near
`{16153.2, 16298.1, 52.16}`. Selected spawn 991704 was within five yards of all
six recipients before the cast. Their initial and resulting health was:

| Spawn | Initial health | Health after hit | Damage |
| --- | ---: | ---: | ---: |
| 991700 | 176 | 108 | 68 |
| 991701 | 176 | 110 | 66 |
| 991702 | 176 | 109 | 67 |
| 991703 | 198 | 126 | 72 |
| 991704 | 198 | 131 | 67 |
| 991705 | 176 | 106 | 70 |

The player waited for the normal 180,000 ms item cooldown between uses. The
trinket's loaded coefficient was zero, so the warrior's incidental spell power
did not affect these measurements. The six individual base rolls were divided
by six before delivery; they need not sum to the single-target trial's separate
random roll.

Read-only 20 ms samplers captured the first health changes. After the player
left the group, all six wolves reset to full health, returned to their spawn
positions, and left combat. The final player state had full health, no selected
target, and no pending cast. The normal item cooldown remained.

The client WoW process, PID 2273679, used `amdgpu`; its graphics counter
increased from 1,615,405,292 to 12,300,159,225 ns. No server errors or cast
validation failures appeared. Existing account-data and GM-ticket query
warnings remain. The helper-owned client service was stopped and confirmed
inactive with an empty control group; the WoW and retained server PIDs exited.
Ports 4000, 8085, and 3724 were free before the documentation commit.

This native run exercised the item-use path. Other Meteor variants, triggered
delivery, misses, immunity, effect masks, and bonus ordering have automated
coverage. No development seed or command additions were needed.

Retained evidence:

- Client: `/home/pikdum/.cache/thistle-wow-playtest.rkNANY/`
- Accepted screenshots: `screenshots/solo-impact.png` and
  `screenshots/group-impact.png` inside that session.
- Initial and final probes: `/tmp/thistle-meteor-solo-{before,after}.log` and
  `/tmp/thistle-meteor-group-{before,after}.log`.
- Timed health evidence: `/tmp/thistle-meteor-{solo,group}-sample.log`.
- Cooldown and cleanup state: `/tmp/thistle-meteor-cooldown.log` and
  `/tmp/thistle-meteor-final-state.log`.
- GPU evidence: `/tmp/thistle-meteor-gpu-{before,after}.log`.
- Server: `/tmp/thistle-meteor-server.log`.
