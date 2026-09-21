# Quest sharing acceptance

Build 5875, September 20, 2026. Core rules: `9aa7755d`; owner and protocol
integration: `fab73087`; credential inspection redaction: `95700c07`; client
clock synchronization: `3dcd3d18`; quest-item lifecycle: `18a8f749`.

All 4,031 tests pass, along with compilation with warnings as errors, strict
Credo, and formatting. The first successful client run used `fab73087`; the
final run used `18a8f749`. No source edits, builds, tests, or commit hooks ran
while either playtest server was live.

## Behavior and ownership

`Logic.QuestSharing` owns pure share eligibility, ordered feedback, and timer
inheritance. Manual sharing requires flag `0x8`, an active unexpired quest,
party membership, the same world, and distance strictly below 14 yards.
Recipients receive native sharing, acceptance, decline, distance, busy,
log-capacity, existing-quest, and completed-quest results. Requirements and
conditions are checked when presenting the offer and again on acceptance.

`Player.QuestSharing` owns the pending offer in the player's state. An offer
records the quest, group, sharer GUID, sharer process, and mode; a process
monitor observes sharer loss. Acceptance must match this offer and its live
source. Client result packets cannot claim successful acceptance or redirect
feedback through a forged GUID. Inventory rejection does not add the quest or
send an accepted result.

NPC acceptance of a quest with party-accept flag `0x2` sends the native party
confirmation popup to eligible members in the same world. Ordinary quests
respect raid subgroups; raid quests can cross subgroups. This confirmation has
no manual-sharing distance requirement. Confirmation does not repeat the NPC
start script. Manual timed sharing copies the sharer's remaining deadline;
party confirmation uses the ordinary fresh quest timer.

Abandonment, quest invalidation, group changes, logout, and owner loss invalidate
pending offers. Accepted quests survive reconnect through `CharacterStore`,
while offers and monitors do not. `SMSG_GOSSIP_COMPLETE` invalidates the native
questgiver reference, although this client can leave old dialog text visible
until dismissal. Accepting that stale dialog sent GUID zero and granted no
quest.

`Logic.QuestItems` computes source-item deficits including bank storage.
Abandonment consumes the source quantity when available, preserves a source
that itself starts the same quest, and restores a distinct original starter
when appropriate. Quest-bound objective items are removed from carried and
bank storage; ordinary objective trade goods remain. Overlapping source and
objective removals are combined. Removals and replacements use one
`Inventory.Batch` plan and one commit; failure preserves both quest and items.
Quest consumption can remove protected scrolls while still rejecting nonempty
bags. Original starter templates are loaded at the quest boundary.

The playtest exposed a missing `CMSG_QUERY_TIME` response: correct absolute
quest deadlines appeared about six hours too long in the client. The new
response sends Unix seconds in the vanilla four-byte layout. Connection and
account inspection also redact credentials and authentication buffers, after
an overloaded exploratory run exposed those fields in crash logging.

References: local VMangos `Handlers/QuestHandler.cpp`,
`Handlers/QueryHandler.cpp`, `Objects/Player.cpp`, `Objects/Player.h`,
`Objects/Object.h`, `Objects/ItemPrototype.h`, `QuestDef.h`, `GossipDef.cpp`, and
`Server/Packets/Quest.*` and `Query.*`.

## Real-client checks

Debugpaladin (GUID 2), Debugbuyer (GUID 10), and Debugbidder (GUID 11) used
separate accounts and isolated clients. Ordinary sharing ran in Northshire.
NPC party confirmation began at Professor Phizzlethorpe in Faldir's Cove while
the recipients remained in Northshire. Gameplay changes used client commands
and native UI interactions. Tidewave sampled stored characters and world state;
read-only owner inspection checked private offers and monitors. Tracing recorded
incoming codecs and outgoing packets.

| Action | Client evidence | Authoritative evidence |
| --- | --- | --- |
| Share Gold Dust Exchange; accept and decline | Both recipients saw the sharer's quest dialog; source saw acceptance and decline feedback | Buyer gained quest 47, witness did not; result codes 2 and 3 |
| Repeat sharing, then share Protect the Frontier while an offer is pending | Source saw existing-quest and busy feedback | Codes 7 and 5; the witness's original offer was preserved |
| Move the recipient beyond sharing distance | Source saw too-far feedback | Code 4; attempted stale acceptance added no quest |
| Abandon the source quest with a pending recipient | Old dialog could remain visible but could no longer grant the quest | Offer and monitor cleared; stale GUID-zero acceptance was rejected |
| Share A Hunter's Boast after its timer starts | Final client showed 13 minutes 45 seconds, rather than six extra hours | Source and buyer had identical monotonic and Unix deadlines; witness declined |
| Accept Dearest Colara through sharing | Carefully Penned Note appeared in the backpack | Exactly one item 21921 and quest 8897 |
| Abandon that quest and accept a fresh share | Note disappeared, then exactly one note returned | Original instance was destroyed; reacceptance created one different instance |
| Reconnect with an unanswered Gold Dust Exchange offer | Accepted quests and note returned; countdown showed 10 minutes 15 seconds | Original timer retained, one note, no quest 47, no pending offer or monitor |
| Log out the sharer with the witness still pending | Stale offer could no longer be accepted | Sharer offline; witness offer and monitor cleared |
| Accept Sunken Treasure from the actual NPC | Both distant recipients saw the native confirmation popup and clicked Yes | Both sent `CMSG_QUEST_CONFIRM_ACCEPT`; all three gained quest 665 |
| Abandon a timed quest with native UI controls | Confirmation worked; timer and quest disappeared without a Lua error | Quest removed normally |
| Remove remaining quests and leave the party | Empty quest log, empty note slot, no quest timer or party frames | All three had empty logs, no offers or monitors, no group, and no note instances left in `ItemStore` |

The final proof contains 23 passing assertions. Automated coverage additionally
checks full logs, conditions, repeatability, expired sources, process replacement,
raid subgroups, script non-repetition, forged results, exact packet layouts and
dispatch, banked source counts, protected objective items, starter exchanges,
and atomic rollback when a replacement cannot fit.

An initial unrestricted run saturated the CPU with three software-rendered
clients and caused timeouts; it was discarded as acceptance evidence. Subsequent
runs limited the clients to cores 0–1, 2–3, and 4–5. The final run stayed
responsive and logged no server errors or unimplemented quest-sharing/time-query
requests. Existing account-data, raid-info, GM-ticket, and meeting-stone warnings
remain outside this feature.

The first bulk-cleanup macro used `SelectQuestLogEntry` while the quest window
was displaying a timer. Selecting an untimed quest this way reproduced a
`SecondsToTime(nil)` client error without any abandonment request. Native UI
abandonment passed. Cleanup was corrected to use `QuestLog_SetSelection`, which
refreshes the displayed quest details, and repeated successfully. This follows
the client [quest-log UI implementation](https://github.com/MOUZU/Blizzard-WoW-Interface/blob/master/1.12.1/FrameXML/QuestLogFrame.lua).

## Retained evidence

- Final leader: `/home/pikdum/.cache/thistle-wow-playtest.4IFGTB`
- Final buyer: `/home/pikdum/.cache/thistle-wow-playtest.ZCvtrR`
- Final witness: `/home/pikdum/.cache/thistle-wow-playtest.PAOHgV`
- Buyer screenshots: `fixed-timer-running.png`, `fixed-note-before-abandon.png`,
  `fixed-note-after-abandon.png`, `fixed-reconnect-timer-and-note.png`,
  `fixed-party-confirmation.png`, `fixed-party-quest-accepted.png`,
  `timed-native-abandon-confirm.png`, `timed-native-abandoned.png`, and
  `fixed-cleanup-safe-selection.png`
- Leader screenshots: `fixed-party-questgiver.png`,
  `fixed-party-quest-details.png`, and `fixed-cleanup-leader.png`
- Witness screenshots: `fixed-party-confirmation-witness.png` and
  `fixed-cleanup-witness.png`
- Earlier successful run: leader `thistle-wow-playtest.8wYvNj`, buyer
  `thistle-wow-playtest.3YbtCP`, witness `thistle-wow-playtest.akwCQu` under
  `/home/pikdum/.cache`
- Packet traces: `/tmp/thistle-quest-share-packets.log` and
  `/tmp/thistle-quest-share-fixed-packets.log`
- State samples: `/tmp/thistle-quest-share-state-<phase>.term`; final phases
  begin with `fixed-`
- Final assertions: `/tmp/thistle-quest-share-final-proof.log`, `accepted: true`
- Final server log: `/tmp/thistle-quest-share-fixed-playtest.log`
- Gates: `/tmp/thistle-quest-sharing-all.log`,
  `/tmp/thistle-quest-sharing-compile.log`, `/tmp/thistle-quest-sharing-credo.log`,
  and `/tmp/thistle-quest-sharing-format.log`

All clients and the server were stopped, with artifacts retained.
