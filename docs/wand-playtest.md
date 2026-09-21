# Wand attacks and auto-repeat

Shoot (5019) now uses the equipped wand and repeats at its derived ranged
attack speed. Its damage school comes from the wand's item template, and its
hit and critical chances use ranged weapon combat. Wand damage receives no
attack-power or spell-power contribution; wand criticals add 50% damage.
School immunity, resistance, absorption, and combat-log feedback use the
resolved weapon school. Wand Specialization applies only to eligible weapon
attacks and updates displayed ranged damage without compounding recomputes.

The spell loader recognizes the ranged-slot and auto-repeat attributes for
both Shoot and Auto Shot. The shared lifecycle arms the attack with a minimum
500 ms windup and preserves the last launch's weapon cooldown across toggles.
Moving or casting cancels wand shooting. Bow auto-attacks pause, then receive
a fresh windup when movement or casting ends. Target loss, concealment,
blocked line of sight, range failure, death, and unavailable equipment stop
the repeat. Each owner-side launch revalidates the cast and equipment before
committing inventory costs or projecting a projectile. Wands consume no ammo.

## Implementation and references

- `Logic.AutoRepeat` owns arming, interruption, resumption, launch deadlines,
  and cancellation. The behavior tree consumes immutable perception data.
- `Character.sync_equipment_stats/1` publishes the usable ranged weapon as a
  canonical input. `Logic.WeaponDamage` shares school selection, equipment
  restrictions, and damage multipliers between stats and attack snapshots.
- `Player.Ammunition` retains the existing atomic launch boundary, including
  stale-request rejection and checks after an equipment change.
- Reference sources: `refs/vmangos/src/game/Spells/SpellEntry.h`
  (`IsAutoRepeatRangedSpell`), `Spells/Spell.cpp` (weapon school),
  `Objects/Unit.cpp` (`_UpdateAutoRepeatSpell`, `GetSpellCritChance`), and
  `Objects/SpellCaster.cpp` (`SpellHitResult`, `SpellCriticalDamageBonus`).
  These guided attribute decoding, timing, interruption, and combat rules;
  the implementation keeps Thistle Tea's existing owners and typed effects.

## Native client acceptance

Tested on 2026-09-21 against commit `1aac6ed8` with the real build-5875 client,
isolated Wine prefixes and Xvfb, and a fresh local server. Debughunter and
Debugmage were level 50 on Programmer Isle. God mode kept incoming mob damage
from ending the combat scenarios. All actions used ordinary client packets;
Tidewave probes only read owner state. No source edits, tests, builds, or
commits ran while the server or clients were alive.

| Scenario | Observed result |
| --- | --- |
| Bow regression | One Auto Shot consumed exactly one of 200 arrows and reduced a Skeletal Flayer from 2,880 to 2,778 health. The repeat stopped when the mob entered the dead zone, leaving 199 arrows. |
| Fire wand | Ember Wand (5215) displayed 35–66 damage. A single Shoot request produced repeated Fire hits in the client combat log and authoritative health changes, with launch deadlines about 1,501 ms apart. |
| Movement | A short forward step cleared the armed wand attack. Health remained 1,505 for the rest of the nine-second sample, and no new launch deadline appeared. |
| Another spell | Requesting Frostbolt canceled Shoot through the client. A subsequent Frostbolt request reached the server as spell 10180 and cast normally. Automated coverage also exercises interruption directly through `Casting.start/5`. |
| School swap | Equipping Lesser Magic Wand (11287) changed displayed damage to 12–22 and subsequent client combat feedback to Arcane. Samples included 20, 20, 12, and 12 damage. |
| Wand Specialization | Learning rank 2 (6085, 25%) changed the arcane wand's displayed range to 15–27.5. Subsequent normal hits included 18, 22, 27, 16, and 25. Switching back to Ember Wand displayed 43.75–82.5. |
| Target death | Health reached zero at 4,429 ms in the sample; the repeat was absent at 4,580 ms and stayed absent. |
| Unequip | Moving the equipped wand into an empty backpack slot cleared ranged weapon inputs, displayed 0–0 damage, and stopped further attacks. |
| Inventory and resources | Both wands retained their stack counts and full durability. Ammo remained absent and mana stayed at 3,693 throughout the wand samples; automated tests cover the no-cost path without god mode. |
| Disconnect and reconnect | Closing an actively shooting client removed its entity owner. Reconnecting restored Ember Wand, skill 250, the talent, and displayed 43.75–82.5 damage, with no target, cast, or repeat. Selecting a living target and using Shoot again produced Fire hits of 56, 57, 76, and 82 in the client. |

No error-level server logs or cast-validation failures occurred. Existing
unsupported account-data, raid-info, GM-ticket, and meetingstone requests
appeared during login. All owned clients, Wine/Xvfb processes, and the server
were stopped after acceptance.

## Automated coverage and evidence

`mix test.all`: **4,281 passed**. `mix compile --warnings-as-errors`,
`mix credo --strict`, and `mix format --check-formatted` passed. Tests cover
DBC classification, damage school and scaling, weapon talent isolation,
immunity and resistance feedback, ranged combat outcomes, timing, movement,
casting, dead targets, lost sight, range, caster death, weapon replacement,
broken equipment, duplicate requests, and inventory conservation. The
architecture dependency allowlist is unchanged.

Retained local evidence:

- `/tmp/thistle-wand-server.log`
- `/tmp/thistle-wand-{bow,fire,move,cast,arcane,talent,death,unequip}-sample.log`
- `/tmp/thistle-wand-{test-all,compile,credo}.log`
- `/home/pikdum/.cache/thistle-wow-playtest.4ezdjU/screenshots/`, including
  `fire-wand-combat.png`, `arcane-wand-combat.png`, and `wand-death-stop.png`
- `/home/pikdum/.cache/thistle-wow-playtest.m8HnQe/screenshots/wand-reconnected-live.png`
