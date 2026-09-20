# Auction house implementation

The auction system is in development. The pure market, inventory planning,
search rules, and cached house data are implemented. Runtime escrow,
coordinator recovery, idempotent mail delivery, protocol handlers, and client
acceptance remain required before auctioneers can be used in-game.

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

## Required integration

1. Commit market state, item escrow, a player receipt, and settlement outbox
   together in application-owned ETS. Recover unacknowledged receipts on
   login and retain the book across coordinator restarts.
2. Deliver the outbox through an idempotent Post Office operation, retaining
   delivery identity and mailbox custody across coordinator restarts.
3. Validate each auctioneer interaction at the player boundary. Wire the
   vanilla hello, sell, bid, cancel, search, owner list, bidder list, result,
   and notification packets without trusting client prices or positions.
4. Exercise real auctioneer and mailbox UI with distinct accounts: sale,
   bid increase, outbid refund, buyout, cancellation, unsold and sold expiry,
   full bags, offline delivery, reconnect, and market isolation. Verify
   owner state, ledger/escrow state, client messages, and lifecycle cleanup.

## References and checks

Rules and layouts were checked against local VMangos
`AuctionHouse/AuctionHouseMgr.cpp`, `Handlers/AuctionHouseHandler.cpp`,
`Server/Packets/AuctionHouse.cpp`, and `Mail/Mail.cpp`, plus the vanilla
`refs/wow_messages` auction definitions and actual `AuctionHouse` DBC rows.

The foundation passes 3,907 tests through `mix test.all`, compilation with
warnings as errors, strict Credo, and formatting checks. Focused tests cover
money conservation paths, exact item identity, same-account and market
rejection, repeated refunds, deadline settlement, fees, queries, transfer
eligibility, and loaded DBC rates. Logs are
`/tmp/thistle-auction-core-{all,compile,credo,format}.log`.
