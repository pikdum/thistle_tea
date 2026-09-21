# Friend and ignore list acceptance

Build 5875, September 20, 2026. Social state: `a8f85c3c`; protocol and gameplay
integration: `bdd04dc3`.

All 4,003 tests pass, along with compilation with warnings as errors, strict
Credo, and formatting. The client run used `bdd04dc3`. No source edits, builds,
or tests occurred while the playtest server was live.

## Behavior and ownership

`Social` owns pure membership transitions and the independent capacities of 50
friends and 25 ignored characters. The same character can belong to both lists;
removing one relationship preserves the other. `Player.Social` resolves names
through `CharacterStore`, validates requests, and writes the player's complete
row atomically to `World.SocialStore`. Lists survive logout and reconnect within
the server process, following the project's runtime-only persistence model.

Friends must share a faction; ignores can include the opposite faction. Both
support offline characters. Self, missing, duplicate, and full-list additions
return the corresponding vanilla result. Six incoming social messages dispatch
through thin codecs, and three outgoing codecs carry lists and status changes.

`Social.Notifier` derives available, AFK, DND, level, class, and zone information
from registered owners and the live metadata projection. Subareas resolve to
their parent zone through the exploration cache. `World.Presence` sends login
and logout notifications only to online characters who list that friend;
duplicate leave transitions do not repeat the notification. Login sends both
retained lists, and friend-list requests refresh current presence information.

The vanilla client filters ignored local chat and whispers. Its
`CMSG_CHAT_IGNORED` report produces `CHAT_MSG_IGNORED` (`0x16`) feedback to the
sender only when the reporting character actually ignores that sender.
Ordinary channel messages are filtered at the server. Channel moderators retain
the VMangos delivery exception, although this client still hides their text
locally. Ignored channel invitations are suppressed while retaining the sender's
acknowledgment. Party invitations return result 8, and duel admission rejects
ignored challengers before creating a match or flag.

References: local VMangos `SocialMgr.h`, `SocialMgr.cpp`,
`Handlers/MiscHandler.cpp`, `Handlers/CharacterHandler.cpp`,
`Handlers/ChatHandler.cpp`, `Handlers/GroupHandler.cpp`, `Server/WorldSession.cpp`,
`Server/Packets/Social.cpp`, `Server/Packets/Misc.cpp`,
`Chat/MasterPlayerChat.cpp`, `Chat/Channel.cpp`, `SharedDefines.h`, and
`Spells/SpellEffects.cpp`.

## Real-client checks

Debugpaladin (GUID 2), Debugbuyer (GUID 10), and Debugbidder (GUID 11) used separate
accounts and isolated clients in Northshire. Offline Debugdruid (GUID 9) and
Debugshaman (GUID 8) supplied offline and cross-faction cases. The bidder owned
the custom channel `SocialTea`, with the paladin initially an ordinary member.
All gameplay changes used client commands or UI interaction. Tidewave sampled
public state; tracing recorded incoming codecs and outgoing recipient GUIDs.

| Action | Client evidence | Authoritative evidence |
| --- | --- | --- |
| Add the online paladin and offline druid | Friends window showed level 50 Paladin in Elwynn Forest and an offline druid | Buyer friends became `{2, 9}`; results 6 and 7 |
| Try self, missing, and opposite-faction friends | Native error messages appeared | Results 9, 4, and 10; membership unchanged |
| Set the paladin AFK, then DND, refreshing the list | Friend row displayed AFK and DND | Status values were 2 and 4 |
| Raise the paladin to level 51 and teleport to Dun Morogh | Friend row showed level 51 and Dun Morogh | Refreshed level 51 and zone 1 |
| Log the paladin out and back in | Buyer saw offline and online notifications | Exactly one result 3 and one result 2, both only to GUID 10; witness received neither |
| Ignore the paladin and offline Horde shaman | Native added-to-ignore messages appeared | Ignored became `{2, 8}` while friends stayed `{2, 9}` |
| Send say, whisper, and ordinary channel text | Buyer hid all three; witness saw say and channel text; sender saw `Debugbuyer is ignoring you` | Client reported the ignored whisper; feedback type 22 reached GUID 2; channel recipients were only 2 and 11 |
| Send party and duel requests while ignored | Sender saw the ignoring response and `Invalid target`; buyer received no invitation | Party result 8; no group or duel match |
| Temporarily promote the paladin to channel moderator | Buyer saw the moderation notification but still hid the message text | `MODERATOR-CHANNEL` reached GUIDs 2, 10, and 11, preserving the reference delivery exception |
| Invite the buyer to `SocialInvite` while ignored | Buyer received no channel invitation | Sender received acknowledgment 29; recipient notification 24 was absent |
| Log the buyer out and back in | Friends row returned; another ignored whisper still produced sender feedback | Login resent friends `{2, 9}` and ignores `{2, 8}`; a second native ignored acknowledgment arrived |
| Remove both ignores and repeat chat and invitations | Whisper, channel text, channel invitation, and party popup appeared | Ignores became empty; friends remained `{2, 9}`; ordinary channel recipients became 2, 10, and 11 |
| Accept the restored party invitation, then leave | Party frames appeared, followed by the leave message | Group contained GUIDs 2 and 10, then disbanded |
| Request a duel after removing the ignore, then decline | Duel popup and flag appeared, then disappeared | Match reached `:requested`; decline cleared both participants and removed the arbiter from the world |
| Add the offline shaman again and open Ignore | Ignore pane displayed Debugshaman | Stored ignore matched the visible row |
| Remove remaining friends and ignores | Both panes became empty | Empty social lists, no followers for GUID 2, and no group or duel for any actor |
| Log the removed friend out | Buyer received no friend-offline notification | Total offline friend notifications remained one |

Automated coverage also checks capacity limits, duplicate and idempotent
transitions, independent relationship removal, exact conditional packet
payloads, opcode registration, readiness guards, offline state retention,
duplicate presence cleanup, spoofed ignored reports, channel moderator delivery,
and rejected/restored party and duel admission. Capacity was verified with
deterministic fixtures; the live run used three clients.

## Retained evidence

- Leader: `/home/pikdum/.cache/thistle-wow-playtest.zpuIsA`
- Buyer: `/home/pikdum/.cache/thistle-wow-playtest.tqbneN`
- Bidder: `/home/pikdum/.cache/thistle-wow-playtest.a1iyNA`
- Buyer screenshots: `friends-online-and-offline.png`, `friend-afk.png`,
  `friend-dnd.png`, `friend-level-and-zone.png`, `friend-logged-off.png`,
  `ignored-messages-hidden.png`, `reconnect-friends.png`,
  `restored-chat-and-party-invite.png`, `restored-party.png`,
  `restored-duel-invite.png`, `ignore-pane.png`, `friends-removed.png`,
  `ignores-removed.png`
- Leader screenshots: `ignored-feedback.png`, `reconnect-ignored-feedback.png`
- Bidder screenshot: `witness-received-messages.png`
- Packet trace: `/tmp/thistle-social-packets.log`
- State samples: `/tmp/thistle-social-snapshots.log` and
  `/tmp/thistle-social-state-<phase>.term`
- Final assertions: `/tmp/thistle-social-final-proof.log`, `accepted: true`
- Server log: `/tmp/thistle-social-playtest.log`
- Gates: `/tmp/thistle-social-all.log`, `/tmp/thistle-social-compile.log`,
  `/tmp/thistle-social-credo.log`, `/tmp/thistle-social-format.log`

No server errors or unimplemented social-message warnings occurred. Rejecting
the ignored duel logged the expected `bad_targets` validation warning. Login
also logged existing unimplemented account-data, raid-info, GM-ticket, time-query,
and meeting-stone requests. All clients and the server were stopped, with
artifacts retained.
