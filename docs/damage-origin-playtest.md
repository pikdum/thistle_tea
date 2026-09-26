# NPC-assisted creature kill rewards

Implemented and checked against VMangos `8f4e60845`, with native build-5875
acceptance on September 25–26, 2026.

## Rules and ownership

`DamageOrigin` records damage after mitigation, absorption, and sharing, including
overkill. Player-controlled pets, guardians, totems, and charmed units count on
the player side; an NPC-controlled player counts on the NPC side. Self-inflicted
creature damage also counts on the player side, matching `Unit::DealDamage`.
Combat snapshots use the shared pure `ControlOwner` resolver.

A normal creature permits loot only when player damage is strictly more than
35% of total damage. Exactly 35% and no recorded damage are ineligible. Eligible
kills multiply base XP by the player contribution; the final base reward rounds
to the nearest integer, with ties to even, before party distribution. Creatures
with `CREATURE_STATIC_FLAG_CORPSE_RAID` bypass these restrictions.

Damage history survives death for XP and corpse preparation. Engagement reset,
evade, and respawn clear it; changing victims and healing do not. Death clears
an ineligible tap through `Engagement`, and corpse preparation creates no loot
session or party loot rotation. Soul Shard eligibility uses the lethal damage
history before death removes auras. As in VMangos, an ineligible kill still
allows solo quest/reputation credit for a player controlling the killing blow;
an NPC killing blow does not reward the earlier tagger.

Reference locations: `Objects/Creature.h` damage-origin helpers,
`Objects/Unit.cpp` damage counting and `Kill`, and `Formulas.h` kill XP rounding.

## Native setup

Fresh local server and GPU client session:
`/home/pikdum/.cache/thistle-wow-playtest.iCenye`.
Debugbidder was a level-50 Human Mage, GUID 11, with zero initial XP.
God mode protected the Mage without changing outgoing damage.

The developer seed places a Stormwind City Guard, entry 68 / low GUID 992400,
at `{16123.2, 16218.1, 69.444}` on map 451. A Skeletal Flayer, entry 1783 /
low GUID 992401, stands 45 yards east. Its 30-second respawn resets its 2,880
health and contribution history; its guaranteed loot is one Minor Healing
Potion (118) and 17 copper. Its full level-50 XP reward is 295.

The Mage started at `{16148.2, 16218.1}`, targeted the nearest enemy, cast
Fireball, and used native backward keyboard movement to pull it into the guard's
aggro range. The guard fought through its ordinary AI. Tidewave reads observed
owner state and public projections; they did not mutate gameplay state.

## Acceptance

| Encounter | Player damage | NPC damage | Client and owner result |
| --- | ---: | ---: | --- |
| Rank-1 Fireball tag, guard finish | 24 | 3,038 | XP remained 0; corpse tap, loot session, loot projection, and lootable flag cleared. |
| Three full-rank Fireballs, guard finish | 1,452 | 1,561 | 142 XP, matching `round(295 * 1452 / 3013)`; tap retained and loot window showed the full potion and 17 copper. |
| Next life, entirely player damage | 2,967 | 0 | Full 295 XP; client and owner total increased from 142 to 437. |
| Repeated assisted kill and immediate collection | 1,483 | 1,423 | 151 XP, total 588; native clicks collected the potion and 17 copper. |

The guard's lethal overkill remained in the NPC total. A preliminary teleport
ended the encounter and returned the Flayer to full health with zero totals;
the accepted guard encounters used keyboard movement. Each sampled respawn
also had zero totals, no tap, and no previous loot session. The unassisted kill
proves the prior NPC contribution did not reduce the next life's XP.

The first assisted loot window was inspected successfully, but its short
respawn expired before collection was verified. Collection was repeated with
immediate native loot-window clicks rather than treating that first window as
proof of an inventory transfer.

The repeat sent `CMSG_LOOT_MONEY` and `CMSG_AUTOSTORE_LOOT_ITEM`. The client
displayed both loot messages and money `100000017`; the player owner matched.
The corpse session and loot projection became nil, and its flags changed from
5 (tapped and lootable) to 4 (tapped only).

Logout saved 588 XP, money `100000017`, and one potion. After native reconnect,
the client showed the same XP and money, and the potion in its backpack. The
new player owner reported the same three values.

## Automated coverage and follow-up fixes

Contribution tests cover the strict cutoff, raid corpses, overkill, healing,
controlled attackers, absorption, immunity, scripted health thresholds,
periodic damage, lethal Soul Shard eligibility, self kills, victim changes,
evade, respawn, and XP rounding. Reward tests cover scaled party and pet XP,
ineligible killing-blow selection, full loot above the cutoff, and no party
loot rotation below it.

Corpse preparation also now uses the original tap group's loot policy after the
tagger changes parties. A regression keeps the old party alive, moves the
tagger into a new party, and verifies that only the old party's looter advances
and receives access. An unrelated Flare delivery test was made deterministic
by giving its target no spell defense; it had assumed a random hit always landed.

## Local evidence

- Server log: `/tmp/thistle-damage-origin-server.log`.
- Damage samples: `/tmp/thistle-origin-{low-contribution-final,high-contribution,full-contribution}.log`.
- Owner and projection reads: `/tmp/thistle-origin-{low-result,high-result,respawn,full-result}.log`.
- Client captures: `guard-kill-no-reward`, `corpse-unlootable`,
  `guard-kill-reduced-xp`, `assisted-loot-open`, and `full-player-kill` under
  the session's `screenshots` directory.
- Repeat samples and transfer state: `/tmp/thistle-origin-{repeat-contribution,repeat-looted}.log`;
  captures `repeat-assisted-loot-open` and `repeat-assisted-loot-collected`.

WoW's own AMDGPU graphics counter advanced from 995,610,866 to 29,015,508,144 ns,
confirming hardware rendering in the helper-owned service.

The helper-owned client service stopped and reported `inactive/dead`; the
retained server PTY exited. The server log contains no error-level entries or
gameplay validation warnings. The existing unsupported account-data, GM-ticket,
and meeting-stone requests were the only warnings. Evidence remains local;
nothing was pushed.

Final validation after client cleanup: `mix test.all` passed all 6,317 tests,
`mix compile --warnings-as-errors` passed, and `mix credo --strict` found no
issues. Logs are `/tmp/thistle-damage-origin-final-{tests,compile,credo}.log`.
