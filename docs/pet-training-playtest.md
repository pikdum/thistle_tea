# Hunter pet ability training

Hunters can spend their pet's earned training points through the vanilla Beast
Training window. The shared path handles pet-targeted Learn Spell effects and
Learn Pet Spell effects. It requires an active, living hunter pet owned by the
caster, a compatible family, the required pet level, and enough training points.
A pet can know four active ability families and additional passive abilities.
Known or lower ranks cannot be bought again. Upgrades charge the difference
between cumulative rank costs; zero-cost abilities remain available in training
debt, matching the reference core.

`Logic.PetTraining` owns the pure validation and purchase transition. The player
boundary checks the active pet before casting, then a typed `LearnPetSpell`
effect returns to the player owner through `EventSink.Context`. The pet process
revalidates and commits the purchase atomically. Progress uses the existing
ordered `PetProgressChanged` notifications, so an older queued loyalty snapshot
cannot become the final retained spellbook. Stale requests cannot train a
replacement pet, and a pet dying before completion cannot spend points.

Active upgrades replace the old rank in combat actions, autocast, and current
action-bar slots. Passive upgrades remove the old aura and apply the new one
through the shared aura lifecycle. Learned passives stay in `PetProgress.spells`
and are reapplied when the pet is restored. The client packet now carries the
complete known spellbook, with passive flags, independently of the four active
action buttons. Runtime retention follows the rest of the server and resets on
server restart.

## Reference data

Rules follow `Pet::CanLearnPetSpell`, `CanTakeMoreActiveSpells`, `GetTPForSpell`,
and `Spell::EffectLearnPetSpell` in `refs/vmangos/`. Packet layout follows
`refs/wow_messages/wow_message_parser/wowm/world/pet/smsg_pet_spells.wowm`.

The startup catalogue translates the vanilla DBC's family skills and cumulative
costs into 236 pet abilities. The converter calls the training-cost column
`num_skills_up`; the Ecto schema now names it `training_points`. The local VMangos
spell-chain table omits these pet ranks, so the catalogue follows DBC
`SkillLineAbility.superseded_by` links. These canonical chains also recognize
previously retained spellbooks without chain metadata. Training reads cached
data and does not query Mangos during a purchase.

Debughunter now knows Beast Training and example stamina, armor, resistance,
Dash, and Claw training spells. Existing commands provide repeatable setup:

```text
.debug pet
.debug pet happiness 900000
.debug pet loyalty 5000
/cast Beast Training
```

The loyalty adjustment promotes a fresh rank-one pet and awards its level in
training points through the normal transition. The feature consumes training
spells already known by the hunter; learning new training recipes from wild-pet
ability use and pet untraining are separate systems.

## Real-client acceptance

An isolated build-5875 client controlled Debughunter on Programmer Isle against
a fresh server. Purchases used the Beast Training window's Train button or its
normal `SelectCraft`/`DoCraft` APIs. Runtime probes only read owner state.

- The initial level-49 wolf had zero training points, 202 stamina, 2,138 maximum
  health, and 2,963 armor. An Arcane Resistance purchase reached the server and
  failed with `training_points`, preserving its balance.
- A loyalty promotion awarded 49 points. Dash rank one cost 15, leaving 34.
  After enabling autocast, rank two cost another five, leaving 29. Spell 23109
  replaced 23099 in the spellbook and the same action slot, retained autocast,
  and actually applied its Dash aura. The client displays cumulative recipe
  costs; the server charges the upgrade difference.
- Great Stamina ranks one and two cost ten points total. Only rank two's aura
  remained, yielding 207 stamina and 2,188 maximum health. Arcane Resistance,
  Fire Resistance, and Natural Armor rank one then left eight points, 30 arcane
  and fire resistance, and 3,013 armor. Both the pet panel and authoritative
  state agreed. The pet spellbook visibly listed all eight abilities: four
  active and four passive.
- Claw was rejected by the client's family restriction. Cower reached the
  server and failed with `too_many_skills`; Dash rank three reached the server
  and failed with `lowlevel`. The client displayed the corresponding errors,
  and the balance remained eight.
- Dismiss Pet stopped GUID 17383894611314868238 and retained all eight spells,
  eight points, passive stance, and Dash autocast. Call Pet restored them under
  GUID 17383894611314868246, including exactly one copy of each trained passive
  and the same derived stats.
- Logout stopped the recalled process and retained the complete spellbook,
  training balance, reaction stance, and autocast in `CharacterStore`. Reconnect
  restored these values under another new GUID, with the same displayed stats
  and no surviving previous pet process.

Automated coverage additionally checks free training in debt, duplicate and
lower ranks, unknown abilities, server-side family checks, dead and broken pets,
foreign owners, stale requests, ordered progress delivery, suspension snapshots,
passive rank replacement and restoration, action slots, and the complete packet
payload. Pet death during training is covered automatically rather than by this
client run.

Evidence is retained in `/tmp/thistle-training-server.log`,
`/tmp/thistle-training-{before,dash-first,stamina,complete,dismissed,recalled,logged-out,reconnected}.txt`,
and `/home/pikdum/.cache/thistle-wow-playtest.ZQCzWJ/screenshots/`.

The live server emitted no error-level logs. The helper-owned client and server
were stopped before final validation.

## Final validation

- `mix test.all`: 3,615 passed, including DBC, VMangos, and map integration.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- `git diff --check`: passed.
- Logs: `/tmp/thistle-training-final-{tests,compile,credo}.log`.
