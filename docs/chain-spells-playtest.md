# Chained spells and jump attenuation

Commit `2b003acf` completes the missing per-jump effect calculation and improves
the existing chain target expansion. Chain Lightning and Chain Heal previously
delivered full-strength effects to every selected recipient.

## Behavior and references

`Spell.Chain` snapshots per-effect recipients and multipliers when a cast
launches. Each effect retains its own target count; caster-only and primary-only
effects do not spread to every bounce. Saved hit-roll misses occupy a target
slot without advancing attenuation. Triggered chains resolve through their
caster and share the same calculation.

`Entity.ChainTargets` selects successive recipients within ten yards of the
previous target. It checks line of sight, caster detection, creature type,
hostility, assistance eligibility, and world identity. Chain Heal skips
full-health secondary recipients and prefers the preceding recipient's raidmates,
then the greatest absolute health deficit. It can bounce back to its caster.
Health deficits are derived at the existing owner metadata publication paths.

Jump-count and later-effect spell modifiers participate in the saved plan and
charged-modifier consumption. Attenuation multiplies the rolled effect value
before spell-power or healing bonuses. Separate rolls and critical hits mean
the final combat-log numbers need not be exact ratios of the preceding hit.

Reference behavior comes from `refs/vmangos/src/game/Spells/Spell.cpp`:
`SetTargetMap`, `ChainHealingOrder`, `InitializeDamageMultipliers`, and
`DoSpellHitOnUnit`; the ten-yard constant is in `SharedDefines.h`. The DBC
supplies three targets and factors of approximately `0.7` for Chain Lightning
421 and `0.5` for Chain Heal 1064. Target 45 now retains its distinct Chain Heal
meaning instead of being merged into ordinary friendly targeting.

The debug playground has three additional Skeletal Flayers at spawn IDs
991600–991602, eight yards apart west of the main spawn point.

## Automated verification

Final implementation gates passed:

- `mix test.all`: **5,461 passed**.
- `mix compile --warnings-as-errors`.
- `mix credo --strict`: zero issues.
- Formatting, `git diff --check`, and commit hooks.

Regressions cover independent effect counts, saved misses, ordinary spell
isolation, modifiers, damage and healing bonuses, a caster bounce, ordered
launch feedback, cancellation, foreign triggered-caster routing, blocked jumps,
line-of-sight exemptions, hidden/dead/wrong-type targets, instance separation,
raid priority, full-health exclusion, and live health-deficit publication.
Line-of-sight selection tests inject their visibility result; geometry itself
is covered by the existing map integration suite.

## Native acceptance

Three isolated GPU-rendered WoW 1.12.1 build-5875 clients used Debugmage,
Debugbuyer, and Debugbidder on Programmer Isle. Debugmage learned the actual
rank-one Shaman spells through `.learn`; casts, development setup commands,
movement, death, and resurrection acceptance all came from the clients.
Tidewave only sampled live state.

| Scenario | Client result | Authoritative result |
| --- | --- | --- |
| Chain Lightning, three nearby enemies | Combat log reported 224, 156, and 114 damage | Spawn 991601 lost 224 health, 991600 lost 156, and 991602 lost 114 |
| Chain Heal, three injured players | Buyer healed for 363, caster for 193, bidder for 97 | In one sampled transition, health changed from 857/319/304 to 1220/512/401 in that order |
| Full-health bidder | Only buyer and caster received heal messages, for 364 and 177 | Bidder remained at 1875; buyer changed 2229→2593 and caster 790→967 |
| Dead bidder | Only buyer and caster received heal messages, for 368 and 182 | Bidder remained at zero; buyer changed 504→872 and caster 1348→1530 |
| Movement interruption | Cast bar appeared, then disappeared after forward input; no new heal messages | Spell 1064 was present for about 610 ms, then casting cleared; health only changed through ordinary regeneration |
| Resurrection and another chain | Bidder accepted the native Resurrection dialog; the next chain healed all three players | Buyer gained 379, caster 187, and bidder 145 from a critical third bounce; all were alive with no active cast afterwards |

An earlier lightning cast started on the middle creature and hit only two:
after jumping to one endpoint, the remaining creature was sixteen yards away.
The three-hit run used the creatures after they had gathered around the caster.
The first sampler's default display truncated its result; the accepted run
retains complete, compact health transitions in a separate file.

Raid priority, jump modifiers, mixed-effect spell plans, and blocked geometry
selection were verified through automated tests rather than native scenarios.
No server errors or cast-validation failures appeared during acceptance. Login
reported the existing unimplemented account-data, GM-ticket, and meeting-stone
messages.

## Local evidence

- Mage screenshots: `/home/pikdum/.cache/thistle-wow-playtest.wM3g8B/screenshots/`
  (`lightning-three-result`, `heal-three-result`, `heal-skip-full`,
  `heal-skip-dead`, `heal-before-cancel`, `heal-cancelled`,
  `heal-after-resurrection`).
- Buyer session: `/home/pikdum/.cache/thistle-wow-playtest.wnpAQ4/`.
- Bidder session: `/home/pikdum/.cache/thistle-wow-playtest.aHPXgw/`
  (`resurrection-offer`, `restored-recipient`).
- Health samples: `/tmp/thistle-chain-lightning-three.txt` and
  `/tmp/thistle-chain-heal-{three,full,dead,cancel,restored}.txt`.
- Final owner state: `/tmp/thistle-chain-final-state.txt`.
- Server log: `/tmp/thistle-chain-server.log`.
- Gates: `/tmp/thistle-chain-all-final.log`,
  `/tmp/thistle-chain-compile-final.log`, `/tmp/thistle-chain-credo-final.log`.

All three WoW processes used `amdgpu` on `0000:0c:00.0`. Their graphics counters
advanced from 7,218,672,240 to 18,282,589,953 ns for the mage, 5,893,061,392 to
17,359,936,451 ns for the buyer, and 3,426,605,263 to 13,654,292,609 ns for the
bidder. Evidence is retained in `/tmp/thistle-chain-gpu-{start,end}-*.txt`.

All three helper-owned client sessions and the retained server were stopped.
No push or deployment was performed.
