# Equipment destination requests

`CMSG_AUTOEQUIP_ITEM_SLOT` (`0x10F`) now accepts the vanilla nine-byte payload:
an unsigned little-endian 64-bit item GUID followed by an equipment slot.
Slots 0–18 address equipment; slots 19–22 address equipped bags. Missing,
unowned, detached, invalid-destination, and same-slot requests are ignored.

The player inventory boundary resolves the item's current position from owned
inventory and delegates to the existing swap path. This preserves proficiency,
level, reputation, binding, combat, equip cooldown, stat recomputation, and
item/character projection rules. Bank sources require a currently valid banker
session, including another distance check when an old session has gone stale.

References: VMangos revision `8f4e608450460efe1e38743e4da74397d4773a3a`,
`ItemHandler.cpp:HandleAutoEquipItemSlotOpcode`, `Player.cpp:IsEquipmentPos`,
and `refs/wow_messages/wow_message_parser/wowm/world/item/cmsg_autoequip_item_slot.wowm`.

## Native equipment regression

An isolated build-5875 client used Debugwarrior (GUID 1) and a fresh server at
`1330444d`. All mutations used native Lua inventory APIs, the binding prompt,
ordinary login/logout, and `.additem` / `.learn` commands. Tidewave only read
item positions, owner identity, cooldown deadlines, and stored character state.

The native `EquipCursorItem` actions below emitted `CMSG_SWAP_INV_ITEM`, not
the new GUID opcode. This run validates the shared equipment transition and
client projection. Dispatch and boundary tests validate the new opcode; native
generation of `CMSG_AUTOEQUIP_ITEM_SLOT` remains unverified. Picking an item
from an action button did not produce that opcode either.

| Action | Verified result |
| --- | --- |
| Equip Blazing Emblem (2802) into client slot 14 and accept binding | Second trinket slot contains the same item GUID, first slot remains empty, item is bound, and client reports a 30-second equip cooldown. |
| Equip Mooncloth Bag (14155) into client slot 23 | Fourth bag slot contains the bag and exposes 16 slots. |
| Attempt Battleworn Hammer (2361) without proficiency | Client reports missing proficiency; weapon, shield, and hammer positions remain unchanged. |
| Learn Two-Handed Maces (199), then repeat | Hammer enters main hand; old main-hand item 12774 returns to the hammer's backpack slot; shield 10195 moves into another backpack slot; offhand becomes empty. |
| Log out | Owner process lookup and world position both become nil. |
| Log back in | A new owner retains identical item GUIDs, positions, binding flags, and cooldown deadline. Client displays the trinket, hammer, and 16-slot fourth bag; stored player matches the owner. |

No owner or equipment errors occurred. Login produced the existing unrelated
account-data and GM-ticket unsupported-opcode warnings.

## Bank offhand storage regression

Final code review found that a two-handed weapon leaving a bank slot could
incorrectly count that slot as space for the displaced shield. With full
carried storage and an empty main hand, validation passed while shield storage
failed, leaving both a two-handed weapon and shield equipped.

The pure validator now evaluates carried space after the source position has
received the destination item. It uses the same slot eligibility checks as the
actual offhand placement. A vacated bank slot cannot satisfy carried storage;
a vacated compatible backpack or carried-bag slot can.

The regression failed before the fix and passes afterward. Tests cover bank
slots and bank-bag contents with full carried storage, acceptance after freeing
a backpack slot, and use of the vacated carried slot. This correction was
validated automatically after the native run, without a native bank scenario.

## Evidence

- Client artifacts: `/home/pikdum/.cache/thistle-wow-playtest.CGSukV`.
- Screenshots: `trinket-equipped.png`, `twohand.png` (proficiency rejection),
  `trained-twohand.png`, and `reconnected.png`.
- Server log: `/tmp/thistle-equip-slot-server.log`.
- Read-only snapshots: `/tmp/thistle-equip-slot-{trinket,twohand,trained-twohand,offline,reconnected}.log`.
- WoW PID 2939233 used `amdgpu`; its graphics counter increased from
  635,195,119 to 8,388,896,540 ns. Evidence is in
  `/tmp/thistle-equip-slot-drm-{before,after}.log`.
- Owned client service and retained server were stopped; artifacts remain.
- The focused final suite passed 126 tests. Regression evidence is in
  `/tmp/thistle-equip-slot-bank-{red,green}.log`.

Final gates after the bank correction passed: `mix test.all` reported 7,476
tests, seed 517186, in 69.3 seconds; `mix compile --warnings-as-errors` passed;
`mix credo --strict` reported zero issues. Logs are
`/tmp/thistle-equip-slot-final-{tests,compile,credo}.log`.
