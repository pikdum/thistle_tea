# Equipment durability and repairs

Durability now affects gameplay. Combat can wear equipped items, PvE death
removes 10% of maximum durability from equipped items, and spirit-healer
resurrection removes 25% from equipped and carried items. Bank items are
excluded. Broken items remain equipped and visible, but contribute no item
stats, armor, weapon damage, enchantment bonuses, or weapon enchant procs.
Broken shields cannot block; broken weapons no longer satisfy weapon checks.
Repairing restores the normal equipment-derived inputs and bonuses.

Damage enters through the shared health transition and typed effects. The
boundary resolves player ownership, battleground exemptions, and independent
0.5% attacker/victim wear rolls, then delivers updates to the player owner.
Zero damage, absorbed hits, repeated damage to a corpse, and nonlethal
environmental damage do not wear items. PvP deaths, player-controlled pet
kills, battleground deaths, and exempt spells avoid the death penalty.

Wear and repair use `Inventory.Batch` item updates and a single
`InventoryUpdate.apply/2` commit. Repair-all includes carried items, validates
every price and the complete payment first, and leaves everything unchanged
when money or pricing data is missing. Vendor requests validate a living,
nearby repair NPC in the same world and the player's reputation. The
spirit-healer boundary similarly requires a ghost and a nearby healer.

DBC repair factors are loaded into ETS at startup. Prices use item level,
class/subclass, quality, and the existing Honored reputation discount. The
build-5875 client rounds the base cost before discounting, then rounds the
single-precision discounted value with half-copper ties going to the nearest
even copper. Live per-item tooltip comparisons exposed both rounding stages;
regression tests preserve those cases. VMangos supplied the wear, ownership,
exemption, and packet references; client-observed prices take precedence over
its repair-cost truncation.

## Developer setup

The debug playground includes Corina Steele and a Spirit Healer near the
character spawn. `.debug durability <percent> [carried]` applies normal wear
transactions. Omitting `carried` limits it to equipped items.

Useful positions on map 451 are:

- Repair vendor: `.go xyz 16307.2 16323.1 69.44`
- Spirit healer: `.go xyz 16309.2 16314.1 69.44`

Ghosts cannot use ordinary say chat in the client. A self-whisper such as
`/w Debugdruid .go xyz 16309.2 16314.1 69.44` reaches the existing developer
command path. Right-click the NPC model and use its ordinary interaction UI.

## Client acceptance

An isolated World of Warcraft 1.12.1 build-5875 client controlled level-50
Debugdruid. Changes entered through chat commands, merchant clicks, death,
release, healer gossip, both resurrection confirmations, and logout/login.
Tidewave probes read authoritative state without mutating gameplay state.

- Breaking all ten durable equipped items set each to zero. The client
  displayed broken equipment, armor fell from 896 to 36, maximum health from
  1,818 to 1,478, and weapon damage from 70.43–114.43 to 13–14. Equipment
  appearance remained intact. Repair-all restored every item's durability
  and the original derived stats.
- A two-point Honored repair quoted and charged 903 copper. The larger
  combined 10% and 25% loss quoted and charged 8,657 copper after the final
  rounding fix. Per-item tooltip prices matched the server's factors and
  rounding, including the 608-copper boots repair.
- One death changed head durability from 50 to 45, chest from 100 to 90,
  and the main-hand weapon from 65 to 59. Reconnecting as a ghost preserved
  those values and the previous repair payment.
- The healer's two confirmation dialogs applied the additional 25% loss:
  head 45→33, chest 90→65, and main hand 59→43. Ghost flags and ghost/wisp
  auras cleared, Resurrection Sickness appeared, and both the corpse owner
  and its spatial entry disappeared. The client returned to its living
  model and world visibility.
- A final repair restored every durable item to maximum and left 99,953,230
  copper. Logout removed the player owner while retaining this state in the
  runtime store; login restored the repaired equipment and payment.

The original automation client reproduced the cached UI issue documented in
`percent-stat-playtest.md`: it received healer gossip but hid the panel and
sent a zero NPC GUID when its gossip API was called. A separate client copy
with fresh WDB/WTF state and no addons displayed the normal gossip and both
confirmation dialogs. No server workaround was added for that client state.

No gameplay owner or network errors occurred in the final acceptance server
log. Existing unimplemented account-data, raid-info, GM-ticket, time-query,
meeting-stone, and cancel-trade requests appeared during ordinary UI activity.
PvP/pet/battleground exemptions, random combat rolls, bag/bank selection,
unaffordable repairs, enchantment restoration, and shield/parry behavior have
deterministic coverage; a second observer client was not used.

## Evidence

- Breaking/repairing screenshots: `/home/pikdum/.cache/thistle-wow-playtest.qyL825/screenshots/`.
- Healer and final repair screenshots: `/home/pikdum/.cache/thistle-wow-playtest.p43aBh/screenshots/`.
- Fresh client copy: `/storage/games/Thistle-durability-playtest.IkYoZm`.
- State probes: `/tmp/thistle-durability-{clean-broken,honored-repaired,dead,ghost-reconnected,spirit-healed,final-repair,reconnected}.txt`.
- Server log: `/tmp/thistle-durability-acceptance-server.log`.
- Final checks: `/tmp/thistle-durability-final-{tests,compile,credo}.log`.

`mix test.all` passed all 3,406 tests, `mix compile --warnings-as-errors`
passed, and `mix credo --strict` reported no issues. All helper-owned clients
and the retained local server were stopped; logs and screenshots remain.
