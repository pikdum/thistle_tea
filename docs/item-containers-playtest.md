# Inventory containers and lockboxes

Build 5875, September 21, 2026. Implementation commits:

- `1fd91e6d`: retained item loot, atomic claims, and separate instance flags.
- `677d1d4d`: native item opening, owned-item unlocking, and lifecycle integration.
- `e90cda7a`: Lockpicking and Poisons skill initialization from vanilla data.
- `e2088b18`: the client loot response required after unlocking spells.

The final implementation passes all 4,177 tests through `mix test.all`,
compilation with warnings as errors, strict Credo, and formatting. The
architecture dependency allowlist is unchanged. Repository edits, builds,
tests, and commit hooks ran with the playtest server and client stopped.

## Shared behavior

`CMSG_OPEN_ITEM` decodes native bag and slot fields and dispatches to the
container boundary. Direct loot requests for item GUIDs use the same checks.
Opening requires a living owner, an eligible container, an unlocked item,
and current access to its inventory location. Remote bank access and opening
during taxi flight are rejected.

The loader caches `item_loot_template` and its reward templates at startup.
Container generation reads that cache, including reference groups, quest
item eligibility, conditions, and template money ranges. Obsolete rows whose
item templates are missing are skipped without a gameplay database query.

Rolled contents belong to the item instance in `ItemStore`. Closing or
reconnecting retains the exact roll and claim state. Closing does not collect
remaining rewards. Every item or money claim rechecks ownership and access,
then commits the reward and source update through one inventory transaction.
Failed storage preserves the reward. Repeated requests cannot duplicate
items or money. Releasing an exhausted container removes its source item.
These stores retain state within the running server; restart still wipes it.

Generated containers cannot be traded, mailed, auctioned, split, or merged.
Their ordinary inventory movement remains available. Static template flags
are separate from dynamic item flags: the template's lootable bit and the
instance's unlocked bit both use value 4, but have different meanings.

Owned-item Pick Lock and opening-item spells share the cached lock catalog,
cast validation, typed opening effect, completion revalidation, and gathering
rules used by world objects. Unlocking, reagent and charge consumption, and
skill progress commit together. Failed attempts consume no opening item;
successful skill casts can award one point, while item casts award none.
Reopening an unlocked item cannot repeat the gain.

Ordinary item opening sends loot type 1. Spell-based unlocking sends type 2,
matching VMangos's client mapping of `LOOT_SKINNING`. This keeps the native
loot window open after the successful cast.

References: local VMangos `Handlers/SpellHandler.cpp` (`HandleOpenItemOpcode`),
`Spells/Spell.cpp` (`CanOpenLock`), `Spells/SpellEffects.cpp` (`EffectOpenLock`),
`Objects/Player.cpp` (`SendLoot` and `UpdateSkillTrainedSpells`),
`Handlers/LootHandler.cpp`, and the item prototype/dynamic flag definitions.
The packet fields also follow the local `wow_messages` vanilla specification.

## Client acceptance

Debugrogue (GUID 3) and Debugwarrior (GUID 1) used isolated Wine/Xvfb clients
against fresh local servers. Native bag clicks, spell targeting, loot clicks,
trainer dialogs, and logout/login exercised the real network path. Tidewave
read selected owner and store fields without mutating gameplay state.

Existing level, teleport, and item commands prepared fixtures. The rogue's
level increase retained Lockpicking 250 while raising its cap to 300. The
warrior trained Apprentice Blacksmithing through Dane Lindgren, then used
`.debug professions` to meet the key's profession requirement. A debug
`.learn` grant alone does not supply a trained profession rank.

| Transition | Client and authoritative result |
| --- | --- |
| Open a locked Heavy Junkbox | Item remains locked, with no generated loot |
| Pick Lock at the skill threshold | Visible failed attempt leaves the item and skill unchanged; retry unlocks it and advances 250 to 251 |
| Collect only gold, close, logout, and reopen | All four remaining rewards, unlocked flag, coinage, and skill exactly match the pre-logout snapshot |
| Unlock an Ornate Bronze Lockbox with all 16 backpack slots occupied | Fortified Boots remain in the loot window after the visible inventory-full rejection |
| Free one slot and retry the same reward | Boots enter the freed slot; closing removes the exhausted source |
| Open a Dented Crate normally | Two Coarse Blasting Powder are claimable; collecting and releasing removes the crate |
| Use a Silver Skeleton Key on a Heavy Junkbox | Insufficient opening strength is rejected and both keys remain |
| Use the key on an Ornate Bronze Lockbox | Exactly one key is consumed, the source unlocks, and no Lockpicking skill is added |
| Final revision: Pick Lock without an extra opening click | Loot window remains open automatically; 372 copper and three Blinding Powder are collected, the source is deleted, and saved Lockpicking remains 251 |
| Final revision: native key unlock and collection | Loot window opens automatically with Demon Band; one key remains and collecting/releasing removes the source |

The reconnect, full-bag, and ordinary-crate checks ran on `e90cda7a`. The
final fresh run on `e2088b18` repeated rogue unlocking, partial reopening,
collection and source cleanup, native Blacksmithing training, weak-key
rejection, and successful key unlocking and collection.

Final evidence is retained under
`/home/pikdum/.cache/thistle-wow-playtest.57yIga/screenshots`, including
`automatic-unlock-loot.png`, `final-partial-reopen.png`,
`final-exhausted-container.png`, and `final-key-automatic-loot.png`.
Earlier lifecycle evidence is under the `thistle-wow-playtest.FQeBNW`
session. Server logs are `/tmp/thistle-containers-acceptance-server.log`
and `/tmp/thistle-containers-final-server.log`.

Neither acceptance log contains an owner error or unsupported container/loot
opcode. Expected weak-key validation failures are present. Existing startup
account-data, raid-info, ticket, meeting-stone, and unrelated world-script
warnings remain outside this feature. All playtest processes were stopped.

## Bugs found and corrected

Native testing first exposed a rogue that knew Pick Lock but had no
Lockpicking skill. Vanilla's base Lockpicking and Poisons abilities require
a special skill-acquisition rule; the loader now handles those rows while
excluding recipes and other classes. Fixture and DBC tests cover this.

The first unlocking implementation generated and saved loot correctly but
the client immediately closed its window. Sending the vanilla unlocking
loot type fixed both Pick Lock and consumable keys. The final fresh client
run proves the visible result, and packet assertions cover both paths.

Automated tests additionally cover private claims, duplicate requests,
unavailable sources, death, remote bank access, full-bag rollback, atomic
instant-key costs, completion-time revalidation, transfer restrictions,
cached generation, and persistence through the runtime stores.

[Trade-slot unlocking](trade-opening-playtest.md) extends these systems to
another player's retained item. Wrapped gifts remain separate parity work.
