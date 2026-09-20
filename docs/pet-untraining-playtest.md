# Hunter pet untraining

Hunter pet trainers now offer the vanilla untraining dialog. Accepting removes
the pet's learned abilities, their passive stat bonuses, spell action buttons,
and autocast selections. Commands and reaction stance remain. Training points
return to `pet level * (loyalty rank - 1)`, and intrinsic family passives remain
available. The hunter retains its Beast Training recipes.

The price starts at 10 silver, increases to 50 silver, then one gold, and then
rises by one gold per reset to a ten-gold cap. A full day since the last reset
returns the price to 10 silver. Reset history belongs to each pet and follows
its retained progression through dismissal, stabling, and logout. Like the rest
of the runtime stores, it is cleared on server restart.

## Implementation and references

`Logic.PetUntraining` handles prices and the pure reset transition. The player
boundary validates the trainer and captures a confirmation for the active pet
GUID. Completion rechecks that identity and available money, commits through
the owning pet process, updates the owner's retained progress and coinage, and
projects the new spellbook. Repeated or stale confirmations cannot reset a
replacement pet or charge twice. An in-flight pet cast is canceled, and the AI
spell selection is reset when its abilities are removed.

The reference behavior comes from `WorldSession::HandlePetUnlearnOpcode`,
`Pet::GetResetTalentsCost`, `Pet::LearnPetPassives`, and gossip option 17 in
`refs/vmangos/`. Packet layouts follow `cmsg_pet_unlearn.wowm` and
`smsg_pet_unlearn_confirm.wowm` under `refs/wow_messages/`.

This also fixes missing intrinsic hunter-pet family passives. The startup
catalogue selects passive spells with acquisition method 2 from both family
skill lines. The converter calls the secondary skill column `pet_talent_type`;
the schema exposes it as `secondary_skill`. Family passives are cached, restored
at spawn and after reset, and excluded from the retained list of purchased
abilities. Wolves now receive their built-in five-percent armor bonus. Aura
157 remains unused, matching the reference core.

Belia Thundergranite is available beside the debug spawn on Programmer Isle.

## Real-client acceptance

An isolated build-5875 client controlled Debughunter against a fresh server.
Actions used the normal trainer dialog, Beast Training, Dismiss Pet, Call Pet,
and stable UI. Existing debug commands supplied happiness and a loyalty
promotion. Tidewave probes only inspected state.

- The level-49 wolf started with nine family passives, 202 stamina, 2,138 maximum
  health, and 3,111 armor. Great Stamina rank one spent five of its 49 earned
  points, yielding 205 stamina and 2,168 maximum health. Growl autocast was
  enabled before the reset.
- Belia displayed the untraining gossip option and a 10-silver confirmation.
  Cancel left the money, spells, stats, and 44-point balance unchanged.
- Accept charged exactly 1,000 copper. The client showed 49 training points and
  empty spell action slots. Stamina and maximum health returned to 202 and
  2,138; armor remained 3,111. Authoritative state contained exactly the nine
  family spells and auras, with no learned abilities or autocast entries.
- The next dialog quoted 50 silver. Accept charged another 5,000 copper without
  duplicating the point refund. The following price was one gold.
- Dismissal stopped pet GUID 17383894611314868245 and removed its world position
  and metadata. Call Pet restored the same pet number, 4194325, under GUID
  17383894611314868288. It retained 49 points, only family abilities, the same
  stats, and the one-gold quote.
- Buying a stable slot charged its separate five-silver fee. Stabling removed
  the recalled pet process and projections while retaining the reset history
  and empty learned-spell list. Retrieval under GUID 17383894611314868312
  restored the same family passives, stats, points, and next price.
- Logout removed that pet process, position, and metadata. Reconnect restored
  pet number 4194325 under GUID 17383894611314868343, with 49 points, no learned
  abilities, and the same reset history. Buying Great Stamina again succeeded,
  leaving 44 points, 205 stamina, and 2,168 maximum health without changing the
  one-gold next reset price.

Automated tests additionally cover the daily reset boundary, escalating price
cap, insufficient money, foreign owners, possession, broken bonds, stale and
replayed confirmations, corpse resets without resurrection, preservation of
unrelated buffs, cast interruption, action slots, packet dispatch, DBC family
data, and restored pet progression.

Evidence is retained in `/tmp/thistle-pet-untraining-*.txt`,
`/tmp/thistle-pet-untraining-server.log`, and
`/home/pikdum/.cache/thistle-wow-playtest.f9hGb6/screenshots/`.

The server emitted no error-level logs or untraining failures. Startup warnings
were limited to existing unimplemented account-data, raid-info, ticket, time,
and meeting-stone messages. The helper-owned client and server were stopped,
with evidence retained.

## Validation

- `mix test.all`: 3,663 passed, including DBC, VMangos, and map integration.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- `git diff --check`: passed.
- Logs: `/tmp/thistle-pet-untraining-{full,compile,credo}.log`.
