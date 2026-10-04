# Alterac Valley world-boss offerings and rituals

Build-5875 acceptance on 2026-10-04 used fresh local servers and two isolated
GPU clients. The behavior reference is
`refs/vmangos/src/scripts/battlegrounds/battleground_alterac.cpp`,
`refs/vmangos/src/game/Battlegrounds/BattleGroundAV.cpp`, and the generated
quest, waypoint, game-object, and spell catalogs.

This slice implements Storm Crystals and Stormpike Soldier's Blood donations,
the summoners' escorted journeys, ten-player rituals, and Ivus and Lokholar's
combat scripts. Air strikes, cavalry, and ground assaults remain future work.

## Native donations and scripted journeys

Level-60 Debugpaladin (Alliance, GUID 2) and Debugshaman (Horde, GUID 8) entered
Alterac Valley instance 1 through `.bg join alterac` and the native **Enter
Battle** button. Existing developer commands supplied levels, godmode, items,
and travel within the admitted instance. `.bg start` shortened preparation.
Quest rewards used native NPC interactions and a temporary client frame calling
`CompleteQuest()` and `GetQuestReward(0)` on their quest events.

| Check | Observed result |
| --- | --- |
| Donation menu | Renferal and Thurloga presented their quests and the current offering-status gossip through ordinary NPC right-clicks. |
| First exchange | A five-item donation consumed five items, credited five offerings and five faction reputation, and left the opposing team unchanged. |
| Thresholds | The native status menu was checked at zero and 100 offerings. At 200, the team's launch flag became true and its summoner departed. Automated tests also cover the 160-offering text. |
| Both teams | Each native client made forty five-item exchanges, reaching 200 crystals or blood through the normal reward boundary. |
| Escort travel | Summoners and escorts mounted, followed their authored routes, dismounted near the altar, and began Invocation (11206). |
| Alliance arrival | Renferal reached authored waypoint 49 at approximately `{-199.64, -342.7, 7.15}` and created the Circle of Calling (178670). |
| Horde arrival | Thurloga reached the altar and created the Altar of Summoning (178465); her phase was invoking and her channel was 11206. |

## Ritual participation and completion

Each ritual used one native client and nine headless player sessions. The helpers
were normal player owners admitted to the same match, with ordinary
`CmsgGameobjUse` input for participation; their connection processes discarded
outbound packets. This is not acceptance with ten native clients. Runtime probes
read counters, channels, positions, phases, and entity counts; they did not
advance the rituals or directly spawn either boss.

The native Alliance player clicked the circle and jumped. Her participant entry
and channel were removed. Clicking again and adding eight helpers left nine
participants, an active Invocation channel, and zero Ivus entities. The ninth
helper completed the ritual. The circle disappeared, all ten channels cleared,
and exactly one Ivus appeared.

The Horde native player likewise clicked her altar and channeled Invocation.
Eight helpers left nine participants without completion. The ninth helper
produced exactly one Lokholar, removed the altar, and cleared all ten channels.
Thurloga advanced to the completed phase and stopped channeling. Her ten-minute
cleanup was scheduled; this run did not observe its expiry. Renferal's shorter
cleanup completed, and she later returned at her seed location without a channel.

Completion spells 21249 and 21648 contain `send_event` in the DBC, and VMangos's
preloaded spell overrides add `summon_wild`. Boss creation stays in the shared
spell path; the
forwarded event only ends the NPC ceremony. The spell's radius and orientation
place the initial boss away from the altar, matching VMangos's summon geometry.
Adding a second scripted summon was caught and removed before the final run.

Ivus followed his route to the forward objective near
`{-1066, -374.54, 52.34}`, stopped marching, and retained that location as his
combat home. Against the Horde native client, authoritative aura state confirmed
Faerie Fire (21670), Entangling Roots (20654), and Moonfire (21669); native
screenshots captured the encounter. Lokholar spawned through the Horde ritual
and later died in the active battlefield. His complete march, player-kill Swell
stacks, and every combat spell were not verified with native input in this run.
Automated tests cover the boss kits, player-only kill trigger, route objectives,
and waypoint arrival behavior.

Idle native clients eventually entered AFK and left the battleground with
Deserter through the existing AFK departure boundary. This is separate from
ritual cancellation. Final server logs contained no error- or warning-level
entries. WoW's own `amdgpu` DRM counters confirmed GPU rendering. Both owned
client services and the retained server were stopped after acceptance.

## Bugs repaired during acceptance

- Authored waypoint paths could finish at a mesh-clipped endpoint without
  reaching their script point. Waypoint and home shortcuts now retain the path
  and finish at the authored destination, including empty-path fallback.
- A zero object despawn duration prevented Invocation from channeling while
  still counting participants. Nonpositive despawn durations now use the
  animation spell's channel duration.
- An unowned ritual altar sent its NPC creator a player-only channel-start
  command. Only player-owned rituals now register that channel ownership.
- Type-18 ritual interactions now enforce the existing range, world, living
  player, and faction checks used by equivalent interactable objects.

## Automated coverage and retained evidence

Tests cover both offering thresholds, failed and duplicate quest rewards,
matching-instance launch delivery, summoner phases, repeated and dead completion
events, unowned altar creation, ten distinct participants, channel durations,
interaction guards, clipped waypoint paths, boss combat kits, and catalog
compatibility. VMangos and DBC checks use separate integration tags.

The final revision passed `mix test.all` (8,689 tests), compilation with warnings
treated as errors, strict Credo with zero issues, formatting, and
`git diff --check`.

Local evidence:

- Final native server: `/tmp/thistle-av-assault-single-boss-server.log`.
- GPU counters: `/tmp/thistle-av-assault-gpu.log`.
- Alliance images: `/home/pikdum/.cache/thistle-wow-playtest.4fDemF/screenshots/`,
  including `single-boss-circle-ready` and `single-ivus`.
- Horde images: `/home/pikdum/.cache/thistle-wow-playtest.8Zncgs/screenshots/`,
  including `horde-rune-channel`, `ivus-combat`, and `ivus-melee`.
- Headless setup: `/tmp/thistle-av-helpers.exs` and
  `/tmp/thistle-av-horde-helpers.exs`.
- Final checks: `/tmp/thistle-av-assault-focused-final.log` and
  `/tmp/thistle-av-assault-{all,compile,credo}-final.log`.
