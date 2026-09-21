# Wrapped gifts

Wrapping paper now transforms an eligible item into its configured gift while
consuming exactly one paper in the same inventory plan. The gift keeps the
item's GUID, current owner, charges, durability, enchantments, and other
instance fields. Its original template and flags live in a typed
`WrappedItem` value inside the item; there is no separate gift store or disk
persistence. Trade and reconnect therefore retain the complete gift.

`CMSG_WRAP_ITEM` dispatches to the player boundary, which checks bank access,
settles completed item costs, and loads the gift template through the existing
cache. `ItemWrapping` validates the pure transition and builds one
`Inventory.Batch` plan. It rejects equipped, already wrapped, bound, stackable,
unique, and bag targets, generated container loot, ongoing casts, and invalid
ownership or paper mappings. Failed plans leave the paper and target intact.

Opening uses `CMSG_OPEN_ITEM`. It restores the original identity and flags in
place, clears the gift creator and saved wrapping metadata, and sends item
updates without generating loot. It retains the current owner and mutable
fields, including enchantment expiry that occurred while wrapped. A corrupt
gift fails without destroying the item.

## References

- `refs/wow_messages/wow_message_parser/wowm/world/item/cmsg_wrap_item.wowm`
  defines the four native bag/slot bytes.
- `refs/vmangos/src/game/Handlers/ItemHandler.cpp::HandleWrapItemOpcode`
  defines paper mapping, eligibility, creator assignment, wrapped flag 8,
  paper consumption, and the casting restriction.
- `Handlers/SpellHandler.cpp::HandleOpenItemOpcode` restores original entry
  and flags and clears the gift creator without opening a loot window.
- `Handlers/TradeHandler.cpp::SendUpdateTrade` projects gift identity and
  creator through the trade window.
- Generated VMangos templates provide `wrapped_gift`; all six retail paper
  mappings are covered by a tagged integration test.

## Native acceptance

Two isolated build-5875 clients used Debugwarrior (GUID 1) as sender and
Debugrogue (GUID 3) as recipient on Programmer Isle, against commit `60c1142c`.
Debug commands supplied the items. All wrapping, item use, trading, and
opening happened through the clients; Tidewave probes only read state.

- The warrior applied Minor Wizard Oil to a carried Worn Shortsword. Oil
  `4611686018427388132` had four charges remaining, and sword
  `4611686018427388133` had coating 2623 and durability 20/20.
- Trying to wrap the soulbound Hearthstone displayed "Bound items can't be
  wrapped." All three red papers remained and no item changed.
- Red paper wrapped the oil as Red Ribboned Gift 5043. The paper stack changed
  from three to two. The same item GUID retained four charges, gained wrapped
  flag 8 and gift creator 1, and kept original identity `{20744, 0}` internally.
- Blue paper wrapped the sword as Blue Ribboned Gift 5044. Its paper stack
  changed from two to one; the same sword GUID retained its coating and
  durability, with original identity `{25, 0}`.
- The warrior offered both gifts in ordinary transferred-item trade slots.
  The recipient saw their colored gift icons and the tooltip "Gift from
  Debugwarrior", without the original item names. Acceptance transferred both
  original GUIDs to owner 3, preserving creator 1 and all retained state.
  No trade session or recovery receipt remained.
- Both players logged out and back in. The gifts remained wrapped in the
  recipient's backpack with their creator, original identities, charges, and
  coating intact.
- Opening each gift restored its item directly in the same backpack slot.
  Ownership stayed with the rogue. Wrapped flags, gift creator, and wrapping
  metadata cleared. Neither opening produced a loot window or loot session.
- The native oil tooltip displayed "4 Charges". The sword tooltip displayed
  "Minor Wizard Oil (27 min)" and durability 20/20, showing that wrapping and
  reconnecting did not restart the coating's duration.
- The recipient reconnected again after opening. The original item GUIDs,
  ownership, four oil charges, coating, and cleared gift metadata remained.

No owner or network errors or unsupported wrapping/opening packets appeared.
Existing unrelated login-opcode warnings remain. Both clients and the server
were stopped before documentation changes.

Artifacts retained:

- `/home/pikdum/.cache/thistle-wow-playtest.AcLFTQ/` (sender)
- `/home/pikdum/.cache/thistle-wow-playtest.J8L5L1/` (recipient)
- `/tmp/thistle-gifts-server.log`
- `/tmp/thistle-gifts-{initial,used,rejected,red,wrapped,offered,received,reconnect,opened,opened-reconnect}.txt`

## Automated validation

- `mix test.all`: 4,199 passed, including DBC, VMangos, and map integration.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- `mix format --check-formatted`: passed.

Tests cover exact paper consumption, the last paper, full bags, wrapping
restrictions, invalid mappings and ownership, casting and death, remote bank
access and movement control, pending item charges, corrupt gifts, transfer and
recipient restoration, mutable enchantment expiry, packet registration, trade
creator projection, and opening without loot. The dependency allowlist was
not expanded. Mail and auction gift delivery were not part of this native pass.
