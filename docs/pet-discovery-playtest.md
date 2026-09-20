# Hunter pet ability discovery

Hunters can discover Beast Training recipes by using abilities from tamed
beasts. The startup catalogue preserves each beast's exact creation spells,
preferring creature spell data over the VMangos fallback. It unwraps teaching
spells, maps usable abilities back to recipes, and charges the initial training
cost. A newly tamed beast no longer receives owner-level ranks or free Growl.
The prepared debug wolf retains its explicitly seeded abilities.

Successful launches of innate active abilities request discovery through typed
effects. The resolver uses the VMangos roll: ten winning outcomes out of 101.
Both commanded casts and autocasts share this launch path. Canceled casts,
passive application, dead pets, demons, and possession do not request discovery.
Innate passive recipes are learned on hunter-pet attachment.

The player owner accepts discovery only from its current pet and learns the
recipe through the shared player spellbook boundary, including the learned-spell
packet and CharacterStore update. Already-known recipes produce no duplicate
learned-spell packet. Eligibility comes from the cached beast profile and survives
dismissal, stabling, and reconnecting; learned recipes belong to the hunter and
remain available for other eligible pets.

Reference behavior: `Pet::InitPetCreateSpells` and `Pet::CheckLearning` in
`refs/vmangos/src/game/Objects/Pet.cpp`, creation-spell loading in `ObjectMgr.cpp`,
and the manual/autocast paths in `Handlers/PetHandler.cpp` and `AI/PetAI.cpp`.

The client check also exposed two shared buff bugs. Beneficial melee-class
spells now skip melee avoidance, following `SpellCaster::SpellHitResult`.
Party-area targeting includes nearby party-owned pets, including a casting pet,
while excluding unrelated or dead pets. This lets Furious Howl affect both
the hunter and wolf. The target selection follows `Spell::FillRaidOrPartyTargets`.

Discovery reads one beast profile per lookup and skips already-known recipes
before calling the spell-loading boundary.

## Acceptance setup

Use Debughunter on Programmer Isle. The seed includes Jenova Stoneshield, a
Prairie Wolf Alpha with Bite rank 2 and Furious Howl rank 1, and a Mottled Worg
without innate abilities. Buy both stable slots and store the prepared debug
wolf. Tame the Worg, raise its loyalty once with `.debug pet loyalty 40000`,
and stable it. Tame the Prairie Wolf Alpha and use Furious Howl until the hunter
discovers its recipe. Swap back to the Worg and teach it through Beast Training.
Alternatively, discover the recipe first, stable the wolf, then tame the Worg.

The Prairie Wolf Alpha starts with abilities 17255 and 24604 and a training
balance of -14. Its corresponding recipes are 17262 and 24609. The Worg needs
level 10 and ten available training points for Furious Howl rank 1. Happiness
can be supplied with `.debug pet happiness 900000`; recipe discovery must use
ordinary client casts and the normal random roll.

## Verified in the build-5875 client

The final run used a fresh server and isolated client after the buff fixes.

- The level-10 Prairie Wolf Alpha retained Bite rank 2, Furious Howl rank 1,
  and -14 training points after taming.
- Repeated ordinary client casts learned recipe 24609. The client displayed
  `You have learned a new spell: Furious Howl (Rank 1).` The live hunter and
  CharacterStore both contained the recipe.
- Furious Howl applied to both the wolf and hunter. A runtime sample found the
  aura on both and an 11-point damage bonus on each, matching the rank's
  randomized 9–11 bonus.
- The wolf was stabled. A newly tamed level-12 Mottled Worg had no abilities.
  Raising loyalty once supplied 12 training points. Beast Training displayed
  the discovered recipe, required pet level 10, and charged exactly ten points.
- The Worg learned ability 24604, retained two points, and cast the buff on
  itself and its hunter through the client.
- Dismissal removed the old pet process, metadata, and spatial entry. Both
  original wild creatures were also absent from those surfaces after taming.
  Recall restored the Worg's ability and two-point balance.
- Logout retained the recipe and suspended pet progress. Reconnect restored
  the trained Worg with a new runtime GUID and the same ability and balance;
  another client cast applied Furious Howl successfully.
- No gameplay errors, pet-protocol stubs, or unsupported aura warnings appeared.
  The ordinary account-data, raid-info, ticket, query-time, and meeting-stone
  startup stubs remained outside this feature.

`GetCraftInfo` exposes the discovered recipe. For scripted UI inspection,
`CraftFrame_SetSelection(index); CraftFrame_Update()` refreshes the description;
`DoCraft(index)` performs the actual training. `SelectCraft(index)` alone does
not refresh the FrameXML presentation.

Artifacts: `/tmp/thistle-pet-learning-final-*.txt`,
`/tmp/thistle-pet-learning-final-server.log`, and screenshots under
`/home/pikdum/.cache/thistle-wow-playtest.EcFax3/screenshots/`.
The client and server were stopped after acceptance.

Final gates: `mix test.all` passed all 3,647 tests,
`mix compile --warnings-as-errors` passed, and `mix credo --strict` reported zero
issues. Regression coverage includes discovery roll boundaries, canceled casts,
stale pet messages, immediate passive discovery, exact starting ranks and costs,
friendly melee-class buffs, and party pet eligibility.
