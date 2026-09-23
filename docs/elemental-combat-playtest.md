# Creature elemental combat

Creature construction retains the template's attack school and school-immunity
mask through respawn. Shared spell, aura, periodic-damage, and melee paths
respect that mask, including friendly and self-cast exceptions and the reference
immunity-bypass attributes. The existing aura-immunity bypass does not bypass a
creature's template immunity.

Elemental melee carries its school through the behavior-tree attack snapshot,
outgoing bonuses, incoming flat modifiers, resistance, absorption, and threat.
It bypasses physical armor. Dampen Magic can reduce the base swing by at most
half before the attack outcome and later mitigation. Matching wards absorb
damage after resistance, and depleted or expired wards use normal aura cleanup.
The native melee packet now encodes a school index, rather than an internal
school mask, and reports both resisted and absorbed amounts.

This uses retained entity data and the existing pure combat and aura systems;
gameplay performs no database queries. The architecture dependency allowlist is
unchanged. Local references are VMangos `Creature::IsImmuneToSpell`,
`Creature::IsImmuneToDamage`, `Unit::CalculateMeleeDamage`,
`Unit::MeleeDamageBonusTaken`, and `Packets/Combat.cpp`.

## Loader regression found during acceptance

VMangos uses negative `spell_mod.AuraInterruptFlags` values to retain the DBC
value. The loader previously cached `-1` as real flags, which made Fire Ward
force the caster to sit and exposed the caster to guaranteed melee criticals.
The loader now accepts only nonnegative overrides, matching VMangos
`ModUInt32ValueIfExplicit`. Regression tests cover negative sentinels, explicit
zero, and Cannibalize's real damage-interrupt override. A fresh server loaded
Fire Ward with flags zero and Cannibalize with flags two.

## Automated coverage

Tests cover school retention and respawn, direct and periodic immunity, hostile
auras with both initialized and absent aura lists, friendly effects, bypass
attributes, combined immunity masks, both attack hands, school-specific bonuses,
armor bypass, penetration, resistance before absorption, unrelated wards,
Dampen and Amplify Magic, and exact packet encoding and projection.

Separately tagged integration tests use real VMangos elemental templates and
real DBC Fire Ward, Dampen Magic, and Amplify Magic. Default tests use fixtures.

## Native acceptance

An isolated GPU-rendered build-5875 client used Debugmage against Burning Exile
template 2760, spawn 11719, in Arathi Highlands. The fresh spawn was level 38
with 1,604 health, fire attack school 2, and school-immunity mask 4. Actions used
native input and existing development commands. Tidewave probes only read
owner state. God mode was disabled for damage and mitigation measurements.

| Check | Client and owner evidence |
| --- | --- |
| Fire immunity | Fireball rank 1 displayed Immune and left the creature's health unchanged. |
| School isolation | Frostbolt rank 1 reduced health from 1,604 to 1,581 and applied its slow. The slow subsequently expired. |
| Fire Ward | The ward started at 165 and absorbed swings of 62 and 61 while health remained 1,875. The next swing consumed the remaining 42 and dealt 12 damage. The client displayed both full absorption and the partial-absorb amount. |
| Posture regression | The owner retained standing state zero throughout ward application, absorption, and depletion. Later swings were normal hits, rather than the forced sitting criticals seen before the loader fix. |
| Resistance and school feedback | The client displayed 53 Fire damage with 17 resisted; health decreased by 53. Ordinary swings displayed their fire school too. |
| Dampen Magic | Spell 10173 contributed -60 incoming magic damage. Normal fire swings dealt 27–33 damage, with a separate 26-damage hit reporting 8 resisted. |
| Cancellation | Right-clicking Dampen Magic cleared the aura and its modifier at 12,563 ms in the sampler. Subsequent swings dealt 60, 63, 61, and 54 damage. |
| Combat reset | After the mage returned to Programmer Isle, both owners left combat. The creature returned to 1,604 health with its fire school, immunity mask, and original Fire Shield. The mage retained no cast, ward, or Dampen Magic aura. |

WoW's own AMD DRM graphics counter advanced from 1,596,127,977 to
9,082,187,027 ns in the helper-owned cgroup. The owned client unit and retained
server were stopped. No gameplay errors appeared; the log contains the existing
unsupported login requests for account data, raid information, GM tickets, and
meeting stones.

Local evidence:

- `/home/pikdum/.cache/thistle-wow-playtest.zQqc5O/screenshots/`: fire immunity,
  frost damage, ward absorption and depletion, Dampen Magic and cancellation.
- `/tmp/thistle-elemental-fixed-spell-samples.txt`,
  `/tmp/thistle-elemental-fixed-ward-samples.txt`,
  `/tmp/thistle-elemental-dampen-samples.txt`,
  `/tmp/thistle-elemental-final-state.txt`, and
  `/tmp/thistle-elemental-fixed-server.log`.

Validation: `mix test.all`, `mix compile --warnings-as-errors`,
`mix credo --strict`, `mix format --check-formatted`, and `git diff --check`.
