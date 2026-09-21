# AFK, DND, and whisper acceptance

Build 5875, September 20, 2026. Implementation: `7aedfe84`.
All 3,944 tests pass, as do compilation with warnings as errors, strict Credo,
and formatting. No source changes or compiler runs occurred during acceptance.

## Behavior and ownership

`Entity.Data.ChatStatus` stores one session mode and reply. Pure
`Logic.ChatStatus` transitions project only the AFK/DND bits of `PLAYER_FLAGS`,
preserving leader, rest, and other flags. Empty requests toggle the current mode;
nonempty requests update its reply. Entering either mode clears the other.
AFK requests are ignored in combat, while DND remains available.

`Player.ChatStatus` dispatches entry into AFK through the existing battleground
leave path. The player owner's ordinary update funnel broadcasts player flags
and party member status, and `World.Presence` publishes the current reply.
Login clears the session status before publishing Presence.

Whispers deliver the sender's tag, echo the message to its sender with the
recipient's tag, and return the recipient's current AFK/DND reply. Ordinary
whispers use universal language. Say, yell, party, channel, and custom emote
messages carry the sender's current tag. Channel tags come from the current
request rather than the saved membership snapshot. The shared message encoder
uses UTF-8 byte lengths and preserves its supplied language, including addon
language; addon whispers do not generate a normal sender echo.

Reference behavior comes from VMangos `ChatHandler.cpp`,
`MasterPlayerChat.cpp`, `Player::ToggleAFK`, `Player::ToggleDND`,
`GetGroupMemberStatus`, and `ChatHandler::BuildChatPacket`.

## Real-client checks

Debugwarrior (GUID 1) and Debugbuyer (GUID 10) used separate isolated clients and
accounts. They formed a party in Stormwind. Client commands and ordinary UI
interaction performed all gameplay mutations; Tidewave probes read state only.

| Action | Client evidence | Authoritative evidence |
| --- | --- | --- |
| AFK with `Tea break` | Observer saw overhead, say, party, and channel AFK tags; whisper echo included AFK and the automatic reply | Mode AFK; flags 35 preserved resting and leader bits; party status 65; Presence matched |
| Switch to DND | Overhead and chat tags changed to DND; whisper reply was `Concentrating` | Mode DND; flags 37; party status 129; AFK bit cleared |
| Update DND message | Next whisper returned `Updated busy reply` | Existing DND mode retained with the new reply |
| Logout and login | Observer lost and regained the player; subsequent whisper had no status tag or automatic reply | Logout removed owner and metadata; login restored available mode, empty reply, flags 33, and party status 1 |
| AFK during a duel | Player remained in combat without an overhead AFK tag | Both duel owners were in combat; the sender stayed available with no AFK bit |
| DND during that duel | DND command remained usable | In-combat owner entered DND with flags 5 and party status 129 |
| Enter Warsong through Enter Battle | Client loaded Silverwing Hold in instance 1 | Map 489, instance 1, registered participant |
| DND inside Warsong | Player remained in the battleground | Mode DND and membership `in_progress` |
| Switch to AFK inside Warsong | Client returned to Northshire; observer saw the returning AFK tag | Exact return position `{-8949, -132, 83.56324768066406}` on open map 0; membership `none`; empty match stopped; AFK retained |
| Restore automatic AFK clearing | Further client keyboard input cleared AFK | Available mode, empty reply, flags 1; Presence agreed |

The vanilla client clears AFK on keyboard input by default. For stable tag and
reply checks, `autoClearAFK` was temporarily set to 0, then restored to 1.
The client also prints an optimistic "You are now AFK" line when submitting a
request during combat; the owner state and public flags confirm the server
correctly rejected that request. A diagnostic attempt to call `UnitIsAFK`
failed because that Lua API is absent in this client; subsequent checks used
visible tags and server projections.

Automated regressions cover empty toggles, nonempty updates, mutual exclusion,
combat restrictions, unrelated flag preservation, reconnect normalization,
party status, recipient lookup, whisper replies and echoes, current channel
tags, Unicode byte lengths, and spoken/addon language encoding.

## Retained evidence

- Actor session: `/home/pikdum/.cache/thistle-wow-playtest.Pi6tpT`
- Observer session: `/home/pikdum/.cache/thistle-wow-playtest.sIk7gf`
- Actor screenshots: `afk-tags.png`, `combat-afk-rejected.png`,
  `warsong-before-afk.png`, `warsong-afk-exit.png`
- Observer screenshots: `afk-reply.png`, `dnd-reply.png`, `updated-reply.png`,
  `reconnect-clear.png`, `observer-afk-return.png`
- Server log: `/tmp/thistle-chat-playtest.log`
- State samples: `/tmp/thistle-chat-snapshots.log`
- Final assertions: `/tmp/thistle-chat-final-proof.log`, `accepted: true`
- Gates: `/tmp/thistle-chat-all.log`, `/tmp/thistle-chat-compile.log`,
  `/tmp/thistle-chat-credo.log`, `/tmp/thistle-chat-format.log`

No server errors or unknown chat-type warnings occurred. Existing unsupported
account-data, raid-info, GM-ticket, query-time, and meeting-stone requests remain
outside this change. Both clients and the retained server were stopped; evidence
was retained. Emote animation and cancellation remain separate follow-up work.
