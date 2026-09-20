# Creature, spell, and Warsong honor acceptance

Build-5875 client acceptance for `27fdba1c`, with follow-up fixes in
`181d2aee`, `274a29ee`, and `fab02d63`. Final gates passed all 3,837 tests,
compilation with warnings as errors, strict Credo, and formatting.

## Creature and spell rewards

Two level-60 Alliance clients formed a party. The paladin learned the existing
Death Touch and Honor Points +25 spells through developer commands, then cast
them through the client. God mode kept the characters alive near hostile NPCs.

| Action | Paladin contribution | Hunter contribution | Kill counters |
| --- | ---: | ---: | --- |
| Cast Honor Points +25 on self | 25 | 0 | No kills |
| Kill Brewmaster Drohn, a gray civilian | 25 | 0 | One DK each |
| Kill Cairne Bloodhoof with both members nearby | 513 | 488 | One HK and one DK each |

The paladin displayed `DK: Civilian` and `HK: Leader`. The hunter dealt no
damage and still received the full 488 leader honor. Its Honor panel showed
one HK, one DK, and 488 weekly contribution. Owner fields and ledger totals
agreed. These zero-rank characters exercised the DK counter and rank floor;
automated tests cover deductions from an existing rank balance.

The leader kill also exposed an XP popup at the player level cap. The fix
skips player XP feedback and rested-XP consumption when no next level exists,
while preserving pet rewards. A fresh client repeated the spell and leader
kill: packet tracing recorded 25 and 488 honor, with no XP packet or popup.

## Warsong captures, victory, and exit

The paladin entered a solo debug invitation through the client's normal Enter
Battle action and started the match using the existing debug command. Each
capture used a real flag click, travel within the same world copy, and client
movement into the capture trigger. Flag respawn timers elapsed normally.

Three captures awarded 396 honor each; victory added 198. A run retaining the
spell and leader awards finished at 1,899 contribution and one lifetime HK.
The scoreboard showed 1,386 bonus honor, three captures, and no battleground
kills. The character received three Warsong marks. The owner, saved character,
and honor ledger agreed, and the flag aura was removed.

Repeated captures exposed a shared spawn-pool bug: event refresh replaced a
game object's database member ID with its runtime instance GUID. The next
flag reset could not find the selected member. Spawn selection now preserves
`Spawn.pool_member`; a runtime regression exercises refresh and three repeated
suspension/resume cycles inside an instance.

The victory screen exposed another bug: scoreboard queries discarded the
winner and ended state. The stock client's `WorldStateFrame.xml` requests
scores during `OnUpdate`, so the next response hid the victory banner and
leave button. Queries now use the same complete scoreboard projection as
pushes, and victory immediately publishes the exit countdown.

A final fresh client repeated all three captures. The screen retained
`Alliance Wins`, the countdown, and Leave Battleground after an explicit score
refresh. Clicking that button returned the player to the original open-world
position. The Honor panel showed 1,386 contribution and zero kills; the ledger
had no victim entries. Match membership and the flag aura were cleared.

## Evidence

- Initial server log: `/tmp/thistle-honor-rewards-playtest.log`.
- Initial paladin: `/home/pikdum/.cache/thistle-wow-playtest.cNUnim`, with
  `honor-civilian-kill.png` and `honor-leader-kill.png`.
- Initial hunter: `/home/pikdum/.cache/thistle-wow-playtest.vJFx5k`, with
  `honor-group-leader-credit.png`.
- XP/respawn follow-up: `/home/pikdum/.cache/thistle-wow-playtest.KEAErS`, with
  `honor-leader-no-xp.png` and `honor-warsong-victory.png`.
  Log: `/tmp/thistle-honor-followup-playtest.log`.
  Packet trace: `/tmp/thistle-honor-followup-packets.log`.
- Final client: `/home/pikdum/.cache/thistle-wow-playtest.I01hNL`, with
  `honor-warsong-victory.png`, `honor-victory-refreshed.png`, and
  `honor-after-warsong.png`.
- Final log: `/tmp/thistle-honor-scoreboard-playtest.log`.
  State probes: `/tmp/thistle-honor-scoreboard-{final,exit}-state.log`.
- Gate logs: `/tmp/thistle-honor-scoreboard-{all,compile,credo,format}.log`.

No entity-owner, honor, battleground, or packet-encoding errors appeared in the
final run. All helper-owned clients and servers were stopped; artifacts were
retained. Runtime state was inspected read-only; setup and gameplay actions
went through the client.
