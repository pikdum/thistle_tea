# Instance group membership

Leaving or being removed from an instance's group starts a 60-second grace
period. The native client displays the destination and countdown. Rejoining
the owning group cancels it. Expiry rechecks membership, then uses normal
world travel to return the player to their home bind.

`Instance` owns copy ownership and bindings. Creating a group adopts its
leader's solo copies. Disbanding marks the group's copies as orphaned while
preserving occupants and progress; a newly formed group can adopt its leader's
orphaned copy. A different active group's copy cannot be claimed this way.
Normal entry selects the current owner rather than a stale personal binding.

`Instance.Eviction` owns the pure deadline rule. `Player.Instances` owns the
timer, client reminder, and home transfer. Group mutations update their ETS
projection before notifying the instance boundary. Players recheck eligibility
after world entry and group changes. Repeated notifications retain the same
deadline. Token checks reject stale callbacks, and world travel or logout
cancels the timer.

Login resumes an eligible saved copy. A missing copy, lost ownership, or other
admission failure returns the player home; it does not create a new copy at the
saved dungeon coordinates. Open worlds and battlegrounds are excluded from
these countdowns. Permanent raid saves remain a separate unimplemented system.

The behavior references are VMangos `Group::_homebindIfInstance`,
`Group::_addMember`, the group-join binding checks, and
`Player::UpdateHomebindTime`. The latter supplies the 60-second timer and
`SMSG_RAID_GROUP_ONLY` reminder cancellation.

## Native acceptance

A fresh server and three isolated build-5875 GPU clients used Debughunter,
Debugbuyer, and Debugbidder. Runtime probes were read-only. The third client
joined the group and then disconnected, leaving a three-member roster for the
kick checks.

- The hunter entered Ragefire Chasm through open-world area trigger 2230,
  creating map 389, copy 1, owned by player 7. Forming a party adopted that
  same copy for party 1. The buyer entered through the same portal and saw
  the hunter inside; both owner states and copy membership agreed.
- Removing the buyer displayed the native countdown to Elwynn Forest.
  Reinviting and accepting removed the countdown. The buyer remained in copy
  1 with no timer after the original deadline had passed.
- A second removal was allowed to expire. The buyer appeared at the Northshire
  home bind on open map 0, at `{-8949.95, -132.493, 83.5312}`. The timer and
  current instance membership were cleared; the hunter remained in copy 1.
- After rejoining and returning through the portal, disbanding the party
  started countdowns for both players and marked copy 1 as orphaned. Reforming
  the party adopted the same copy for party 2 and canceled both countdowns.
- The buyer logged out inside the dungeon. After the remaining player left
  the group, reconnect placed the buyer at Northshire with no group, timer, or
  instance membership. No replacement dungeon copy was created.
- The hunter's final countdown expired at the Coldridge Valley home bind on
  open map 0, at `{-6240.32, 331.033, 382.758}`. A read-only sampler observed
  the transfer 241 ms after the deadline (60.241 seconds after timer start).
  Owner state and world presence agreed; the timer was cleared and copy 1 had
  no remaining members. The sampler exited normally.

The actual WoW processes had increasing AMD GPU engine counters. The server
log contained no error-level entries. All three helper units and the retained
server were stopped before the final automated gates.

Evidence is retained in `/tmp/thistle-instance-membership-*.txt`,
`/tmp/thistle-instance-membership-server.log`, and screenshot directories under
`/home/pikdum/.cache/thistle-wow-playtest.uurlcC/` (hunter),
`/home/pikdum/.cache/thistle-wow-playtest.vMsLY8/` (buyer), and
`/home/pikdum/.cache/thistle-wow-playtest.oLabrT/` (third group member).

Automated tests cover ownership adoption without losing progress or entry
history, competing bindings, active-group isolation, disbanding and reforming,
raid eligibility, the real party-to-instance notification path, exact timer
boundaries, reinvite cancellation, stale callbacks, single expiry delivery,
world transfer and logout cleanup, and login recovery.

Final validation: `mix test.all` passed all 4,976 tests;
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix format --check-formatted`, and `git diff --check` passed.
