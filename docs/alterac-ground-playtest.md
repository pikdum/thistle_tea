# Alterac Valley mine supplies and ground assaults

Build-5875 acceptance on 2026-10-05 used fresh local servers and isolated GPU
clients. References were `refs/vmangos/src/scripts/battlegrounds/battleground_alterac.cpp`,
`refs/vmangos/src/game/Battlegrounds/BattleGroundAV.cpp`, and the generated
creature, quest, item, broadcast-text, and waypoint catalogs.

Both quartermasters now accept repeatable mine supply donations, retain their
vendor menus, report supply status, and issue assault orders at Honored
reputation. Alliance needs 280 Irondeep or 70 Coldtooth supplies; Horde needs
70 Irondeep or 280 Coldtooth supplies. Each quest consumes ten items. Either
threshold qualifies; the player does not need both stockpiles.

Taking orders spends both stockpiles and assembles one commander and ten troops
at the authored staging positions. Infantry entry reflects the team's current
armor tier. Inventory planning precedes the serialized stock reservation, so
full bags, a unique order in the bank, and racing selections preserve the
correct shared stock. Air beacons use the same inventory boundary.

Orders retain their catalog uniqueness, fifteen-minute duration, and Alterac
Valley area restriction. Delivering the native automatic quest consumes the
order and launches the exact assembled commander. Launch walks to the rally,
holds for six seconds, then runs with infantry warcries and formation movement.
Complete authored routes retain the final combat home. A quartermaster can
assemble one army per life; additional funded orders can replace a lost or
expired order for the existing assembly. Quartermaster death does not cancel
an already assembled army's delivery. A stale commander's death cannot
invalidate a newer deployment.

## Native acceptance

Level-60 Debugwarrior, Alliance GUID 1, and Debugshaman, Horde GUID 8, entered
Alterac Valley through `.bg join alterac` and the native battlefield-port
action, on separate fresh servers. Existing developer commands supplied level,
godmode, remaining supply items, reputation, travel, and commander damage.
Horde's quartermaster was moved a short distance to make its model accessible.
Repeatable rewards used ordinary NPC right-clicks and a temporary Lua frame
calling the quest APIs on native dialog events. Tidewave probes read owner and
public projection state without mutating gameplay.

| Check | Observed result |
| --- | --- |
| Captured mine loot | Alliance killed Taskmaster Snivvle, acquired Coldtooth Mine, opened its newly friendly supply crate, and clicked the native loot icon. One Coldtooth Supply entered inventory and advanced the accepted quest to 1/10. |
| Repeatable contributions | Seven Alliance Coldtooth rewards and seven Horde Irondeep rewards consumed 70 items each and credited the respective stockpile to 70. |
| Quartermaster presentation | Supply quests, status, and vendor remained available. Alliance opened the actual vendor stock through its gossip option. |
| Reputation gate | Alliance's fresh menu at standing 8,999 offered no orders; closing and reopening at 9,000 exposed the order option. Horde's Honored menu also exposed orders. |
| Assembly | Native gossip issued item 17353 for Alliance or 17442 for Horde, reset both stocks, and produced exactly eleven grouped actors: one commander and ten tier-zero infantry. Infantry waited without an independent route before delivery. |
| Order delivery | Field Marshal Teravaine and Warmaster Garrick displayed their automatic delivery quests. Native completion consumed the order and started the matching assembled commander. |
| Rally | Alliance's sampler recorded walking through the initial points, approximately six seconds at the rally, then running and ten infantry in the formed phase. Both clients displayed their infantry warcries and marching units. |
| Commander death | Native `.damage` killed each commander. Surviving infantry entered the survivor phase and retained group movement. |
| Successive handoffs | After Horde's commander corpse and owner disappeared, Reaver GUIDs ending 19443, 19445, 19449, and 19455 successively led survivors through combat deaths. The last observed survivor retained the complete 55-point route and advanced to waypoint 17. |
| Exit cleanup | Each player left through `.bg leave`. Its old match disappeared, the world contained zero entities, commander and survivor owners were offline, and group membership was empty. Horde's formation projection was also removed. |

The Horde infantry encountered Korrak and suffered combat losses. This run did
not establish that either army survives the entire battlefield or reaches the
enemy base. Both native assemblies used armor tier zero; deterministic tests
cover every infantry tier, orphan movement before rally, final route homes,
both resource thresholds, replacement orders, and quartermaster lifecycle.
The fifteen-minute order expiry was checked against catalog data and existing
item behavior, not observed by waiting for the timer in this run.

## Repair found during acceptance

Formation promotion required the original commander's owner to remain present.
Temporary commanders disappear after their ten-second corpse timeout, so a
later leader death could strand the remaining troops. Promotion now uses the
group's retained original route while still requiring a living, present
successor. A pure regression and a world regression with a genuinely exiting
commander process failed before the fix and passed afterward. Horde's later
native handoffs and resumed route movement verified the repair in gameplay.

WoW's own AMD DRM counters confirmed GPU rendering. Both owned client services
and retained servers were stopped before the final suite. The final Horde
server logged no warning- or error-level entries. Earlier Alliance diagnostic
probe errors and unsupported client Lua calls were corrected during testing;
they did not represent gameplay-owner or network failures.

The final revision passed `mix test.all` (8,782 tests), compilation with warnings
treated as errors, strict Credo with zero issues, formatting, and
`git diff --check`.

## Retained local evidence

- Servers: `/tmp/thistle-av-ground-server1.log` and `/tmp/thistle-av-ground-server2.log`.
- Alliance resources and gate: `/tmp/thistle-av-ground-native-supplied2.txt`,
  `/tmp/thistle-av-ground-native-rep8999.txt`, and `/tmp/thistle-av-ground-native-rep9000.txt`.
- Alliance assembly and timing: `/tmp/thistle-av-ground-native-assembled.txt`
  and `/tmp/thistle-av-ground-native-rally.txt`.
- Horde assembly: `/tmp/thistle-av-ground-horde-supplied.txt` and
  `/tmp/thistle-av-ground-horde-assembled.txt`.
- Horde handoffs: `/tmp/thistle-av-ground-horde-first-promotion.txt`,
  `/tmp/thistle-av-ground-horde-corpse-gone.txt`,
  `/tmp/thistle-av-ground-horde-selected-leader.txt`,
  `/tmp/thistle-av-ground-horde-second-promotion.txt`, and
  `/tmp/thistle-av-ground-horde-resumed.txt`.
- Cleanup: `/tmp/thistle-av-ground-native-alliance-cleanup.txt` and
  `/tmp/thistle-av-ground-native-horde-cleanup.txt`.
- Horde GPU counters: `/tmp/thistle-av-ground-horde-gpu.txt`.
- Screenshots: `/home/pikdum/.cache/thistle-wow-playtest.v2N5Xr/screenshots/`
  and `/home/pikdum/.cache/thistle-wow-playtest.VkbNh7/screenshots/`.
- Checks: `/tmp/thistle-av-ground-focused5.log`,
  `/tmp/thistle-av-ground-promotion-red.log`, and
  `/tmp/thistle-av-ground-{all,compile,credo,format}-final.log`.
