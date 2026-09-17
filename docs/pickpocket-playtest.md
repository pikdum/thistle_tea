# Rogue Pick Pocket

Pick Pocket (921) now opens private loot on living, nonfriendly creatures
whose templates provide a pickpocket loot table. Admission checks require
stealth and reject players, controlled creatures, dead targets, and targets
without pockets. The creature owner checks availability and distance again
when opening and transferring loot.

Pocket loot is independent of corpse loot. The first rogue receives ordinary
items and level-based money; later rogues receive only their own quest drops.
Each rogue's session is retained until respawn, so reopening cannot reroll
money or ordinary items. Party loot methods do not share pocket items or money.
Item transfers use the existing inventory reservation protocol, including
recovery when the receiver disappears. Death closes pocket viewing and blocks
new transfers while existing reservations can finish safely. Respawn waits
for pending transfers and creates fresh pocket state.

The loader preloads pickpocket tables and their item templates at startup.
Gameplay reads cached rows, with no new database queries in the request path.
A Defias Thug now spawns at 16328.2, 16298.1, 69.44 on Programmer Isle, with
a thirty-second respawn, for repeatable testing.

Reference: `Spell::EffectPickPocket`, `Spell::CheckCast`, `Player::SendLoot`,
and spell hit/miss handling in `refs/vmangos/src/game/`.

## Related fixes

The spell loader now preserves the threat-only-on-miss and
failure-breaks-stealth attributes. Successful Pick Pocket casts leave both
units out of combat; resisted attempts break stealth and provoke the target.

Client testing found that generic action-start aura cleanup removed actual
DBC Stealth before Pick Pocket resolved. That cleanup now preserves stealth
for spells allowed while stealthed, while still interrupting invisibility.
The regression test covers preparation using actual Stealth rank 3 data.

Opening another loot source now releases the previous viewer before opening
the new window, preventing old sessions from sending item-removal packets to
a different loot window.

## Automated validation

- `mix test.all`: 3,002 passed after the final code change.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues; commit formatting hooks passed.
- Focused cast, stealth, and DBC tests: 40 passed.
- Tests cover target admission, private ownership within a party, quest-only
  secondary loot, reopening and exhaustion, money consumption, duplicate
  reservations, receiver loss, death during transfer, independent corpse
  loot, respawn, loot-window switching, and successful/resisted casting.

## Real-client acceptance

Used an isolated build-5875 client with Debugrogue (GUID 3), god mode disabled,
and the seeded Defias Thug. Casts and transfers were driven through the client;
read-only owner probes recorded the independent authoritative state.

- Pick Pocket opened a living Thug's loot window with the rogue still stealthed,
  neither owner in combat, no tap, and no corpse loot session.
- Reopening preserved the existing pocket roll.
- After a later respawn, the client displayed 150 copper and a Shiny Red Apple.
  Clicking their loot icons increased money from 100,000,000 to 100,000,150
  and placed one apple (4536) in inventory. The pocket item became looted,
  gold became zero, reservations cleared, and stealth remained active.
- Retrying those emptied pockets returned no new loot or money.
- Sinister Strike killed the same Thug. Its separate corpse window contained
  one copper; taking it increased money to 100,000,151. Previously stolen
  pocket state remained exhausted. Earlier corpse windows also displayed
  independent Darnassian Bleu drops.
- Respawn restored living state and fresh pocket loot. Pocket/corpse separation
  was observed across multiple actual deaths and respawns.
- With the test rogue temporarily lowered to level 1, repeated client casts
  produced a resisted attempt against the level 3 Thug. A read-only timeline
  recorded stealth changing from true to false, both owners entering combat,
  and the Thug selecting GUID 3 as its victim. Health fell from 435 to 433,
  then 431 and 427; the client visibly showed the Thug turning and attacking.
  Money stayed unchanged and the pocket viewer closed.

Party ownership, quest eligibility, receiver failure, and death during an
in-flight reservation were checked automatically, not with additional clients.

Screenshots: `/home/pikdum/.cache/thistle-wow-playtest.Ene6AC/screenshots/`.
Authoritative evidence: `/tmp/thistle-pickpocket-{open,reopened,transfer-icons,empty-retry,corpse-transfer,final-inventory}.txt`.
Failure-path evidence: `/tmp/thistle-pickpocket-{level1-resist,resisted}.txt`
and screenshot `resisted-pickpocket.png`.
Validation: `/tmp/thistle-pickpocket-{all-final,compile,credo,stealth-tests}.log`.
Server log: `/tmp/thistle-pickpocket-server.log`.

Two module hot-load attempts reported `:not_purged` during the stealth fix;
both modules were subsequently purged and loaded successfully before the
successful acceptance checks. No gameplay owner or network exceptions were
observed. The owned client and local server were stopped after acceptance.
