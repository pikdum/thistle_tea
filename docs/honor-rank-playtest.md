# Honor rank requirements: client acceptance

Validated commit `56738e4c` with the build-5875 client, Debugwarrior (GUID 1)
at level 60, Officer Areyn (entry 12805), and the real Champions' Hall
entrance trigger 2532. Rank setup used `.debug honor points` through the
realm ledger. Tidewave probes only read state.

## Item use and purchases

Private's Tabard (15196) requires internal rank 5, displayed as Private.

1. At current/highest rank 0, a tabard supplied with `.additem` could not be
   equipped. The client sent `CMSG_AUTOEQUIP_ITEM` and displayed the required
   rank error. The tabard stayed in the backpack.
2. Officer Areyn still listed the tabard. `BuyMerchantItem(1,1)` sent
   `CMSG_BUY_ITEM` and displayed the rank error. Money stayed at 100,100,000
   copper and the character still owned one tabard.
3. At 100 rank points (current/highest internal rank 5), the tabard equipped.
   A duplicate purchase correctly failed the existing unique-item limit.
   After deleting that setup item through the client, buying a replacement
   charged exactly 10,000 copper. Money became 100,090,000, and the purchased
   tabard, GUID 4611686018427388093, equipped successfully.
4. After setting rank points to zero, current rank became 0 and highest
   remained 5. Unequipping and re-equipping the purchased tabard succeeded.
   Another purchase displayed the rank error and left money and ownership
   unchanged, even though the tabard remained eligible for use.

The player owner and CharacterStore agreed on equipment. Owner-published
metadata contained internal ranks 5/0 and condition snapshots contained
visible ranks 1/0 at the corresponding stages.

## Conditions, world entry, and reconnect

At 15,000 rank points (visible rank 5), entering trigger 2532 displayed the
Knight-rank requirement and retained map 0. At 20,000 points (visible rank 6),
the same trigger admitted the character into map 449 at
`{-0.401287, 2.40001, -0.255885}`. The client displayed Champions' Hall and its
NPCs. No direct teleport to map 449 was used.

After returning to Stormwind and dropping to zero points, logout/login
retained current rank 0, highest internal rank 10, the purchased tabard, and
100,090,000 copper. The ledger, player owner, saved character, and published
rank agreed. The former Knight was denied entry by trigger 2532 again,
demonstrating that the condition uses current rank rather than earned rank.

A stale resource label in one reconnect screenshot was checked separately:
the client reported power type 1 and maximum 100, the owner and saved unit
retained Rage with maximum 1000 protocol units, and hovering the bar showed
`Rage 0/100` without changing gameplay state.

## Evidence and checks

- Client session: `/home/pikdum/.cache/thistle-wow-playtest.6mri5i`.
- Screenshots in that session: `rank-shop.png` (equip rejection),
  `rank-purchase-denied.png`, `rank-purchased-equipped.png`,
  `rank-demoted-purchase-denied.png`, `rank-hall-denied-message.png`,
  `rank-hall-entered.png`, `rank-former-knight-denied.png`, and
  `rank-reconnected.png`.
- Runtime snapshots: `/tmp/thistle-rank-demoted-state.log`,
  `/tmp/thistle-rank-hall-state.log`, `/tmp/thistle-rank-reconnected-state.log`.
- Server log: `/tmp/thistle-rank-playtest.log`. No error or spell-validation
  failures occurred. Existing login stubs logged account-data, raid-info,
  GM-ticket, query-time, and meeting-stone requests.
- `mix test.all`: 3,864 passed. Compilation with warnings as errors, strict
  Credo, formatting, and the generated condition-coverage report passed.
  Gate logs are `/tmp/thistle-rank-{all,compile,credo,format}.log`.

The helper client, X server, and retained server were stopped after acceptance.
