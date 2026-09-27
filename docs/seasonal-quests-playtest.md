# Seasonal quest availability

Quests linked through `game_event_quest` now require their world event to be
active before players can accept them. Permanent NPCs no longer offer holiday
quests year-round. NPC markers, gossip menus, and questgiver game-object
activation refresh through the existing visibility tick when events change.

The quest loader attaches static event IDs before compiling dependencies,
including embedded breadcrumb targets. It loads links through patch 10 and
ignores links to nonexistent events. The current data has 63 valid bindings;
six additional rows refer to the missing event 22 and remain unrestricted,
matching the reference loader's treatment of invalid links.

Quest eligibility receives the active event snapshot from the boundary.
Ordinary NPC acceptance, shared quests, item starters, and quest-availability
conditions use that same pure check. No gameplay database queries or extra
event subscriptions were added.

Stopping an event hides linked start and turn-in entries. Accepted quests,
their progress, and source items remain intact across event changes and
reconnects. Existing progress and reward handlers retain their behavior;
this change does not impose an additional event check on an already-open
reward dialog or the reduced requirements for automatic reward spells.

Reference: VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`GameEventMgr::LoadFromDB`, `GameEventMgr::UpdateEventQuests`,
`Player::CanTakeQuest`, `Player::PrepareQuestMenu`, and the questgiver status
calculation in `QuestHandler.cpp`. The reference toggles availability without
resetting accepted or rewarded quest state.

## Native acceptance

An isolated build-5875 GPU client tested the implementation committed as
`5d67637c`. Debugrogue, GUID 3, visited Orphan Matron Nightingale, entry 14450,
spawn 79806, at `{-8623, 744, 96.86}` on map 0. The matron is a permanent
spawn. Quest 1468, Children's Week, belongs to event 10 and supplies Human
Orphan Whistle 18598. Gameplay actions used native client input and existing
`.debug events start|stop 10` commands. Tidewave probes were read-only.

1. With event 10 inactive, the matron had no quest marker or menu entry.
   Starting the event restored her yellow exclamation mark while the player
   remained stationary. Her process remained the same throughout the test.
2. The player opened the quest's accept dialog, stopped the event, and clicked
   Accept. The client reported unmet requirements. The owner and character
   store had no quest entry, the whistle count remained zero, and the matron's
   projected status was zero.
3. Restarting the event allowed normal acceptance. Both the owner and
   character store contained quest 1468 with complete status, and the
   inventory contained one whistle. The native quest log displayed the quest.
4. Using the whistle summoned Human Orphan, entry 14305. The orphan displayed
   a yellow question mark, projected status 7, and menu entry `{1468, 4}`.
   Stopping the event removed the marker and entry while the orphan stayed
   alive. The native gossip panel still opened, with no quest entry. The
   completed quest and whistle remained intact.
5. Logout removed both player and orphan owners, positions, and metadata.
   Reconnecting created a new player owner with the retained quest and
   whistle while event 10 was still inactive. The native quest log continued
   to display Children's Week.
6. The player summoned another orphan and restarted the event. Its marker
   and turn-in entry returned. Clicking Complete Quest produced the native
   completion message and reputation feedback. The owner recorded quest
   1468 as rewarded and removed its log entry; the whistle remained available
   for the subsequent orphan quests.

## Automated acceptance

- `mix test.all`: 6,846 passed in 69.0 seconds after the final code edit.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues; pre-commit formatting checks passed.

Coverage includes real database links, invalid event references, ordinary
quest eligibility, breadcrumb targets, conditional availability facts,
stationary marker refresh and deduplication, game-object activation, stale
NPC and item dialogs, stale shared offers and monitor cleanup, preservation
of owned starter items, and accepted quest retention across event changes.
Sharing, item starters, and game-object cases were automated rather than
repeated through native clients.

Runtime and checks used
`NAMIGATOR_SRC=/nix/store/3nds85i5fyjgpqcgjnk03fdfgs798vfn-namigator-with-wmo-metadata`.

## Retained evidence and cleanup

Client artifacts are in
`/home/pikdum/.cache/thistle-wow-playtest.usTdLj/screenshots/`.
Useful screenshots are `matron-inactive.png`, `stationary-active.png`,
`accept-dialog.png`, `stale-accept-rejected.png`, `quest-accepted.png`,
`orphan-active.png`, `orphan-inactive.png`, `reconnect-inactive-quest.png`,
`orphan-restored.png`, `orphan-reward-ready.png`, and `quest-rewarded.png`.

Probe and log files use the prefix `/tmp/thistle-event-quests-`:
`stale-proof.txt`, `accepted.txt`, `orphan-active.txt`, `retained.txt`,
`logout.txt`, `reconnected.txt`, `orphan-restored.txt`, `rewarded.txt`,
`cleanup.txt`, `server.log`, `all-final.log`, `compile.log`, and `credo.log`.
The first diagnostic queried a nonexistent inventory field; `stale-proof.txt`
is the corrected probe. An initial Tidewave request timed out during local
compilation; later probes completed normally.

WoW PID 1971263 belonged to the helper's service and used `amdgpu` directly.
Its own graphics counters increased from 3,715,834,309 to 17,623,856,094 ns,
recorded in `gpu.txt` and `gpu-final.txt` under the same temporary prefix.

The server logged the native accept, complete, and reward packets. It had no
errors or gameplay warnings; existing unsupported account-data and GM-ticket
requests were the only warnings.

Event 10 was restored to inactive before the final logout. Player and orphan
owners, positions, and metadata were absent afterward, and the saved reward
remained recorded. The helper stopped service invocation
`e8a12d174eb3430191ce563ca79e6b47`; its unit became inactive with an empty
cgroup and WoW PID 1971263 disappeared. The retained server PTY exited and
ports 4000, 3724, and 8085 were free. All evidence was retained.
