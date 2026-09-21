# Auction house implementation

The market rules, runtime escrow, coordinator recovery, mail delivery,
auctioneer authorization, and vanilla client protocol are implemented.
[Build-5875 client acceptance](auction-playtest.md) covers separate accounts,
all settlement paths, full bags, reconnect, and linked versus neutral markets.

## Rules implemented

- Houses 1–3 share the Alliance market, 4–6 share Horde, and 7 is neutral.
  DBC rates are cached at startup: faction houses charge five percent of
  vendor value per two hours and a five-percent sale cut; neutral houses use
  twenty-five percent and fifteen percent respectively.
- Listings accept 120, 480, or 1,440 minutes. Deposits include the entire
  stack. Price limits, opening bid versus buyout, ownership, and funds are
  validated before producing a transition.
- Bids reserve money. Raising one's own bid charges the difference. Other
  bidders receive their previous reservation by mail. The minimum increment
  is `max(div(current_bid, 100) * 5, 1)` copper.
- Characters cannot bid on their own account's auctions. Buyout charges the
  listed buyout amount and settles immediately. The seller receives the bid
  plus deposit minus cut; the winner receives the exact item instance.
- Cancellation forfeits the deposit. With an existing bid, the seller must
  pay the sale cut and the bidder receives a full refund. Unsold expiry
  returns the item; sold expiry follows the normal winning settlement.
- Auction settlement mail uses vanilla subject codes, body fields, auction
  stationery, and immediate delivery. Stable delivery keys distinguish
  repeated outbid refunds and permit idempotent dispatch.
- Search supports names, classes, subclasses, equipment slots (including
  robes under chest), minimum quality, level bounds, eligibility callbacks,
  deterministic buyout ordering, and fifty-row pages. Owner and bidder lists
  remain inside the linked market; bidder refreshes include requested outbid
  listings without duplicating rows.
- Sale eligibility reuses shared transfer rules and additionally rejects
  conjured and temporary items. Inventory detachment and fees are planned
  through `Inventory.Batch` and `Inventory.plan` before commitment.

The core has no database, clock, process, metadata, or packet dependencies.
`World.Loader.AuctionHouse` maps cached DBC rows and auctioneer factions into
internal house data. Neither listings nor queries perform gameplay database
queries.

## Runtime ownership and recovery

`World.System.Auction` serializes transactions while the requesting player
is blocked. `AuctionStore` commits the book, exact item ownership, player
receipt, and settlement outbox in one insertion into the application-owned
ItemStore table. The player projects and acknowledges its receipt; login
recovers an interrupted projection without applying it twice.

The Post Office retains custody and keyed delivery identities in
application-owned ETS. The outbox retries with stable keys, and replaying a
posted delivery never restores an acknowledged attachment or refund. Players
save incoming mail before acknowledging custody and reject stale or duplicate
delivery notifications. These are runtime guarantees; restarting the whole
server deliberately wipes all accounts, characters, items, and mail.

Each request checks the live vanilla auctioneer flag (`0x1000`), life state,
faction interaction, world, and distance. Search eligibility also checks
equipment requirements, reputation, required spells, and learned recipes.
Listing packets carry the exact vanilla 64-byte rows.

## Client acceptance

Three real clients completed sale, bid increase, outbid refund, buyout,
cancellation, unsold and sold expiry, full bags, offline delivery, reconnect,
and market isolation. The final owner and saved balances reconcile with the
fees; all exact item instances reached their intended inventories. The book,
settlement mailboxes, pending receipts, and outbox were empty afterward.

Development seeding provides `debugbuyer/debugbuyer` and
`debugbidder/debugbidder` alongside the original debug account. The command
`.debug auction expire <id>` settles only the invoking character's own
auction through the normal expiry and mail path.

## References and checks

Rules and layouts were checked against local VMangos
`AuctionHouse/AuctionHouseMgr.cpp`, `Handlers/AuctionHouseHandler.cpp`,
`Server/Packets/AuctionHouse.cpp`, and `Mail/Mail.cpp`, plus the vanilla
`refs/wow_messages` auction definitions and actual `AuctionHouse` DBC rows.

The implementation passes 3,932 tests through `mix test.all`, compilation with
warnings as errors, strict Credo, and formatting checks. Focused tests cover
money conservation paths, exact item identity, same-account and market
rejection, repeated refunds, deadline settlement, fees, queries, transfer
eligibility, and loaded DBC rates. Boundary tests additionally cover competing
buyouts, coordinator and Post Office restarts, delivery retries, player
recovery, client dispatch, and exact wire layouts. Final logs are
`/tmp/thistle-auction-protocol-all.log`,
`/tmp/thistle-auction-protocol-final-compile.log`, and
`/tmp/thistle-auction-protocol-credo.log`.
