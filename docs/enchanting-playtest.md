# Permanent equipment enchanting

Permanent enchants now complete against the selected owned item. Admission checks
ownership, item class, subclass, inventory type, minimum item level, reagents,
and required tools. Completion checks the current inventory again and commits
reagents, consumable enchant items, the enchant, and Enchanting progress through
one inventory change set. Interrupted casts leave materials and equipment intact.

The permanent slot coexists with temporary weapon enchants. Equip-spell effects
are passive aura sources identified by item GUID, enchant slot, and spell ID.
Two items with the same enchant stack independently. Replacement, unequipping,
item destruction, temporary expiry, login, and death use the shared equipment
and aura transitions. Direct armor, resistance, stat, and weapon-damage effects
feed the equipment stat inputs; weapon damage belongs to its equipment hand.

Weapon procs inspect the striking hand's permanent and temporary enchants. They
use VMangos PPM overrides, the enchant chance, or the default one PPM. Beneficial
procs target the wielder. Feral attacks and disarmed main-hand attacks do not
trigger stored weapon enchants. Enchanting an owned item is supported; trade-slot
enchanting remains outside this implementation.

References: `Spell::EffectEnchantItemPerm`, `Spell::CheckItems`,
`Player::ApplyEnchantment`, `Player::CastItemCombatSpell`, and
`Player::UpdateCraftSkill` in `refs/vmangos/src/game/`.

## Related fixes

Visible equipment values pack item and enchant IDs together. Weapon stat,
weapon skill, cast requirement, ammunition, and character-selection lookups now
extract the item ID before looking up its template.

The real client exposed missing skill modifier fields: Minor Deflect affected
server Defense but displayed `250 + 0`. Skill aura transitions now project
separate signed temporary and permanent skill bonuses without changing learned
skill progress.

Debug creature spawns now snap their individual positions to the terrain. The
Devilsaur fixture previously inherited the playground's shared height and
floated roughly 17 yards above its local ground, preventing melee acceptance.

## Initial client acceptance

An isolated build-5875 client used level-50 Debugdruid, GUID 9, on a fresh local
server. Gameplay actions went through the client. Tidewave probes read state.

- Trained Apprentice Enchanting through Betty Quin's gossip and trainer UI.
  The client received the starter recipes and skill 1/75.
- Added a Runed Copper Rod and ten Strange Dust. Used the Enchanting crafting
  window to apply Minor Health to the equipped bracers. The cast bar appeared;
  maximum health rose from 1,818 to 1,823, dust fell to nine, and skill rose to 2.
- Learned the chest recipe with `.learn 7420`. Interrupted its cast by moving.
  The client displayed "Interrupted". The chest stayed unenchanted, dust stayed
  at nine, skill stayed at 2, and the cast cleared.
- Retried successfully. The two separate Minor Health sources produced 1,828
  maximum health, eight dust, and skill 3.
- Unequipped the bracers through the inventory UI. Only the chest enchant source
  remained. Maximum health fell to 1,783, including loss of the bracers' own
  stats. Re-equipping restored both enchant sources and 1,828 maximum health.
- Replaced bracer Minor Health with Minor Deflect through the client's explicit
  replacement dialog. Maximum health returned to 1,823, authoritative Defense
  became 251, skill rose to 4, and dust fell to seven. The stale client Defense
  display prompted the projection fix above.

Initial artifacts: `/home/pikdum/.cache/thistle-wow-playtest.AF7iVq/`,
`/tmp/thistle-enchant-server.log`, and `/tmp/thistle-enchant-*.txt`.

## Client acceptance after the skill projection fix

A fresh server and client repeated Apprentice training and Minor Deflect. The
client displayed `Defense: 250 + 1`; server Defense was 251, with the separate
skill modifier `{1, 0}` and Enchanting skill 2/75. Logout removed the player
owner while the character store retained the enchant source and skill modifier.
After login the client still displayed `After reconnect: 250 + 1`.

The crafting window successfully applied Crusader to Barman Shanker after
learning recipe 20034 and adding its rod and materials. Enchantment 1900 was
stored on the weapon. Its 2,000 ms speed and 70.43–114.43 displayed damage
remained unchanged before any proc.

Artifacts: `/home/pikdum/.cache/thistle-wow-playtest.D07zEl/`, including
`defense-fixed.png`, `reconnected.png`, and `crusader-cast.png`, plus
`/tmp/thistle-enchant-acceptance-server.log` and the final Defense, logout, and
Crusader state probes in `/tmp/thistle-enchant-*.txt`.

## Live weapon proc and expiry

After the terrain fix, a fresh server placed the Devilsaur at
`{16233.2, 16293.1, 52.17549}`. The earlier shared height was `69.44`.
Debugdruid trained Enchanting again and applied Crusader through the crafting
window. All four Large Brilliant Shards and both Righteous Orbs were consumed;
Enchanting advanced from 1 to 2. God mode was enabled only after crafting to
keep the level-50 character alive against the level-55 elite.

Ordinary client melee triggered Holy Strength (20007) on the wielder. Its buff
icon appeared, the authoritative caster was GUID 9, and its lifetime was
15 seconds. Strength rose from 78 to 178 and damage from 70.43–114.43 to
99–143. After moving away and waiting for expiry, the aura was absent,
Strength returned to 78, damage returned to 70.43–114.43, and permanent
enchantment 1900 remained on the weapon.

Artifacts: `/home/pikdum/.cache/thistle-wow-playtest.5kIpQT/`, including
`holy-strength.png` and `holy-strength-expired.png`,
`/tmp/thistle-enchant-crusader-server.log`, and
`/tmp/thistle-enchant-crusader-{costs,proc,expired}.txt`.
The final gameplay server log contained no error-level entries. A separate
ambient script reported unsupported command 79 at debug level. Acceptance
used one client; no separate observer client was exercised. All test clients
and local servers were stopped after capture.

## Automated validation

- `mix test.all`: 3,380 tests passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.

Coverage includes exact target checks, tool and item restrictions, missing-material
rollback, cast cancellation, skill thresholds and caps, permanent/temporary slot
coexistence, independent passive sources, replacement, removal, death,
reconnection restoration, signed skill fields, weapon hand isolation, feral
exclusion, beneficial proc targeting, and proc probabilities.

Final check logs: `/tmp/thistle-enchant-final-{tests,compile,credo}.log`.
