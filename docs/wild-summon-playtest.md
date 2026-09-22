# Wild creature summons and Target Dummies

Implemented in `34fff225`, with vendor interaction corrected in `c869a365`
and summon initialization hardened in `a226346b`. Acceptance completed on
2026-09-22.

## Shared behavior

Spell effect 41 creates independent creatures through a typed `SummonWild`
effect and a cached boundary loader. Unit casters supply the spell, quantity,
duration, and destination. The first creature uses an explicit destination;
additional creatures scatter within its radius. Without a destination, the
spell radius offsets the spawn forward from the caster.

Ordinary wild summons retain their template faction and level range, use mob
GUIDs, and do not occupy a combat-pet or guardian slot. Their lifetime does not
depend on caster presence. Templates marked for creator loot retain a creator
GUID and claim their normal loot through the shared tap transition. The client
labels these creatures as guardians, but they have no controllable pet relation.
The template's no-XP flag suppresses experience rewards.

Positive durations produce death and a normal corpse. Expiry waits while an
ordinary wild summon is in combat. Dead or indefinite summons retain the corpse
lifecycle without a respawn timer; corpse removal stops the temporary actor and
removes its world and metadata projections. Script-created summons using the
same timed-death type initialize the same deadline.

Target Dummies add stationary, passive behavior, their creation taunt and
periodic threat aura, caster faction, and an unconditional 15-second death
deadline. They never chase or melee. Their corpse uses the template's salvage
loot, and their death runs through the shared engagement and aura cleanup.
Expired creatures do not emit another periodic pulse from the corpse.

Reference: `refs/vmangos` at `8f4e60845`, particularly
`Spell::EffectSummonWild`, `TemporarySummon::Update`, `TargetDummyScript` in
`spell_item.cpp`, and `npc_target_dummyAI` in `npcs_special.cpp`.
The raw DBC contains 372 wild-summon effect occurrences. VMangos overrides
classify all three Target Dummy spells as wild summons. Their template levels
remain 20, 40, and 55 at Engineering 300; the reference computes an Engineering
level inside `EffectSummonWild` but does not apply that variable to the summon.
Other creature-specific summon scripts remain separate content work.

## Automated acceptance

`mix test.all` passed **4,686 tests**. Compilation passed with
`--warnings-as-errors`, and strict Credo found zero issues across 1,834 files.
The architecture ratchet passed without an allowlist change.

Coverage includes DBC semantics and caster execution, quantity and destination,
indefinite duration, independent repeated summons, creator loot, no-XP templates,
derived-stat initialization, every dummy passive, periodic pulses ending at
death, combat-gated expiry, passive behavior, exact wake scheduling, scripted
death deadlines, corpse retention, stale corpse tokens, and complete actor and
projection cleanup. The vendor regression covers an NPC without an explicit
gossip menu, including an empty inventory and a dead-vendor rejection.

Default actor tests use cached synthetic templates. DBC-reading tests carry
`:dbc_db` and do not require VMangos queries.

## Native client acceptance

Two fresh local servers and isolated build-5875 clients used Debugwarlock.
Existing development commands supplied levels, Engineering, items, travel, and
durability wear. Item activation and ground targeting, repairs, looting, logout,
and reconnect used native client actions. Tidewave probes only read state.

The initial run exposed the missing vendor fallback. The fresh repeat used
`c869a365`; the subsequent initialization fixes have focused regressions and
the final full-suite result above.

| Creature | Native item | Level | Maximum health | Result |
| --- | --- | --- | --- | --- |
| Target Dummy | 4366 | 20 | 968 | Opening taunt, 15-second death, salvage collection |
| Advanced Target Dummy | 4392 | 40 | 3,048 | Repeated threat, damage received, no retaliation, salvage |
| Masterwork Target Dummy | 16023 | 55 | 5,228 | Survived caster world transfer, expired, salvage collected |
| Field Repair Bot 74A | 18232 | 50 | 2,215 | Merchant interaction, repairs, independent ten-minute lifetime |

- Ground-targeted item use consumed the summon items and preserved the active
  Imp and its action bar. Dummies retained their exact spawn positions.
- The opening taunt redirected a Defias Thug. The Advanced Dummy then added
  100 threat at approximately 3, 6, 9, and 12 seconds. Its attacker continued
  targeting it after the opening taunt expired. The dummy's health fell from
  3,048 to 3,040 while the attacker's health stayed at 86. At about 15 seconds,
  the dummy died and the attacker selected another target.
- Native loot clicks collected Fused Wiring and rank-specific salvage. The
  standard dummy supplied Copper Modulator, Handful of Copper Bolts, Bronze Bar,
  and Wool Cloth. The Masterwork Dummy supplied Mithril Casing, Thorium Tube,
  and Runecloth. The final inventory contained three Fused Wiring items.
- Logout left the standard dummy's corpse and live repair bot in the world.
  Reconnect retained them. The standard corpse later disappeared naturally;
  GUID `17379391006872437669` had no actor, position, or metadata afterward.
- Masterwork Dummy `17379391170500625710` remained alive at its Goldshire
  position with 8.9 seconds remaining while its caster was already on map 451.
  It died in Goldshire, and returning to map 0 allowed normal salvage looting.
- The repair bot had no creator or summoner GUID and retained faction 35.
  Right-clicking initially produced no window because `Gossip.hello` returned
  without handling menu-less vendors. The fix delegates that case to the
  existing authorized vendor path. The fresh client's merchant window opened,
  and its repair button restored nine worn items for 2,535 copper.
- Repair bot `17379391202561884724` survived logout and world transfers. Its
  ten-minute timer produced 0/2,215 health, a visible dead model, no loot, and no
  respawn timer.

No summon, combat, loot, movement, or owner-process failures appeared during
the corrected native run. Existing unrelated account-data, raid-info, ticket,
and meeting-stone opcode warnings were outside this acceptance.

## Retained evidence

- Initial client: `/home/pikdum/.cache/thistle-wow-playtest.tem2My`
- Corrected client: `/home/pikdum/.cache/thistle-wow-playtest.idktwI`
- Server logs: `/tmp/thistle-wild-server.log` and
  `/tmp/thistle-wild-fixed-server.log`
- State evidence: `/tmp/thistle-wild-advanced-sample.txt`,
  `/tmp/thistle-wild-fixed-logout.txt`, `/tmp/thistle-wild-natural-cleanup.txt`,
  `/tmp/thistle-wild-master-worldport.txt`, `/tmp/thistle-wild-master-expired.txt`,
  `/tmp/thistle-wild-final-inventory.txt`, and
  `/tmp/thistle-wild-final-lifecycle.txt`
- Final gates: `/tmp/thistle-wild-final-tests.log`

Client screenshots include `repair-bot-merchant`, `repair-bot-repaired`,
`dummy-loot-collected`, `advanced-alive`, `advanced-loot-window`, `master-loot`,
and `bot-expired-master-salvage`. Both clients, X servers, and BEAM servers were
stopped after acceptance.
