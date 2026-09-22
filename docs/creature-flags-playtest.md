# Creature combat defaults acceptance

Implemented in `9c0f50b4`, with the native-discovered instant-kill polarity correction in `8021acd1` and follow-up validation for any-unit spell targets in `1d9a7518`.

Creature templates now retain their static flags as runtime configuration. The shared systems honor player/NPC immunity, unselectability, swimming animation, one-health invincibility, zero defense skill, and guaranteed magic hit rolls for creatures with no spell defense. The last rule bypasses the caster's miss roll; it does not bypass target-side immunity, reflection, or partial damage resistance.

Sessile creatures default to no combat movement and reject root, fear, confusion, distract, pull, and knockback effects. The no-melee flag controls automatic attacks. Scripts and main-ranged spell behavior can override the combat defaults; combat cleanup and respawn restore them. Sessile evasion completes home cleanup without moving the creature. Disabled melee no longer schedules an immediately due attack on every tick.

Invincibility uses the existing damage floor for direct and periodic damage. Scripts can change or disable that floor, and explicit scripted death remains available. Respawn restores a disabled unkillable floor to one health, preserves a positive scripted floor on an unkillable creature, and clears a scripted floor on ordinary creatures.

References at VMangos revision `8f4e60845`:

- `Objects/CreatureDefines.h`: static flag values.
- `Objects/Creature.cpp`: `ToggleUnitFlagsFromStaticFlags`, `SetDefaultValuesFromStaticFlags`, sessile spell immunities, and respawn defaults.
- `Objects/SpellCaster.cpp`: `GetDefenseSkillValue` and `MagicSpellHitResult`.
- `AI/CreatureAI.cpp`: melee/movement defaults, combat reset, and main-ranged overrides.
- `Movement/HomeMovementGenerator.cpp`: stationary home completion.
- `Spells/SpellEntry.cpp`: negative external instant kills, positive self kills, and sacrifice exceptions.

## Native acceptance

The initial build-5875 session was `/home/pikdum/.cache/thistle-wow-playtest.5A7ti8`, with `/tmp/thistle-flags-server.log`. Debugwarlock and Debugshaman were level 60. God mode protected the test characters. Existing `.learn` commands supplied diagnostic spells; no live owner state was mutated through Tidewave.

- Theramore Combat Dummy, entry 4952, retained player-immunity unit flag `0x100`, full health, no victim, and disabled melee/combat movement. The native client showed its neutral target frame; the post-attempt owner read showed no health loss or combat entry.
- Balos Jacken, entry 5089, spawn 30445, survived at **1/1604 health**. The Horde character's `dmg6` cast (18390) exercised ordinary direct damage; the sampler retained the 1604 → 1 transition and continued combat with no death. His existing surrender event accepts 1–20% health, so the sub-1% lethal-hit case does not trigger surrender.
- Stockade Archer, entry 6237, spawn 90472, kept its position and victim after fear. Rank-1 Fear (5782) retained only its separate 25% speed modifier: the fear aura and fear movement memory were absent. The fear-only Intimidation spell (7093) displayed **Immune** in the native client and left no aura or fear movement. Its main-ranged spell logic had explicitly re-enabled combat movement, demonstrating that this override does not remove sessile control immunity.

Evidence includes `immune-dummy.png`, `balos-surrender.png`, `archer-fear.png`, and `archer-immune.png` in that session's screenshots. The Balos screenshot filename names the intended scenario; the sampled state establishes that surrender did not occur below the event's minimum percentage. Owner/projection reads are retained in `/tmp/thistle-flags-dummy.txt`, `/tmp/thistle-flags-balos-damage.txt`, `/tmp/thistle-flags-balos-combat.txt`, `/tmp/thistle-flags-archer-before.txt`, `/tmp/thistle-flags-archer-after.txt`, `/tmp/thistle-flags-archer-control.txt`, and `/tmp/thistle-flags-archer-immune.txt`.

Death Touch initially reduced a friendly target's health without entering combat. Inspection found that external instant kills with an any-unit target were missing from `Spell.harmful?/1`. The correction follows VMangos polarity while preserving custom-positive sacrifice and self-kill exceptions.

The second native session was `/home/pikdum/.cache/thistle-wow-playtest.ObYtnh` against `8021acd1`, with server log `/tmp/thistle-flags-final-server.log`. Debugshaman was level 60 with god mode enabled.

| Check | Observed result |
| --- | --- |
| Death Touch against idle Balos | The sampler recorded 1604 health, no combat, and no victim before the cast; 4.916 seconds into sampling it recorded one health, combat, and victim GUID 8. Balos then approached the caster. |
| Further `dmg6` damage against Balos | He remained alive at one health. The client target frame displayed the nearly empty health bar. |
| Intimidation against Stockade Archer | The client displayed Immune again; owner state retained the same position, no aura, and no fear movement memory. |
| Lightning Bolt rank 10 (15208) against Gorishi Egg | Entry 9496, spawn 23709, GUID `17379391121339210909` had `no_spell_defense?: true`, disabled melee/combat movement, and 229 health. The client displayed 473 damage and a cracked egg corpse. The sampler recorded health zero, `alive?: false`, combat cleared, and victim zero. A single native hit verifies the path and projection; deterministic tests establish the miss-roll guarantee. |
| Lightning Bolt attempt against Theramore Combat Dummy | The dummy retained player immunity, 42/42 health, no combat, and no victim. The screenshot captured command entry, not a cast-result error; this case establishes flag projection and unchanged state, while automated tests establish rejection. |

Second-session evidence: `balos-one-health.png`, `archer-immune.png`, `gorishi-lightning-bolt.png`, and `dummy-rejected.png`; `/tmp/thistle-flags-final-balos-before.txt`, `-balos-kill.txt`, `-balos-repeat.txt`, `-archer.txt`, `-egg-before.txt`, `-egg-hit.txt`, and `-dummy.txt` share the `/tmp/thistle-flags-final` prefix.

The subsequent server validation correction was reproduced with failing regressions: an explicit any-unit target could bypass template immunity. The shared faction-independent flag check now receives unit flags and ownership through player metadata snapshots and immutable NPC observations. Tests verify rejection, allowed controls, unchanged resource state, and the cast-result packet. Native evidence above predates this final validation-only correction.

Neither native server log contained errors, crashes, or failed spell validations. The second session did record the existing unsupported command 79 (`leave_creature_group`) in Stormwind script 7981501; creature-group behavior is still a separate parity gap and is not covered by this acceptance.

## Automated coverage

Regressions cover template loading and unit projection; player versus NPC ownership rules; repeated lethal damage and periodic ticks; scripted thresholds and respawn; full and partial effect immunity; no-melee/no-movement defaults, explicit overrides and reset; stationary home cleanup; zero defense in attack resolution; guaranteed magic hit rolls in casts and damage procs; and instant-kill polarity. VMangos-tagged fixtures verify ordinary and Theramore/Undercity combat dummies, Minor Water Guardians, and Field Repair Bot 74A.

Natural corpse decay/respawn and every template flag combination were not exercised in the native client; lifecycle and edge combinations are covered by automated regressions.

Final gates with the isolated clients and servers stopped: `mix test.all` (**4,731 passed**), `mix compile --warnings-as-errors`, and `mix credo --strict` (**zero issues**, 1,843 files).
