# Need Before Greed eligibility and failed awards

Need Before Greed now checks item usability before admitting a player to a
roll. Class, race, level, highest honor rank, required skill and rank, required
spell, and weapon or armor proficiency use the same pure `ItemEligibility`
rules as equipping an item. A required skill must be known even when the
template specifies rank zero. The player owner publishes an eligibility
snapshot through `World.Presence`; corpse logic reads that snapshot and cached
item templates without querying the database or another player process.

Existing loot conditions, party access, and distance checks still apply.
Group Loot does not apply the usability filter. With no eligible participants,
an item remains available through ordinary loot rules. With one participant,
the server awards an automatic Need roll of 100 without a roll prompt or
timer. Multiple participants receive the normal roll window.

A Need winner owns the item before inventory delivery begins. Failed delivery
or a lost reservation leaves the same item and random property on the corpse,
available only to that winner while the loot session exists. This also works
after reconnecting. The existing Greed failure behavior remains unchanged.
Releasing a reservation and resolving a roll publish updated corpse
lootability through the existing recipient projection. This restores the
winner's client interaction after a full-bag failure and exposes items after
everyone passes.

Implementation commits:

- `1a906fee feat(loot): enforce vanilla Need Before Greed eligibility`
- `3a0c2f16 fix(loot): publish restored corpse lootability`

## Reference

VMangos checkout `8f4e608450460efe1e38743e4da74397d4773a3a`:

- `src/game/Group/Group.cpp::StartLootRoll` filters the entire Need Before
  Greed participant set with `CanUseItem`, and handles zero, one, and multiple
  participants separately.
- `CountSingleLooterRoll` awards Need 100 and retains `lootOwner` after an
  inventory failure. The ordinary Need winner path also retains ownership
  when delivery fails or the winner is unavailable.
- `src/game/Objects/Player.cpp::CanUseItem(ItemPrototype const*)` defines the
  usability requirements.
- `src/game/LootMgr.cpp` enforces the stored loot owner.

## Native acceptance

Two isolated build-5875 clients used Debugwarrior (GUID 1) and Debugbidder
(mage, GUID 11) on Programmer Isle. Existing development commands staged
levels, inventory, and proficiency. Kills, roll responses, corpse interactions,
logout, reconnect, and item pickup went through the clients. Tidewave probes
only read authoritative state.

The initial run against `1a906fee` established the following:

| Case | Client behavior and authoritative result |
| --- | --- |
| Group Loot control | Both level-50 players received Chromatic Sword 1604 and Skullcrusher 1608 roll prompts despite the mage lacking their proficiencies. Mage Greed and warrior Need awarded both to the warrior. The mace retained property 1807, `of Arcane Wrath`. |
| No usable recipient | Before learning two-handed swords, neither player could use the sword. It remained unblocked with no owner or roll. |
| One usable recipient | Only the warrior could use the mace. It was awarded automatically with Need 100, without a roll prompt. Property 1191, `of the Bear`, was preserved. |
| Two usable recipients | Both players could use Aboriginal Sash 14113 and received its Need Before Greed prompt. Warrior Pass and mage Need awarded the mage property 1009, `of the Whale`, with enchantments `[82, 71, 0]`. |
| Proficiency refresh | After the warrior learned spell 202, the next rabbit awarded both sword and mace automatically without reconnecting. |

The full-bag case exposed a missing corpse lootability update. After fixing
that publication, a fresh server and two fresh clients against `3a0c2f16`
completed the recovery sequence:

1. The warrior's backpack was full. The mage was level 9, below the sash's
   required level 10. Killing Squirrel `17379390985713164556` awarded the
   warrior the sash automatically; the client displayed the win and
   `Inventory is full`.
2. The corpse held one unlooted, unblocked sash with `owner_guid: 1`, property
   756 (`of the Owl`), and enchantments `[79, 83, 0]`. Its roll and reservation
   maps were empty. The warrior could immediately open its loot window.
3. The warrior logged out, removing its process and presence metadata. The
   mage returned to level 50 but still could not loot the sash. Its projected
   loot view returned `:nothing_to_take`; ownership and the exact property
   remained intact.
4. The warrior reconnected, deleted one filler item, reopened the corpse, and
   clicked the loot icon. Native chat displayed the sash receipt. Backpack
   slot 38 contained exactly one item 14113 with property 756 and enchantments
   `[79, 83, 0]`; the mage had none. The corpse remained dead and its loot
   session was cleared.

These recovery checks completed within the staged creature's 180-second
respawn period. They do not imply retention beyond corpse cleanup or server
restart. Both clients used the GPU: their `amdgpu` graphics counters increased
from 2,626,096,005 to 24,051,042,078 ns for the warrior and from 2,599,941,944
to 31,311,717,474 ns for the mage during the final run.

No owner-process errors or crashes appeared in the final server log. Existing
unimplemented account-data and GM-ticket query warnings remain. Both client
services were stopped and confirmed inactive with empty control groups; both
WoW PIDs exited. The retained server was stopped and ports 4000, 8085, and
3724 were confirmed free before the documentation commit.

## Evidence and automated validation

Initial client artifacts:

- Warrior: `/home/pikdum/.cache/thistle-wow-playtest.NWbxp0/`
- Mage: `/home/pikdum/.cache/thistle-wow-playtest.fI14g3/`
- Screenshots: `group-loot.png`, `group-won.png`, `automatic-award.png`,
  `no-roll-prompt.png`, `nbg-two-eligible.png`, and `trained-eligibility.png`
  under the respective session's `screenshots/` directory.
- Probes: `/tmp/thistle-nbg-{group-loot,auto,cloth-roll,trained,usability}.log`

Final recovery artifacts:

- Warrior: `/home/pikdum/.cache/thistle-wow-playtest.fPGbAT/`
- Mage: `/home/pikdum/.cache/thistle-wow-playtest.BIiVU3/`
- Warrior screenshots: `full-final-award.png`, `full-window.png`,
  `recovery-window.png`, and `recovery-receipt.png`.
- Mage screenshot: `offline-protected.png`.
- Probes: `/tmp/thistle-nbg-publication-{full,offline,recovered}.log`
- GPU proof: `/tmp/thistle-nbg-publication-gpu-{before,after}.log`
- Server: `/tmp/thistle-nbg-publication-server.log`

Final implementation gates:

- `mix test.all`: 7,044 passed, including DBC, VMangos, and map integration.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Logs: `/tmp/thistle-nbg-publication-{all,compile,credo}.log`.

Regressions cover shared item requirements, current owner snapshots, missing
eligibility, condition intersections, zero/one/multiple participants, rejected
ineligible votes, automatic awards, retained Need ownership, exact random
properties, duplicate commits, offline winners, reservation loss, and
recipient-specific lootability after failed awards and all-pass rolls. The
architecture dependency allowlist was not expanded.
