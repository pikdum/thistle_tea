# Combat skill progression

Weapon skill now has one snapshot and progression path across main-hand swings,
off-hand swings, queued attacks, and melee and ranged abilities. Temporary and
permanent skill bonuses affect white attacks as well as spell attacks. Natural
weapon forms use level skill; shapeshifted forms cannot train weapons, while
stances, stealth, Shadowform, and Moonkin retain normal weapon progression.
Disarm selects Unarmed for the main hand without changing the off hand.

The defender resolves training eligibility after the attack-table roll and
before damage. Valid hits, misses, avoidance, and resists can train; immune,
reflected, and evaded outcomes cannot. Corpses, players, and player-controlled
pets do not grant progress. The
killing blow remains eligible. A typed `AdvanceCombatSkill` effect returns the
launch-time skill to the attacker owner, so switching weapons before impact
does not award progress to the replacement weapon. Defense uses the same
outcome and ownership checks and refreshes the displayed avoidance fields.

Arcane Shot and other ranged abilities without weapon-damage effects now also
use the ranged attack table. Abilities without a weapon requirement do not
train a weapon. Progress is awarded once per resolved target, independently
of how many spell effects execute. Fishing poles do not train through combat.
The existing level cap, intellect bonus, and skill-gain probabilities remain
in `Logic.Skills`.

Review also found that packed visible-item enchantments were reaching the
main-hand template lookup. Spell snapshots now extract the item entry, keeping
enchanted weapons' normalized attack speeds and weapon-specific talent bonuses.

References used:

- `refs/vmangos/src/game/Objects/Player.cpp`: `UpdateCombatSkills`.
- `refs/vmangos/src/game/Objects/Unit.cpp`: `ProcSkillsAndReactives`.
- `refs/vmangos/src/game/Objects/SpellCaster.cpp`: weapon skill and ranged hit resolution.
- `refs/vmangos/src/game/Spells/Spell.cpp`: melee and ranged proc classification.
- Build-5875 `SpellShapeshiftForm` and `Spell` rows, including the stance and
  natural-weapon flags and Arcane Shot/Serpent Sting's ranged damage class.

## Automated validation

- `mix test.all`: **4,469 passed**.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Formatting and commit hooks: passed.

Coverage includes hand-specific bonuses, disarm, forms, zero effective skill,
weapon swaps, caps, PvP and pet exclusions, valid and invalid outcomes, killing
blows and corpses, actual owner delivery, melee and ranged spell paths, ranged
spell misses, and enchanted one-hand, two-hand, and dagger snapshots.

The new `.debug skill <id> <value>` command changes only an already-known skill
within its trained cap and refreshes defense fields. `.debug skills` still
maximizes known skills and now refreshes those fields too.

Implementation commits:

- `cf59cc26`: shared snapshots and resolved combat progression.
- `1b4bbca9`: enchanted weapon template lookup.
- `5b8f1c86`: ranged spell-damage and debuff attack resolution.

Gate logs: `/tmp/thistle-combat-skills-final-{all,compile,credo}.log`.

## Native build-5875 acceptance

The isolated client used existing debug characters on Programmer Isle. All
staging used native chat, inventory APIs, and the bounded skill command.
Tidewave only read owner and stored state.

The first session ran `1b4bbca9`:

| Scenario | Client and owner result |
| --- | --- |
| Human warrior, main-hand Worn Shortsword and off-hand Worn Dagger | Both base skills began at 1. The attack snapshots were 6 for swords, including the racial +5, and 1 for daggers. |
| Dual-wield attacks against Skeletal Flayers | Swords advanced to base 27, daggers to 31, and defense to 130. The native Skills pane showed Swords 32/255, Daggers 31/250, and Defense 130/250. God mode kept the warrior alive during the prolonged three-mob training test. |
| Logout and re-entry | All three gains, the equipped weapons, and the racial bonus survived a completed logout and login through the registered owner. |
| Hunter Auto Shot | Bows advanced from 1 to 3 and ammunition fell from 200 to 198. Auto Shot stopped when the mobs reached melee range; bow skill stayed at 3 during eight subsequent samples. The hunter took normal damage and died; the client Skills pane and stored character retained Bows 3/250, and repeat state was cleared. |

First session artifacts:

- `/home/pikdum/.cache/thistle-wow-playtest.LhQktx/screenshots/dual-combat.png`
- `/home/pikdum/.cache/thistle-wow-playtest.LhQktx/screenshots/dual-skills-pane.png`
- `/home/pikdum/.cache/thistle-wow-playtest.LhQktx/screenshots/ranged-combat.png`
- `/home/pikdum/.cache/thistle-wow-playtest.LhQktx/screenshots/ranged-skills-pane.png`
- `/tmp/thistle-combat-skills-{dual-samples,dual-final,warrior-reconnect,ranged-samples,ranged-final}.txt`
- `/tmp/thistle-combat-skills-server.log`

A fresh server and second isolated client ran the final `5b8f1c86` code.
Casting Arcane Shot also started the client's Auto Shot: bow skill advanced
from 1 to 3 while ammunition fell from 200 to 198, and a subsequent repeat
raised it to 4 with 197 arrows remaining.

To isolate the spell-damage ability, Bows was reset to 1 and the native client
ran `CastSpellByName("Arcane Shot"); ClearTarget()`. Clearing the target stopped
the automatic follow-up shot. The owner then had Bows **2/250**, ammunition
**196** from 197, no selected target, and no active repeat. The client displayed
the skill increase. The hunter used god mode for this final controlled test.
After a completed logout and re-entry, the native Skills pane still showed
Bows **2/250**. The owner and stored character agreed, ammunition remained at
196, and no automatic shot remained active.

Final session artifacts:

- `/home/pikdum/.cache/thistle-wow-playtest.eXoQjl/screenshots/arcane-skill.png`
- `/home/pikdum/.cache/thistle-wow-playtest.eXoQjl/screenshots/isolated-arcane-skill.png`
- `/home/pikdum/.cache/thistle-wow-playtest.eXoQjl/screenshots/final-skills-pane.png`
- `/tmp/thistle-combat-skills-final-{before,arcane,safe}.txt`
- `/tmp/thistle-combat-skills-isolated-{before,after}.txt`
- `/tmp/thistle-combat-skills-final-server.log`
- `/tmp/thistle-combat-skills-final-reconnect.txt`

Neither server log contained owner, network, or combat-skill errors. Both
helper-owned clients, X servers, and retained game-server processes were stopped.
The character store is in memory: reconnect persistence here means rejoining
the running server, not surviving a server restart.
