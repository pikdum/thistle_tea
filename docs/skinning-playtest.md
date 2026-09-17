# Skinning and corpse harvesting

Skinning now follows the profession spell's cast lifecycle. Eligible creatures
become skinnable after their ordinary loot is exhausted. Admission checks the
creature, corpse state, trained Skinning skill, and a Skinning Knife (including
the two vanilla weapon alternatives). The player and corpse boundaries recheck
eligibility at completion, including interaction distance. Failed attempts leave
the corpse available; a successful attempt claims it once and rolls its cached
skinning table into a private loot session.

Skin loot uses the existing inventory reservations, including rollback and
reopening, and the vanilla client loot type 2. It is not distributed through
group rolls. Success can grant one skill point, using the base profession value,
trained cap, difficulty colors, elite multiplier, and the default 75-point
skinning chance steps. Skill bonuses affect admission. The knife is not consumed.

VMangos references: `Spell::CheckCast` in `Spells/Spell.cpp`,
`Spell::EffectSkinning` in `Spells/SpellEffects.cpp`, and `Player::SendLoot` and
`Player::UpdateGatherSkill` in `Objects/Player.cpp`. Local DBC coverage checks all
four profession ranks. The server preloads skinning tables and their items;
there are no skinning-table database queries during a cast.

The debug seed includes a Stonetusk Boar on Programmer Isle at
`16318.2 16308.1 69.44`, with a three-minute respawn. Existing trainer, item, and
teleport commands suffice for testing; no runtime state mutation was needed.

## Real-client acceptance

An isolated build-5875 client ran Debugmage, GUID 5. The player trained Apprentice
Skinning through Maris Granger's actual gossip and trainer UI in Stormwind,
receiving spell 8613 and skill 393 at 1/75. The client enforced the missing knife
requirement. A knife was then supplied with `.additem 7005`.

- Fire Blast killed the debug boar. Skinning before ordinary looting displayed
  "Creature must be looted first" and logged `target_not_looted`.
- Taking the ordinary items cleared the body session and projected unit flag
  `0x04000000`; the client tooltip displayed "Skinnable".
- Failed attempts displayed "Failed attempt", retained the corpse and skinnable
  flag, and left the skill at 1. Several consecutive failures occurred. A narrow
  runtime call trace on the eventual success recorded level 5, skill 1, and roll
  15; tracing was disabled immediately afterward.
- The successful three-second cast opened Ruined Leather Scraps (item 2934).
  The client reported Skinning increasing to 2. Owner state confirmed skill
  2/75, `skinned?: true`, cleared skinnable flag, and a session owned by GUID 5
  with no group ownership. The knife count remained one.
- Closing and reopening the window retained the same leather. Taking it placed
  one scrap in inventory and exhausted the session. A new Skinning request
  displayed "Creature is not skinnable" and granted no additional skill or loot.
- The next respawn restored 102 health with no claimed skin or skinnable flag.
  After another kill, moving during Skinning displayed "Interrupted" and sent
  `CMSG_CANCEL_CAST`. Sampling showed preparation followed by no active cast,
  with the corpse still skinnable and the skill unchanged at 2.
- Retrying after the interruption yielded Light Leather (item 2318) and raised
  the skill to 3/75. No gameplay owner or packet errors appeared in the server
  log. The client and server were stopped before final validation.

Automated tests additionally cover alternate tools, skill bonuses and thresholds,
training caps, gray corpses, elite skill chances, wrong target types, distance,
empty skin tables, competing claim attempts, private loot permissions, pending
body reservations, and the one-shot cast effect.

## Corpse timer regression

The live test exposed reused corpse decay tokens: respawn reset the counter,
so a delayed timer from an earlier life could remove a later corpse. The second
boar corpse disappeared with health zero, `corpse_removed?: true`, and token 1.

Decay tokens are now unique references. A regression test delivers an earlier
life's token to a new corpse and verifies no state change. After recompilation,
the third live corpse had a reference token and remained present at approximately
150 seconds into its life, beyond the old timer's deadline. The normal respawn
period remained 180 seconds.

## Validation

- `mix test.all`: 3,098 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Final logs: `/tmp/thistle-skinning-final-{tests,compile,credo}.log`.

## Evidence

- Screenshots: `/home/pikdum/.cache/thistle-wow-playtest.cDqK0q/screenshots/`,
  especially `trainer-list.png`, `skin-before-loot.png`,
  `fresh-skin-result.png`, `traced-attempt.png`, `reopened-skin.png`, and
  `consumed-skin.png`.
- Interruption: `movement-cancel.png` and
  `/tmp/thistle-skinning-movement-cancel.txt`; successful recovery:
  `after-interruption.png` and `/tmp/thistle-skinning-after-interruption.txt`.
- Runtime records: `/tmp/thistle-skinning-{claimed,consumed,success2,success3,success5}.txt`.
- Server log: `/tmp/thistle-skinning-server.log`.
