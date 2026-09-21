# Raid group acceptance

Build 5875, September 20, 2026. Membership core: `47df65f3`; protocol and
gameplay integration: `75156de2`; quest target crash fix: `868b59e0`.

All 3,985 tests pass, along with compilation with warnings as errors, strict
Credo, and formatting. The final client run used `868b59e0`. No source edits,
builds, or test runs occurred while either playtest server was live.

## Behavior and ownership

`Party` owns pure membership, leadership, assistant, subgroup, and marker
transitions. `World.System.Party` serializes mutations and publishes the group
and membership indexes in ETS. `Player.Groups` validates player requests and
projects the resulting roster or notification through `Party.Notifier`.
Conversion preserves the existing group ID, members, and loot settings.

A raid supports 40 members in eight subgroups of five. New members fill the
first available subgroup. The leader appoints assistants; leaders and assistants
can invite, remove non-leaders, move members, swap subgroups, mark targets, and
initiate ready checks. Swaps remain atomic when both subgroups are full. Pending
group invitations retain their original group identity when the inviter leaves;
disband removes those invitations. An invited player cannot create a competing
group before accepting.

Roster packets carry the raid type, each member's subgroup, and the assistant
bit, including the recipient's own flags. Target markers are unique per target;
reassignment clears the previous marker, and roster refreshes and reconnects
resend the current marker list. Ready-check requests reach group members;
responses and offline-member failures reach the leader. The vanilla client
owns the ready-check timer and presentation.

Party chat reaches the sender's subgroup. Raid chat reaches the entire raid;
raid leader chat requires the leader, and raid warnings allow assistants.
The vanilla leader and warning chat types are `0x57` and `0x58`.

Party-area spell targets use the owner's subgroup, including owned pets.
Class-wide raid buffs retain the full raid as their candidate set before class,
range, world, and alive checks. Ordinary quest kills and needed quest-item
projections are suppressed in raids; raid quests remain eligible. Quest-item
eligibility retains the battleground exception. Cast, interaction, exploration,
and turn-in paths retain their existing rules. Membership changes refresh the
quest-item projection through `World.Presence`.

For eligible XP recipients beyond five, the group multiplier follows the local
VMangos formula, `max(1 - count * 0.05, 0.01)`, before the existing level-weighted
distribution. This follows the reference implementation's approximation.

References: local VMangos `GroupHandler.cpp`, `Group.cpp`, `Group.h`,
`Server/Packets/Group.cpp`, `ChatHandler.cpp`, `Chat.cpp`, `SharedDefines.h`,
`Player.cpp`, `QuestDef.cpp`, `Spell.cpp`, and `Formulas.h`, plus the generated
build-5875 spell and quest catalogs.

## Real-client checks

Debugpaladin (GUID 2), Debugbuyer (GUID 10), and Debugbidder (GUID 11) used three
separate accounts and isolated clients in Northshire. The paladin began at level
50 and later used the existing developer commands to reach level 54, learn
trainer spells, and obtain Symbols of Kings. Quests 7 and 33 were added through
the existing developer command. All gameplay changes used client commands or UI
interaction. Tidewave read owner and world state; packet tracing observed the
incoming codecs and outgoing messages with their recipient GUIDs.

| Action | Client evidence | Authoritative evidence |
| --- | --- | --- |
| Cast Devotion Aura with active quests | Paladin remained connected; the aura appeared | Aura 10292 applied, with 620 additional armor; quest state stayed valid |
| Form a three-player party | Both other players appeared in the party frames with Devotion Aura | Three members in group 1, subgroup 0; all three had aura 10292 |
| Convert to raid and appoint Debugbuyer | The raid window showed eight groups, the leader, and the assistant marker | Group ID and loot settings were preserved; roster type became 1 and assistant flags became 128 |
| Assistant moves the mage into Group 2 | Mage's party frames and Devotion Aura disappeared | Subgroup became 1; aura 10292 disappeared; armor fell from 1,088 to 468 |
| Send subgroup, raid, and warning messages | Assistant's warning appeared across the screen; the mage saw raid chat and received a rank error for her warning attempt | Party message recipients were GUIDs 2 and 10; raid and assistant-warning recipients were 2, 10, and 11 |
| Set a skull on the mage | Observer saw the skull overhead and on the target portrait | Marker 7 mapped to GUID 11 and was sent to all three clients |
| Replace and clear the marker, then restore the skull | The client sent each marker operation | Reassignment cleared marker 7 before assigning 6; clearing removed 6; the final map was `%{7 => 11}` |
| Start a ready check; buyer clicks Yes and bidder clicks No | Other clients saw the popup; the leader later saw `Debugbidder is not ready` | Incoming boolean answers were forwarded only to leader GUID 2 |
| Move the mage back into Group 1 | Devotion Aura returned | Aura 10292 and armor 1,088 were restored |
| Assistant swaps herself and the mage between groups | The client sent `CMSG_GROUP_SWAP_SUB_GROUP`; rosters changed | Buyer moved to subgroup 1 and bidder to subgroup 0 in one transition |
| Move both observers into Group 2, then cast Greater Blessing of Wisdom on the mage | Mage received the blessing while outside the paladin's subgroup | Aura 25894 applied across subgroups; aura 10292 remained absent and armor stayed 468 |
| Buyer logs out; leader starts another ready check | Buyer reached character selection; leader saw `Debugbuyer is not ready` | Buyer had no live owner, but retained membership and assistant/subgroup state; the server reported her offline response |
| Buyer logs back in | Raid window retained `(A)` and Group 2; the skull remained visible on the mage | Assistant status, subgroup 1, and `%{7 => 11}` survived; recipient roster flags were 129 |
| Kill a Kobold Vermin while in the raid | Dead target and quest log showed `Kobold Vermin slain: 0/10` | Victim health was 0/42; quest 7 counts stayed empty; needed quest-item projection was empty |
| Leave the raid and kill another Kobold Vermin | Quest log and progress text advanced to `1/10` | Quest 7 count became 1; needed quest item 750 returned |
| New leader leaves the remaining two-player raid | Raid frames, group label, and skull disappeared | All three membership lookups returned nil; group and marker state were removed |

The first run exposed an existing quest crash: completed spells could report
player targets to `QuestLog.increment_cast/5`, whose clauses only accepted
creatures and game objects. The fix returns `:no_credit` for unsupported target
types in both cast and interaction counting. Regressions cover player and pet
targets and mixed player/creature casts, preserving valid creature credit.
The final run repeated the original Devotion Aura trigger successfully.

Automated coverage also verifies all six incoming opcode registrations, exact
marker and ready-check payloads, 40-member capacity, subgroup capacity,
full-subgroup swaps, unauthorized management and chat, ordinary-party markers,
invitation cleanup, owned-pet target filtering, raid-class targets, eligible raid
quests, and XP multipliers. Capacity was tested with deterministic group state;
the live run used three clients. Raid-instance admission and lockouts are
separate from this group milestone.

## Retained evidence

- Final leader: `/home/pikdum/.cache/thistle-wow-playtest.98Be7H`
- Final buyer: `/home/pikdum/.cache/thistle-wow-playtest.N5UqNs`
- Final bidder: `/home/pikdum/.cache/thistle-wow-playtest.daDUWW`
- Leader screenshots: `raid-roster.png`, `ready-check-complete.png`,
  `raid-kill-target.png`, `raid-quest-zero.png`,
  `quest-credit-after-leaving.png`
- Buyer screenshots: `ready-check-popup.png`,
  `reconnect-roster-and-marker.png`, `reconnect-visible-marker.png`,
  `disbanded-marker-cleared.png`
- Bidder screenshots: `party-devotion.png`, `subgroup-aura-removed.png`,
  `raid-chat-and-warning.png`, `subgroup-aura-restored.png`,
  `greater-blessing-across-subgroups.png`, `disbanded-roster-cleared.png`
- Packet trace: `/tmp/thistle-raid-packets.log`
- State samples: `/tmp/thistle-raid-snapshots.log` and
  `/tmp/thistle-raid-state-<phase>.term`
- Dead victim: `/tmp/thistle-raid-victim.log`
- Catalog: `/tmp/thistle-raid-final-catalog.log`
- Final assertions: `/tmp/thistle-raid-final-proof.log`, `accepted: true`
- Final server log: `/tmp/thistle-raid-accepted-playtest.log`
- Gates: `/tmp/thistle-raid-final-all.log`,
  `/tmp/thistle-raid-final-compile.log`, `/tmp/thistle-raid-final-credo.log`,
  `/tmp/thistle-raid-final-format.log`
- Initial crash log: `/tmp/thistle-raid-playtest.log`

No server errors or unsupported-command warnings occurred in the final run.
All clients and the server were stopped, with artifacts retained.
