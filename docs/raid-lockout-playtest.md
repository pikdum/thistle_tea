# Raid instance lockouts

Native build-5875 acceptance on September 23, 2026 used two isolated GPU clients,
initially Debugwarlock (6) and Debugpaladin (2), then Debugmage (5). Both WoW
processes used the RX 7900 XT at `0000:0c:00.0`, with increasing DRM graphics
counters. The server used fresh runtime stores.

The implementation follows VMangos `DungeonMap::PermBindAllPlayers`,
`Player::SendRaidInfo`, `Player::SendSavedInstances`, the raid-reset scheduler,
and `CREATURE_STATIC_FLAG_2_LOCK_TAPPERS_TO_RAID_ON_DEATH`. Saves and reset
schedules remain in memory, like the project's other runtime state, and disappear
on server restart. Reset periods come from the cached map template; new schedules
use the reference's 04:00 UTC reset hour and are shared by every copy of a map.

## Boss death and client projection

Both characters reached level 60, obtained Drakefire Amulets, formed a raid, and
entered Onyxia's Lair through area trigger 2848 on map 1. The client sent
`CMSG_AREATRIGGER`; both authoritative positions then used map 249, instance 1.
Neither player had a permanent save before the kill.

The warlock learned the existing Death Touch spell through `.learn 5` and cast
it through the native client at Onyxia. This exercised the ordinary spell,
death-finalization, typed-effect, and instance-owner paths. It was a lockout
acceptance check, not a validation of Onyxia encounter AI or normal raid balance.

Onyxia's authoritative alive flag became false. Both clients received the saved
instance announcement, and both players' saved-raid queries returned map 249,
instance 1 with the same reset countdown. Opening the native Raid Information
window showed "Onyxia's Lair", ID 1, and "Resets in 4 Days 7 Hrs". The client
requested `CMSG_REQUEST_RAID_INFO`, which dispatched to the new handler.

With both players outside, the native `ResetInstances()` request left the save
and copy intact. Disbanding the original raid retained both personal saves.

## Retention, new entrants, and reconnect

At 20:52:45 UTC, copy 1 had no members. It remained saved with its dead Onyxia
owner alive through the five-minute empty-copy lifetime. The original raid was
disbanded and a new raid formed with Debugwarlock leading Debugmage, who had not
been present at the kill. The mage's native Raid Information list was empty
outside, while the group selected copy 1 from its leader's permanent save.

Both players entered through the portal again after five minutes. The mage
received the saved announcement and the same raid ID and countdown on entry.
At 20:58:22, authoritative membership was `[5, 6]` in copy 1. The warlock then
logged out inside and logged back in: at 20:59:34, both the stored world and live
position were again map 249, copy 1, and Onyxia remained dead.

## Expiry and evacuation

The administrative `.instance raid-reset 249` command exercised the same expiry
transition as the scheduled timer. This avoided changing the live clock or
waiting days; deterministic tests separately advance the injected clock to the
real scheduled deadline and verify recurring periods and stale-timer rejection.

The reset cleared the online warlock and mage saves and the offline paladin's
save. Both online players received the native one-minute home-teleport countdown.
The mage left voluntarily; the warlock stayed and was automatically teleported
to the home bind in Northshire. At 21:01:13 UTC, the old instance-copy count was
zero. Re-entering through the portal created unsaved copy 2 with a living Onyxia.

This exposed a pre-existing process leak: the removed copy's hidden corpse owner
remained alive even though its spatial entry was gone. Spawn-pool owners did not
trap supervisor shutdown exits, so their existing termination cleanup was skipped.
The fix enables exit trapping. A regression hides an owned entity from the
spatial index, stops its copy, and verifies that its process stops while another
copy's entity survives. That regression failed before the fix and passed after it.

## Evidence

The final pass after the fixes used fresh runtime stores and GPU sessions
`77koLB` (warlock) and `tid7JT` (mage), with server log
`/tmp/thistle-raid-lockout-final-server.log`. The warlock killed Onyxia in copy 1
while the mage remained outside. Only the warlock received a personal save.
The native `/promote Debugmage` request changed the leader to the unsaved mage:
the group's selected copy became nil, while the warlock retained save 1.

The mage then entered fresh copy 2 and killed its Onyxia. Personal saves were
now 1 and 2 with the same remaining seconds. The warlock's portal entry was
rejected with "Transfer Aborted: instance not found"; authoritative membership
remained nil and the personal save remained 1.

Resetting the raid stopped copy 1's boss process immediately because that copy
was empty. The mage remained in expired copy 2 for the evacuation countdown,
while the warlock entered fresh copy 3. At 21:17:17 UTC, copies 2 and 3 coexisted
and the group's selected copy was 3. At 21:18:22, the mage was home, both old
boss GUIDs resolved to no process, only copy 3 remained, and its Onyxia was alive.
This verifies that delayed cleanup cannot remove the new copy's owner index.

After reset, the native client reported `GetNumSavedInstances() == 0` and disabled
its Raid Info button. Its already-open Raid Information window retained the last
drawn row; closing that window removed the stale presentation. The screenshot
`saved-count-after-reset.png` records both the zero API count and this unmodified
Vanilla UI behavior. The server's saved-raid responses were empty.

Final-pass screenshots include `second-save.png`, `conflicting-save.png`,
`expired-second-copy.png`, and `fresh-third-copy.png`. An early diagnostic tried
the unavailable `PromoteToLeader` Lua function; native `/promote` was then used
successfully.

Automated validation passed 5,295 tests through `mix test.all`, including raid
binding and admission, group formation and leader replacement, reset deadlines,
occupied-copy invalidation, offline save removal, packet layouts and dispatch,
creature flag loading, and hidden spawn-owner teardown. Compilation with
warnings as errors and strict Credo also passed.

- Server log: `/tmp/thistle-raid-lockout-server.log`.
- Warlock session: `/home/pikdum/.cache/thistle-wow-playtest.KLUUBf`.
- Paladin/mage session: `/home/pikdum/.cache/thistle-wow-playtest.VhO3Kz`.
- Warlock `onyxia-death.png` shows the corpse, loot rolls, and saved announcement.
- Warlock `saved-raid-ui.png` shows the native raid ID and countdown after the
  manual reset request.
- Mage `unsaved-new-member.png` and `inherited-save.png` show the transition from
  an empty list outside to the existing save on portal entry.
- Warlock `raid-expired.png` and `evacuated.png` show the countdown and home bind.
- Mage `fresh-raid.png` shows the replacement copy with a living boss.

The simultaneous initial login attempted the warlock twice; the second client
correctly received the already-online rejection before selecting the paladin.
An outside-cave debug teleport used an invalid floor height; both characters were
returned to the known Programmer Isle coordinates before continuing.
The log also contains existing account-data, GM-ticket, and meeting-stone
unimplemented messages from login. No raid-info dispatch or raid-binding failures
occurred.

All four isolated client sessions and both retained server processes were stopped
after acceptance. Screenshots and logs were retained.
