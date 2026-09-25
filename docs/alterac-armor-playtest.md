# Alterac Valley armor donations and troop upgrades

Native build-5875 acceptance on 2026-09-25, with fresh local servers and isolated
GPU clients. The reference behavior comes from
`refs/vmangos/src/game/Battlegrounds/BattleGroundAV.cpp`, its blacksmith gossip
scripts, and the generated quest and spawn catalogs.

This covers armor scraps, supply crates, manual troop upgrades, and General's
Warcry. Other resource turn-ins and player-launched assaults remain unimplemented.
The local mine catalog has only faction population states, so this change does
not invent missing mine troop tiers.

## Native donation and upgrade acceptance

Level-60 Debugmage (Alliance, GUID 5) and Debugshaman (Horde, GUID 8) entered
map 30, instance 1 using `.bg join alterac` and the native **Enter Battle** button.
Existing developer commands supplied levels, godmode, items, reputation, and
travel within the instance. `.bg start` shortened preparation. Quest exchanges
and upgrade selections used the actual client UI and network handlers.

| Check | Observed result |
| --- | --- |
| Blacksmith menu | Murgot Deepforge and Smith Regzar displayed their donation quest alongside the armor-status gossip option. Their questgiver-only NPC flags exercised `CMSG_QUESTGIVER_HELLO`. |
| First donations | Alliance quest 7223 and Horde quest 7224 each consumed 20 Armor Scraps (17422). Each team's stockpile became 20 while its troop tier remained zero. |
| Repeat donations | The mage completed 74 repetitions of quest 6781 after the first donation: 75 completed exchanges consumed all 1,500 supplied scraps. Horde progress remained 20. |
| Missing items | The shaman accepted repeat quest 6741 with no scraps left. The native Continue button was disabled and the stockpile remained 20. |
| Supply crates | At 100 scraps, event 80 selected stage 0. At 400, events 80, 82, 84, and 86 all selected stage 0, with their corresponding live crate GUIDs. At 500 they selected reset stage 2 and the stage-0 GUIDs disappeared. |
| Reputation gate | At 500 scraps and Neutral reputation, Murgot reported sufficient supplies but offered no upgrade. At 1,500 scraps the tier was still zero. Setting Stormpike Guard reputation to 9,000 exposed the Seasoned request. |
| Manual progression | Three separate native gossip selections advanced Alliance through Seasoned, Veteran, and Champion. The cumulative stockpile stayed at 1,500. The final menu reported Champion troops and offered no further upgrade. |
| Opposing observer | The shaman at Stonehearth Graveyard saw the guards replaced on each request. Target frames showed Stormpike Defender level 58, Seasoned Defender 59, Veteran Defender 60, and Champion Defender 61. |
| Buff replacement | The mage held spell 28418 after Seasoned, only 28419 after Veteran, and only 28420 after Champion. Requests were within the preceding buff's two-minute lifetime. Horde received none of these Alliance buffs. |
| Reconnect | The mage logged out and returned to the same match. The stockpile, Champion tier, remaining buff, and Champion blacksmith menu survived. The buff later expired normally. |

At the three upgrade probes, the loaded Alliance defender counts were respectively
12 of entry 13326, 12 of 13331, and 12 of 13422, with no earlier-tier entries
remaining. Horde retained 12 baseline defenders (12053). Graveyard events
15, 16, and 17 advanced through states 1, 2, and 3; Horde events 19, 20, and 21
remained at state 4.

The repeat exchanges used a temporary client frame to call `AcceptQuest`,
`CompleteQuest`, and `GetQuestReward(0)` on their corresponding quest events.
NPC interactions and quest-row selection remained native clicks. Server telemetry
recorded the accept, request-reward, and choose-reward packets. No runtime probe
mutated a stockpile, tier, inventory, reputation, or spawn event.

## Bugs found and repaired

The first native attempt exposed the blacksmith's questgiver-only hello route:
the generic gossip route worked, but ordinary right-clicks bypassed it. Questgiver
hello now includes the battleground menu, with a packet regression.

The quest integration tests exposed a queue teardown race. A new join or instance
list request could reach a stopped match before the manager processed its monitor
notification. Discovery now ignores stopped or empty matches, and final departures
retire their indexes promptly. A deterministic test queues requests before the
monitor notification rather than relying on scheduling luck.

The final native run also exposed an invalid queue cancellation removing an active
player's index while leaving the match roster intact. VMangos treats action 0 as
queue cancellation, not an active-match exit. The shared cancellation path now
releases queued players and invitations while preserving admitted members.

## Final lifecycle acceptance

A fresh server at `acb9bc54` repeated native admission and an Alliance donation.
`AcceptBattlefieldPort(1, 0)` sent the cancellation packet while the mage was
inside. Membership remained active, the blacksmith menu still worked, and the
subsequent donation credited 20 scraps.

The existing `.bg leave` command exercised the normal player leave boundary and
returned the mage to Programmer Isle at `{16303.2, 16318.1, 69.44}`. The match
lookup was nil, the instance had zero entities, reservations were empty, and its
spawn-event row was gone. A second native admission created instance 2 with both
teams at zero scraps and tier zero. Leaving again removed both worlds completely.

This final cleanup proof uses the existing developer leave command. Earlier
`LeaveBattlefield()` calls during the active match sent no leave packet; attempted
portal setup positions placed the clients below terrain. Those attempts are not
claimed as native exit-portal acceptance. The previous objective acceptance
separately covers the post-victory **Leave Battleground** button.

## Automated verification and evidence

The final source revision passed `mix test.all` (5,990 tests), compilation with
warnings treated as errors, strict Credo, formatting, and `git diff --check`.
Coverage includes both factions and all thresholds, failed inventory commits,
duplicate rewards, wrong faction and world, insufficient reputation, stale upgrade
requests, contested or destroyed nodes, later defender population, exclusive
Warcry ranks, queue cancellation, and teardown ordering. Database checks use the
appropriate integration tags.

No error-level or spell-validation failures appeared in either final native run.
The existing login warnings were `CMSG_UPDATE_ACCOUNT_DATA`,
`CMSG_GMTICKET_GETTICKET`, and `CMSG_MEETINGSTONE_INFO`. WoW's own DRM counters
confirmed `amdgpu` rendering in each helper-owned service. All clients and servers
were stopped through their recorded ownership paths.

Retained local evidence:

- Upgrade run: `/tmp/thistle-av-armor-native-server.log`,
  `/tmp/thistle-av-armor-native-*.txt`, and `/tmp/thistle-av-armor-native-gpu.log`.
- Alliance screenshots: `/home/pikdum/.cache/thistle-wow-playtest.itmmaG/screenshots/`.
  Key images are `blacksmith-menu`, `scraps-500-neutral`, `seasoned-ready-menu-2`,
  `veteran-ready`, `champion-ready`, `champion-complete`, and `champion-reconnect`.
- Horde screenshots: `/home/pikdum/.cache/thistle-wow-playtest.8Rvp0j/screenshots/`.
  Key images are `booty-reward`, `insufficient-scraps`, `guards-baseline-ground`,
  `seasoned-observer`, `veteran-observer`, and `champion-observer`.
- Lifecycle run: `/tmp/thistle-av-armor-cleanup-server.log`,
  `/tmp/thistle-av-armor-cleanup-*.txt`, `/tmp/thistle-av-armor-cleanup-gpu.log`, and
  `/home/pikdum/.cache/thistle-wow-playtest.LmWfnJ/screenshots/`.
- Final gates: `/tmp/thistle-av-armor-cancel-{tests,all,compile,credo}.log`.
