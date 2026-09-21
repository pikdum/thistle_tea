# Profession training, abandonment, and crafting progress

Build 5875, September 21, 2026. Implementation commits:

- `a9e6efb3`: two-primary-profession limit and cached skill catalog.
- `51feb2ed`: skill abandonment with spell, aura, cast, and quest cleanup.
- `6aa7d60f`: shared live trainer validation for lists and purchases.
- `87cbe13d`: trained skill tiers and superseded-rank purchase protection.
- `2a367b9a`: recipe skill gains after successful item creation.
- `4f9adbc1`: stable client skill slots across learning and abandonment.

The final implementation passes all 4,137 tests through `mix test.all`,
compilation with warnings as errors, strict Credo, and formatting. Repository
edits, builds, tests, and commit hooks ran with the playtest server and client
stopped. The architecture dependency allowlist is unchanged.

## Shared behavior

Available primary-profession slots are derived from known skills. Trainer
offers carry the client's first/second-profession confirmation fields and
disable a third primary profession. Secondary skills and upgrades remain
available. Purchases recheck current skill rank, prerequisites, money, and
profession capacity. Trained tiers remain distinct from debug-raised caps,
and superseding an apprentice spell cannot make its rank purchasable again.

Trainer listing and purchasing share checks for player and trainer state,
trainer eligibility, hostility/reputation, world identity, and interaction
distance. The boundary reads cached templates and published runtime state;
it does not query Mangos during interaction.

The skill loader caches SkillLine, SkillRaceClassInfo, and SkillLineAbility
data at startup. Race/class-specific unlearn flags authorize abandonment.
All associated known ranks, recipes, and abilities are removed, including
their active auras and tracking effects. An associated cast is interrupted
through the existing spellcasting boundary before removal.

Abandonment plans skill loss, related active quests, rewarded quest history,
and quest source-item removal through one inventory transaction. Source
items include bank storage and do not restore quest starters. A failed plan
leaves progress unchanged. Unrelated skills and quests remain intact, and a
newly available profession slot can be reused immediately. Relearning starts
at rank 1 with starter abilities; old ranks and recipes do not return.

Item-creation effects retain their originating spell ID. Successful inventory
creation applies one recipe skill-gain roll using cached difficulty data and
the same pure rule as enchanting. Failed storage, capped or missing skills,
ordinary item grants, and interrupted casts do not award crafting progress.
Skill entries retain fixed client field slots; adding or removing a skill
does not move the other entries.

References: local VMangos `Handlers/SkillHandler.cpp`,
`Handlers/NPCHandler.cpp`, `Objects/Player.cpp` (`SetSkill`,
`UpdateSkillTrainedSpells`, `UpdateCraftSkill`, `TakeOrReplaceQuestStartItems`),
`Spells/SpellMgr.cpp`, and `Spells/SpellEffects.cpp` item creation.

## Client acceptance

Debugwarrior (GUID 1) used four fresh server/client sessions, each with a
private Wine prefix and Xvfb display, with the client restricted to CPU cores
0–3. Native trainer dialogs, confirmation buttons, the skill-panel unlearn
button, crafting controls, and logout/reconnect exercised the actual network
path. Tidewave read selected owner/store fields without mutating gameplay
state.

Teleports positioned the character at trainers and a forge. `.debug skills`
raised already-trained professions to their current caps for the Journeyman
offer. `.additem` supplied crafting/quest materials, and `.addquest` prepared
profession quest cleanup fixtures. In particular, adding quest 2203 bypassed
its normal Alchemy requirement; this tested removal of its source item, not
its eligibility. Rewarding quest 4104 used the native NPC dialog.

| Transition | Client and authoritative result |
| --- | --- |
| Train Mining at Gelman Stonehand | First-profession confirmation; Mining 1/75; Find Minerals, Smelting, and Smelt Copper learned |
| Train Herbalism at Shylamiir | Second-profession confirmation; both primary slots occupied |
| Visit Alchemist Mallory with two primaries | Alchemy Train button disabled; attempted client purchase leaves money and skills unchanged |
| Train Cooking at Stephen Ryback | Secondary profession learned with both primary slots occupied |
| Raise Mining to 75, train Journeyman and Smelt Tin | Mining 75/150 with trained tier 2; spell 2576 supersedes 2575; recipe 3304 learned |
| Activate Find Minerals, accept quests 4104 and 90, abandon Mining | Native confirmation removes Mining ranks/recipes, tracking mask 4 and aura 2580, and quest 4104; Herbalism, Cooking, and quest 90 remain |
| Logout and reconnect after abandonment | Owner and stored character agree on missing Mining, cleared tracking, and retained unrelated progress |
| Train Alchemy using the freed slot | Native second-profession confirmation succeeds |
| Accept quest 2203, abandon Alchemy | Alchemy abilities, quest 2203, and source item 7870 disappear together; unrelated progress remains |
| Retrain Mining | Mining returns at 1/75 with starter abilities; Journeyman and Smelt Tin remain absent |
| Reward quest 4104, later abandon Mining | Rewarded history for 4104 is cleared; active Cooking quest 90 remains |
| Smelt Copper through the trade-skill frame | One ore becomes one bar; Mining advances from 1 to 2, visible in chat and the profession frame and saved in CharacterStore |
| Start another recipe, immediately stop casting | No extra bar, reagent consumption, or skill point; casting is cleared |
| Start a recipe and abandon Mining through the client API | Client displays Interrupted; the cast and profession abilities are removed with no extra product or skill gain |
| Reconnect with Mining 2/75 | Crafting progress and inventory survive owner recreation within the running server |
| Final fresh-session train, craft, native abandon, reconnect | All 15 unrelated skill entries retain their original values and slots; Mining uses slot 15, then clears it; no false Plate Mail skill notification |

The cast-abandon sequence used native `DoTradeSkill` and `AbandonSkill` Lua
APIs to send both actions before the short recipe completed. Separate runs
proved the visible skill-panel confirmation path. The third-profession
forged-packet rejection is covered explicitly by automated tests; the live
UI check establishes the disabled control and unchanged character state.

Automated coverage also includes race/class unlearn restrictions, protected
skills, repeated requests, timed quests, bank source items, nonempty-bag
rollback, unrelated casts, stale trainer interactions, failed/unique-limited
item creation, multiple created items producing only one skill roll, and
client-message dispatch registration. Database-dependent cases use their
required tags.

## Bugs found and corrected

The initial client run had no native unlearn button because skill fields did
not include the trained tier. Encoding the tier restored the button. A
superseded apprentice spell also appeared purchasable; trainer state now
checks the trained tier independently of spellbook membership.

Native Smelt Copper initially produced its item without awarding Mining
progress. The creation effect now carries recipe identity to the successful
inventory commit. A fresh run proved the visible 1-to-2 gain, cancellation
without a gain, and reconnect persistence.

Abandoning Mining then exposed a false Plate Mail skill-up notification:
sorting skills by ID moved remaining client field entries. Stable assigned
slots fixed that projection error. The final fresh run checked every
unrelated skill's ID, slot, value, and maximum against its pre-training
snapshot after training, crafting, abandonment, and reconnect.

No owner, network, profession, inventory, or quest errors appeared in the
accepted server runs. Logged warnings were the existing unsupported
account-data, raid-info, GM-ticket, and meeting-stone requests at login.

Retained local evidence:

- Initial trainer/UI evidence: `/home/pikdum/.cache/thistle-wow-playtest.eBkfN7/screenshots/`.
- Tier, quest, tracking, and abandonment evidence: `/home/pikdum/.cache/thistle-wow-playtest.m9IFmD/screenshots/`.
- Crafting gain/cancellation evidence: `/home/pikdum/.cache/thistle-wow-playtest.M32JMw/screenshots/`.
- Final stable-slot evidence: `/home/pikdum/.cache/thistle-wow-playtest.BpIU0P/screenshots/`, including `stable-crafting-gain.png`, `stable-native-unlearn-confirm.png`, `stable-native-abandoned.png`, and `stable-reconnected.png`.
- Server logs: `/tmp/thistle-profession-server.log` and `/tmp/thistle-profession-server-{2,3,4}.log`.
- Runtime observations: `/tmp/thistle-profession-acceptance.log`; this includes earlier failed diagnostic expectations alongside the corrected passing phases.
- Final slot assertions: `/tmp/thistle-profession-stable-check.exs` and `/tmp/thistle-profession-stable-{trained,crafted,abandoned,reconnected}.log`.
- Final offline assertion: `/tmp/thistle-profession-stable-offline.exs` and matching `.log`.
- Full-suite result: `/tmp/thistle-profession-tests-8.log`.

All helper-owned clients and retained server PTYs were stopped. Reconnect
checks exercised runtime ETS storage, not persistence across a server
restart. Nothing was pushed or deployed.
