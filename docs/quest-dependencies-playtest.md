# Quest dependencies and profession eligibility

Build 5875, September 21, 2026. Dependency rules: `e37f8168`; live NPC status
refresh: `0fb573a4`; client-helper cleanup race: `e8be7cc8`.

All 4,110 tests pass, alongside compilation with warnings as errors, strict
Credo, and formatting. The accepted client evidence contains 87 passing
runtime assertions across 22 phases. Repository edits, builds, tests, and
commit hooks ran with the playtest clients and servers stopped.

## Shared eligibility rules

`Logic.QuestGraph` compiles the complete quest catalog at the loader boundary.
Immutable templates contain the relationships needed at runtime; eligibility
does not query Mangos or traverse a mutable global catalog.

- Positive prerequisites require a reward; negative prerequisites require a
  current quest. Reverse `NextQuestId` links supply alternative prerequisites.
- Positive exclusive groups prevent taking competing active or permanently
  rewarded choices. Failed alternatives do not block. Repeatable rewards
  retain their separate semantics.
- Negative exclusive groups require every member in the prerequisite's
  requested state, matching the reference's ordered prerequisite evaluation.
- Immediate previous and next chain links prevent overlapping chain steps.
- Breadcrumbs require available targets, including transitive targets and
  their required conditions. Outstanding dependent breadcrumbs block targets.
  Missing or cyclic breadcrumb paths fail closed; ordinary dangling previous
  links follow the reference loader's omission behavior.
- Profession requirements use the current skill plus temporary and permanent
  bonuses. Bonuses do not grant an unknown skill. A configured required rank
  of zero still passes without training, matching VMangos `GetSkillValue`.

NPC dialogs, NPC/game-object/item acceptance, sharing, game-object activation,
and quest-availability conditions use the same pure requirements. Acceptance
rechecks current state after a dialog or sharing offer. Required conditions
for breadcrumb targets are gathered at the player boundary. Nested required
conditions inside `QUEST_AVAILABLE` preserve the existing explicit unknown
result instead of silently passing.

Unavailable dependencies and skills suppress low-level quest markers. Active
turn-ins remain usable independently of start requirements. Abandoning a
parent prevents new chapter acceptance without deleting an accepted chapter.

The current 4,433-template catalog includes 44 negative prerequisites, 368
nonzero next-quest links, 308 quests in positive exclusive groups, 122 in
negative groups, 144 profession requirements, and 23 breadcrumbs.

Reference: local VMangos `Objects/Player.cpp` (`CanTakeQuest`,
`CanSeeStartQuest`, `SatisfyQuestPreviousQuest`, exclusive-group, chain,
breadcrumb, and skill checks), `Objects/Player.h` (`GetSkillValue`), and
`ObjectMgr.cpp` (quest relationship construction).

## Client acceptance

Debugpaladin (GUID 2, level 50) exercised dependencies at `e37f8168`.
Debugwarrior (GUID 1, level 50) exercised Cooking, including a fresh server
and client after `0fb573a4`. Both isolated clients used private Wine prefixes
and Xvfb displays and were restricted to CPU cores 0–3.

Teleports and `.addquest 583` prepared the Green Hills prerequisite. The
paladin used god mode during observation and disabled it before logout.
Quest acceptance, abandonment, and rewards used native client controls.
Cooking was trained through Stephen Ryback; `.debug professions` then raised
the trained skill to 300. An initial `.learn 2550` fixture only granted the
spell, so profession acceptance was repeated with a fresh character and the
real trainer. Tidewave inspected selected owner/store fields without changing
gameplay state.

| Transition | Client result | Authoritative result |
| --- | --- | --- |
| Reward Welcome to the Jungle (583) | Barnil offers Green Hills, without chapters | 583 rewarded; 338 eligible; 339–342 locked |
| Accept Green Hills (338) | All four chapter offers appear | Current-parent requirement passes |
| Accept Chapter I, abandon Green Hills | Chapter I remains as a turn-in; II–IV disappear | 339 stays active; 340–342 reject the missing prerequisite |
| Accept They Call Him Smiling Jim (1282) | Vincent hides James Hyal (1302) | Exclusive-group rejection |
| Abandon 1282, then accept and reward it | 1302 first reappears, then stays hidden after the reward | Abandonment clears the choice; rewarded history preserves it |
| Accept Malin's Request (690) | Kryten hides Worth Its Weight in Gold (691) | Outstanding breadcrumb blocks the target |
| Abandon 690, accept 691 | Target offer returns; Malin's offer disappears | Target activation blocks the breadcrumb |
| Abandon 691, accept and reward 690 | Malin's offer returns; rewarding it exposes Kryten's target | Target eligible after breadcrumb reward |
| Train Cooking to 1/75 | Chef Grual has no Seasoned Wolf Kabobs offer | Skill requirement rejects quest 90 |
| Raise Cooking to 300/300 on the fixed server | Marker and native quest details appear without reconnecting | Eligibility passes; delivered status changes from 0 to 5 |
| Accept 90, logout, reconnect | Quest and incomplete marker remain | Active quest, skill, and saved character agree; status 3 |
| Abandon 90 | Offer and available marker return | Empty quest log; eligibility passes; status 5 |

The paladin's rewarded history and chapter/exclusive restrictions survived a
separate logout/reconnect. Final cleanup left the characters offline and the
fixed run's quest log empty. Exact skill thresholds, negative bonuses,
repeatable/failed states, alternate prerequisites, all-of groups, malformed
graphs, stale offers, item starters, and object activation have automated
coverage. The live Cooking transition used ranks 1 and 300; the exact 49/50
threshold is covered by pure tests.

Malin also has a preexisting required condition that rejects an active target.
The probe checks that condition result and separately verifies the compiled
breadcrumb dependency; it does not rely on an incidental error-priority match.

## Refresh bug found and fixed

The first Cooking run reached authoritative eligibility at rank 300, but Chef
Grual remained noninteractive in the client. A packet trace showed no quest
interaction from clicks. Reconnecting immediately restored the marker and
quest details, confirming stale client availability.

`World.Visibility.QuestGivers` now refreshes visible creature statuses during
the existing 500 ms visibility tick. `Player.PacketSink` remembers delivered
statuses per viewer, including ordinary query replies, so unchanged statuses
are not resent. Removal clears the cache, queued packets check source
visibility, and removing the NPC questgiver flag clears its old status.
Game-object activation retains its existing projection path.

The fresh Cooking run proved the correction without movement or reconnect
between raising the skill and opening the quest. No owner, network,
visibility, quest, or script errors occurred. The server warnings were the
existing unsupported account-data, raid-info, GM-ticket, and meeting-stone
requests at login. A harmless process-exit race in client cleanup was also
fixed while preserving its failure return value and PID identity checks.

Retained local evidence:

- Dependency screenshots: `/home/pikdum/.cache/thistle-wow-playtest.hiUgGV/screenshots/`.
- Fresh refresh-fix screenshots: `/home/pikdum/.cache/thistle-wow-playtest.CSZBYg/screenshots/`.
- Server logs: `/tmp/thistle-quest-deps-server.log` and `/tmp/thistle-quest-deps-fixed-server.log`.
- Packet summaries: `/tmp/thistle-quest-deps-packets.log` and `/tmp/thistle-quest-deps-fixed-packets.log`.
- Accepted assertion manifest and output: `/tmp/thistle-quest-deps-proof.exs` and `/tmp/thistle-quest-deps-proof.log`.
- Individual read-only snapshots and assertions: `/tmp/thistle-quest-deps-<phase>.exs` and matching `.log` files listed by the manifest.

All helper-owned clients and retained server PTYs were stopped. Nothing was
pushed or deployed.
