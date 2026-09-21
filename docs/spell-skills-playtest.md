# Spell-granted skill ranks

Learning a profession spell now grants its DBC skill rank through the shared
spell-learning boundary. Previously, trainer purchases supplied that rank
separately, while ordinary spell learning could open a profession window at
0/0. The focus acceptance run exposed this with Mining and Cooking.

Effect 118 supplies the skill ID and rank. The pure `SpellSkills` transition
derives its cap, preserves earned points and stable skill-panel slots when
upgrading, and initializes Riding 762 at its trained value. The startup skill
catalog uses the same transition for initial character skills. The effect is
metadata for learning; casting a gathering or fishing spell does not retrain
the skill.

The shared learning boundary also grants eligible automatic skill spells and
starting recipes, applies passives, stores the resulting character, and sends
learning notifications. Recursive rewards are bounded by the set of attempted
spell IDs. Trainer purchases retain their admission checks and their existing
teaching-spell skill data, while using this shared reward path.

Removing the final granting spell removes its skill and associated known
recipes. Lost profession progress is not kept in the forgotten-weapon-skill
cache. Native profession abandonment continues through its existing inventory,
quest, casting, and spell-removal transition. Relearning starts at the initial
value. Removing a higher rank while a lower granting rank remains follows
VMangos's lower-rank value and cap rule.

This change implements learned-spell effect 118. Cast-time effect 44
(`SKILL_STEP`) is covered by the subsequent
[teaching spells and recipe books implementation](spell-teaching-playtest.md).

References:

- `refs/vmangos/src/game/Spells/SpellMgr.cpp`: `LoadSpellLearnSkills`.
- `refs/vmangos/src/game/Objects/Player.cpp`: `UpdateSpellTrainedSkills`,
  `UpdateSkillTrainedSpells`, and `SetSkill`.
- `refs/vmangos/src/game/Spells/SpellEffects.cpp`: `EffectSkill` and
  `EffectLearnSkill` distinguish learned metadata from teaching casts.

## Automated validation

- `mix test.all`: **4,412 passed**.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Commit formatting and lint hooks: passed.

Regressions cover direct Mining learning and starting recipes, secondary
professions, Riding values, progress and slot preservation across ranks,
invalid grants, remaining lower ranks, removal and clean relearning, and
agreement between startup catalog data and loaded DBC spell effects. Existing
trainer, primary-profession limit, abandonment, language, and weapon-skill
tests also pass.

Implementation: `ba046ae2`.
Logs: `/tmp/thistle-skill-{all,compile,credo,commit}.log`.

## Native client acceptance

Used an isolated build-5875 client with level-50 Human Debugwarlock, GUID 6,
with god mode off. Existing `.learn` commands taught Mining 2575 and Cooking
2550; menu spells and recipes were not separately granted. Development
commands supplied five Copper Ore and positioned the character beside the
Goldshire forge at approximately `{-9460, 90, 58.32}` on map 0. Tidewave probes
were read-only.

| Scenario | Native and authoritative result |
| --- | --- |
| Learn Mining | Native profession window showed 1/75. Find Minerals, Smelting, and Smelt Copper were learned automatically. The owner and CharacterStore agreed; one primary profession slot remained. |
| Smelt Copper | Clicked the native Create button. Ore decreased from five to four, one Copper Bar appeared, and Mining increased to 2/75 in the window, owner, and stored character. |
| Learn Journeyman Mining 2576 | The native window showed 2/150. The existing two points and skill slot 10 were retained, and the previous rank was superseded. |
| Logout and reconnect | The profession window still showed 2/150, with four ore, one bar, and the same recipes. |
| Native abandonment | Selected Mining in the Skills panel, clicked its unlearn control, and confirmed the native dialog. Mining disappeared, its known rank, tracking, menu spell, and recipe were removed, and two profession slots were available. Cooking stayed at 1/75 in slot 11. Inventory was unchanged. |
| Relearn Mining | The native window returned at 1/75 with its starting recipe, using slot 10 again. The old points and Journeyman cap were not restored; the forgotten-skills cache remained empty. |

Trainer purchases and Riding were covered by automated tests, not this native
run. No owner crashes, spell failures, or unsupported skill messages occurred.
Existing unimplemented account-data, raid-info, GM-ticket, and meeting-stone
notifications remain.

## Retained evidence

- Server log: `/tmp/thistle-skill-server.log`.
- Owner and CharacterStore snapshots:
  `/tmp/thistle-skill-{learned,crafted,upgraded,reconnected,abandoned,relearned}.txt`.
- Screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.NVWz1C/screenshots/`, including
  `skill-learned.png`, `skill-crafted.png`, `skill-upgraded.png`,
  `skill-reconnected.png`, `skill-panel.png`, `skill-abandon-confirm.png`,
  `skill-abandoned.png`, and `skill-relearned.png`.

The helper-owned client and display and the retained server were stopped.
Changes were committed locally; nothing was pushed.
