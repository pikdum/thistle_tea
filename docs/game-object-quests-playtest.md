# Game-object questgivers and gossip acceptance

Build 5875, September 21, 2026. Relations and interaction bounds: `a3868c9f`;
quest and gossip integration: `663b9d71`; per-player activation: `2fd26946`;
gossip script ownership and player casting: `6d8ac1e8`.

All 4,083 tests pass, along with compilation with warnings as errors, strict
Credo, and formatting. The client evidence contains 46 passing assertions.
Repository edits, builds, tests, and commit hooks ran only with the playtest
clients and servers stopped.

## Behavior and ownership

Quest loading now includes the 262 game-object starting relations and 209
ending relations in the current VMangos data. These cover 239 distinct object
entries, all questgiver type 2. Typed relation keys keep objects separate from
creatures with the same entry number. Details, acceptance, turn-ins, rewards,
source items, and automatic follow-up quests use the existing quest systems.

`Player.QuestGiver` validates live presence and the same world. Acceptance and
interaction also check the player's state and interaction range. Object range
uses cached display bounds, scale, and quaternion rotation, with an origin
distance fallback for displays without bounds. The equivalent creature path
checks questgiver flags, life state, hostility, and range. Reward lookup keeps
VMangos's separate presence checks rather than imposing the acceptance range.

Object use honors disabled-interaction and immunity restrictions, removes
auras interrupted by looting, and applies the object's mounted-use policy.
Objects with custom gossip menus use their cached menus and conditions.
Selections bind to the original object GUID and recheck live interaction and
conditions. NPC-only services are excluded from object gossip.

`World.Visibility.QuestGivers` projects the activation bit for each recipient
in `Player.PacketSink`, including batched updates. The existing 500 ms visibility
tick reevaluates visible questgivers and sends updates only when eligibility
changes. This covers quest, inventory, level, and condition changes without
changing shared object state. Removed objects are forgotten, and reconnects
rebuild the projection.

Game-object gossip scripts start on the player with the object as target,
matching VMangos; creature gossip scripts retain the creature source. Normal
scripted player casts emit a typed `ScriptedCast` effect through
`EventSink.Context` to the player owner and use `Player.Spellcasting`. They
retain cast times, validation, busy-cast handling, explicit interruption, and
the normal completion path. Triggered casts retain their existing semantics.
Objects without a unit cannot enter the unit casting path.

Reference code: local VMangos `Objects/GameObject.cpp`, `Objects/Object.cpp`,
`Objects/Player.cpp`, and `Handlers/QuestHandler.cpp`.

## Real-client checks

Debugpaladin (GUID 2, level 50) used isolated clients restricted to CPU cores
0–3. Teleports, `.additem 1357`, `.addquest 4296`, and `.tgm` prepared fixtures;
quest and gossip actions used native client controls. God mode prevented
nearby creatures from killing the character during observation. It was turned
off during cleanup.

The poster and treasure-chain run used `2fd26946`. The corrected tablet run
used a fresh server at `6d8ac1e8`. Packet traces, screenshots, item stores,
world projections, and narrow owner-state snapshots were compared separately.
Live character snapshots use the entity owner because `CharacterStore` can
lag changes such as mounting until the next save.

| Action | Client evidence | Authoritative evidence |
| --- | --- | --- |
| Open Wanted Poster (68), then decline | Native Wanted: “Hogger” details opened and closed | No quest or inventory change |
| Reopen and accept quest 176 | Quest appeared in the log | Incomplete quest 176; the visible poster's activation changed from 1 to 0 |
| Abandon and reopen without moving | Native abandonment removed the quest; details opened again | Empty log; activation returned to 1 |
| Accept Captain Sander's Treasure Map (1357) | Native item quest dialog accepted quest 136 | Starter consumed; quest 136 complete |
| Use Captain's Footlocker (35) | Reward dialog followed automatically by quest 138 details | Quest 136 rewarded, 58 XP, quest 138 accepted, one clue 1358, footlocker deactivated |
| Use Broken Barrel (36) | Reward dialog followed by quest 139 details | Quest 138 rewarded, another 58 XP, one clue 1361, barrel deactivated |
| Log out and reconnect at the barrel | Quest 139 and both clues returned | Same quest, reward history, item GUIDs, counts, and slots; inactive barrel rebuilt |
| Use Old Jug (34) | Reward dialog followed by quest 140 details | Quest 139 rewarded, another 58 XP, one clue 1362, jug deactivated |
| Use Locked Chest (33) | Native reward panel and four item messages | Quest 140 rewarded; 115 XP and 800 copper; exactly one each of 2842, 3342, 3344, and 3343; chest deactivated |
| Use Tablet of the Seven (169294) with quest 4296 | “Transcribe the tablet.” appeared in gossip menu 2187 | Incomplete quest; only option 0 offered |
| Select transcription | Transcription submenu appeared; transcript creation and objective completion were visible | Script 218700 cast spell 15065; one item 11470; quest complete |
| Reopen the tablet | The transcription option disappeared | No offered options and no duplicate transcript |
| Abandon quest 4296 | Quest and transcript disappeared | Empty log; item 11470 destroyed; ordinary inventory preserved |
| Finish cleanup and log out | Ordinary backpack and character-selection screen | No active player owner; saved quest log empty and inventory unchanged |

The Sander chain awarded exactly 289 XP and 800 copper. Its clues are not
required turn-in items and remain after rewards; the three clues and four
reward items were explicitly deleted during fixture cleanup. Ordinary
equipment, food, water, and Hearthstone GUIDs, counts, and slots were retained.

Useful map-0 interaction positions:

| Object | Database GUID | Character position |
| --- | --- | --- |
| Wanted Poster | 26843 | `-9671, 683, 38` |
| Captain's Footlocker | 32338 | `-10518, 2113, 6` |
| Broken Barrel | 31937 | `-10519, 1601.6, 46.1` |
| Old Jug | 32325 | `-9800, 1592, 43` |
| Locked Chest | 31935 | `-9798.3, 2110.6, 14.5` |
| Tablet of the Seven | 2 | `-7830.7, -1848.9, 134` |

Allow the client to load terrain and settle before interaction. The mounted
vanilla client suppressed poster-use requests; the live dialog checks used
manual dismounting. Server-side mounted-use rules have automated coverage.

## Bugs found and fixed

The initial poster run found that the server accepted interaction but the
client could not use the object: its activation field was always zero.
Per-recipient activation fixed this. Automated tests also cover two viewers
with different eligibility, live condition changes, incomplete and complete
turn-ins, failed quests, and removal/recreation.

The first tablet run reached gossip but its script ran on the object and
entered a mob-only casting function. Correcting the script source exposed the
missing normal player-script casting path, which now uses the existing player
spellcasting boundary. The fresh tablet run had no script, owner, movement,
visibility, or network errors. Its only warnings were the existing unsupported
account-data, raid-info, GM-ticket, and meeting-stone requests at login.

Retained local evidence:

- Poster and chain screenshots: `/home/pikdum/.cache/thistle-wow-playtest.1mz8N4/screenshots/`.
- Corrected tablet screenshots: `/home/pikdum/.cache/thistle-wow-playtest.45ZRjB/screenshots/`.
- Packet traces: `/tmp/thistle-go-quest-chain-packets.log` and `/tmp/thistle-go-quest-packets.log`.
- Corrected tablet server log: `/tmp/thistle-go-quest-tablet-fixed-playtest.log`.
- Assertion script and output: `/tmp/thistle-go-quest-proof.exs` and `/tmp/thistle-go-quest-proof.log`.
- Serialized snapshots: `/tmp/thistle-go-quest-state-*.term`.

All helper-owned clients and retained server PTYs were stopped. Nothing was
pushed or deployed.
