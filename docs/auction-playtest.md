# Auction houses: client acceptance

Validated at `939f7b8e` with three isolated build-5875 clients and separate
accounts. Debugwarrior (GUID 1, account 1013) sold items; Debugbuyer (GUID 10,
account 1014) and Debugbidder (GUID 11, account 1015) bid. Each began with
100,000,000 copper. Setup used development item and travel commands; auctions
and mail used the real client UI and its ordinary Lua APIs. Tidewave read
owner state, the market book, escrow, and saved characters without mutating
gameplay state.

## Transactions and client behavior

1. Auctioneer Jaxon opened the Stormwind auction UI. A twenty-item Runecloth
   stack listed for two hours with a 10,000-copper opening bid and 20,000
   buyout. The client showed the listing, the stack left the seller's bag,
   and the owner paid the 400-copper deposit. Item GUID
   `4611686018427388132` remained in escrow with owner zero.
2. Debugbuyer bid 10,000, then raised the bid to 10,500. The second request
   charged only 500. Debugbidder offered 11,025, matching the next increment;
   the first buyer received an outbid notice and a 10,500-copper refund
   letter. The seller's owner list showed the current high bidder.
3. The seller logged out completely. Debugbuyer filled every backpack slot
   and bought out the auction for 20,000. The client displayed the win and
   removed the listing. The rival received an 11,025-copper refund, the
   buyer received the original stack by mail, and the offline seller's
   proceeds were retained by the Post Office.
4. On login, the seller received the successful-auction letter containing
   19,400 copper: buyout plus deposit minus the 1,000-copper cut. The real
   mailbox displayed the translated auction subjects and house names.
   Both outbid refunds were collected. Taking the won item with full bags
   displayed **Inventory is full** and preserved the attachment. Removing
   one test filler item allowed collection of the original twenty-item
   stack. Logout/login retained that exact GUID and the buyer's balance of
   99,980,000 copper, with no duplicate mail.
5. A five-item Greater Healing Potion listing took a 31-copper deposit.
   Debugbidder offered 1,000. Cancellation charged the seller 50 copper,
   returned item GUID `4611686018427388163` by mail, and refunded the bidder
   1,000. The bidder's client displayed the seller-cancellation notice.
6. A twenty-item Linen Cloth listing from Stormwind appeared at Auctioneer
   Buckler in Ironforge, proving the linked Alliance market. Its deposit
   was 13 copper and opening bid 1,000. Another twenty-item stack listed at
   Auctioneer Graves in Booty Bay took a 65-copper neutral deposit and had a
   2,000 opening bid. The two searches each showed exactly their own market's
   listing, even though both stacks belonged to the same character.
7. Both unsold Linen Cloth auctions expired through
   `.debug auction expire <id>`. Their deposits were forfeited, the client
   displayed expiration notices, and mail returned both original GUIDs:
   `4611686018427388164` and `4611686018427388165`. The mailbox distinguished
   Stormwind Auction House from Blackwater Auction House.
8. A five-item Runecloth listing took a 100-copper deposit. Debugbidder's
   1,000-copper bid appeared as **High Bidder** in the client Bids tab.
   Expiry removed the listing and displayed sold/won notices. The winner
   received original item GUID `4611686018427388166`; the seller received
   1,050 copper. Opening the letters rendered the seller/buyer names and the
   sale price, returned deposit, cut, and amount received correctly.

The expiry command changes only the invoking seller's selected listing and
uses the ordinary settlement path. This run did not wait two hours in real
time. Deterministic coordinator tests cover deadline boundaries and recovery
with an advanced clock; the same pure expiry operation drives the timer.

## Final accounting and cleanup

All attachments and money were collected. A read-only assertion script
verified these owner and saved balances:

| Character | Final copper | Result |
| --- | ---: | --- |
| Debugwarrior | 100,019,791 | Sale proceeds minus cuts and forfeited deposits |
| Debugbuyer | 99,980,000 | Bought twenty Runecloth for 20,000 |
| Debugbidder | 99,999,000 | Bought five Runecloth for 1,000; other bids refunded |

The difference from the original combined 300,000,000 copper is exactly
1,209: 1,000 for the buyout cut, 31 plus 50 for cancellation, 13 plus 65 for
unsold deposits, and 50 for the final sale cut. The seller retained five
Greater Healing Potions and forty Linen Cloth; the buyers retained their
respective twenty- and five-item Runecloth stacks. Every checked GUID and
stack count matched its original listing.

The market book, player settlement mailboxes, pending auction receipts, and
delivery outbox were empty. All three clients and their X servers were
stopped, followed by the retained game server. No auction, mail, player-owner,
or packet-decoding errors occurred. Existing session warnings remained for
account-data updates, raid information, GM tickets, query time, meeting
stones, emotes, and AFK chat type 20.

## Evidence and automated checks

- Seller session: `/home/pikdum/.cache/thistle-wow-playtest.eLzgdX`.
- Buyer session: `/home/pikdum/.cache/thistle-wow-playtest.jbV4Vw`.
- Rival session: `/home/pikdum/.cache/thistle-wow-playtest.mJZpG9`.
- Seller screenshots include `auction-listed.png`, `owner-bid-notice.png`,
  `seller-offline-confirmed.png`, `canceled-auction.png`,
  `neutral-only-search-confirmed.png`, `unsold-expiry.png`,
  `sold-expiry-owner.png`, `final-settlement-mail.png`,
  `sale-accounting-letter.png`, and `seller-all-settled.png`.
- Buyer screenshots include `opening-bid.png`, `outbid-notice.png`,
  `buyout-complete.png`, `full-bag-claim-rejected.png`,
  `auction-item-collected.png`, `buyer-reconnect-and-linked-market.png`,
  and `alliance-isolated-confirmed.png`.
- Rival screenshots include `canceled-bid-notice.png`,
  `bidder-list-before-expiry.png`, `sold-expiry-winner.png`,
  `winning-expiry-letter.png`, and `bidder-all-settled.png`.
- Runtime snapshots: `/tmp/thistle-auction-snapshots.log`.
- Final assertions: `/tmp/thistle-auction-final-proof.log`.
- Server log: `/tmp/thistle-auction-playtest.log`.

The final implementation passes 3,932 tests with `mix test.all`, including
market rules, live-item escrow, receipt recovery, competing buyouts, Post
Office restart recovery and posting retries, eligibility, loaded DBC rates,
NPC authorization, dispatch, and exact vanilla packet layouts.
`mix compile --warnings-as-errors`, `mix credo --strict`, and
`mix format --check-formatted` also passed. These gates preceded the client
run; no implementation changed during or after it. Logs are
`/tmp/thistle-auction-protocol-all.log`,
`/tmp/thistle-auction-protocol-final-compile.log`, and
`/tmp/thistle-auction-protocol-credo.log`.
