# Conditional item triggers

Implementation: `8d667ea4`, with the regeneration follow-up in `3a9f965e`.
Reference: VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`.

## Behavior and reference

Linken's Boomerang (item 11905, spell 15712) retains its ordinary damage
and rolls its disarm and stun independently. Scorpid Surprise (item 5473,
spell 6410) always applies its food aura and sometimes triggers poison.

| Parent effect | Child spell | Chance |
| --- | --- | ---: |
| Boomerang effect 1 | Disarm, 15752 | 1/31 |
| Boomerang effect 2 | Knockdown, 15753 | 1/11 |
| Food effect 1 | Scorpid Poison, 6411 | 1/11 |

These probabilities follow the inclusive `urand` checks in
`src/scripts/spells/spell_item.cpp`, `LinkensBoomerangScript` and
`ScorpidSurpriseScript`. The reference comments describe approximate 3% and
10% chances and acknowledge uncertainty; these are reference-compatible
values, not independently established historical rates.

The existing trigger path now emits weighted `RandomChoice` effects for
these cached script labels and effect indices. The boundary selects an
outcome and resolves the ordinary child spell. Target filtering, immunity,
parent damage, cast context, aura control, and expiry keep their existing
owners. Unscripted triggers remain unconditional. No architecture allowlist
or network protocol changed.

Testing exposed a separate low-spirit regeneration error. VMangos
`Unit::GetRegenHPPerSpirit` clamps the spirit contribution to zero before
`Player::RegenerateHealth` adds food and flat bonuses. Applying that clamp
prevents low-spirit warriors, hunters, rogues, and shamans from losing food
healing to a negative spirit contribution. The existing five-second food
interval was already correct.

## Automated validation

- `mix test.all`: 7,422 passed in 81.4 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Both code commits passed the formatting and Credo hooks.

Pure tests enumerate all 341 boomerang roll pairs, including neither effect,
each effect alone, and both together. They cover lethal and immune targets,
recipient filtering, effect masks, cast-item context, ordinary triggers,
and the food branch. DBC tests apply the actual child spells, verify weapon
damage and speed changes, stun/disarm expiry and death cleanup, food healing,
poison's 10-damage ticks, and aura expiry. A separate VMangos-tagged test
checks the cached script labels. Regeneration tests cover all four classes
whose spirit formulas can become negative.

Logs: `/tmp/thistle-conditional-triggers-final-{tests,compile,credo}.log`.

## Native acceptance

Debugmage (5) and Debugpaladin (2), both level 60, used two isolated
build-5875 clients on Programmer Isle. The fresh server loaded the final
code at startup; no gameplay modules were recompiled live. Existing native
debug commands prepared levels, health, learned spells, and inventory.
Tidewave performed read-only owner snapshots and 50 ms sampling.

The learned boomerang parent spell sampled the random outcomes before the
actual item use. The client's minimum-range rejection required moving the
caster farther from the defender. Casts then traveled through native
`CMSG_CAST_SPELL`; god mode prevented deaths during repeated sampling.

- A native parent cast reduced paladin health from 3451 to 3373, applied
  Knockdown for two seconds, and removed it at expiry.
- Repeated casts produced ordinary hits without control effects and
  occasional stuns. A disarm changed weapon damage from 151.2–203.2 to
  77–78, and attack speed from 2400 to 2000 ms. Its holder had a 10-second
  lifetime. Both clients displayed the disarm icon; a later snapshot
  confirmed the original weapon values and no control auras.
- With god mode disabled on the recipient, using equipped item 11905
  reduced health from 3451 to 3367 without either control aura. The client
  combat text reported 84 damage. The retained item cooldown was 180000 ms,
  with a 10000 ms category deadline. Immediate reuse displayed
  “Item is not ready yet.”
- After forfeiting the duel and disabling mage god mode, actual Scorpid
  Surprise consumption applied both Food (6410) and Scorpid Poison (6411).
  The client displayed both icons and the poison effect. Owner samples
  recorded separate 10-health losses, including 1421→1411 and 1520→1510,
  interleaved with food healing. Both holders expired naturally.
- Subsequent meals displayed Food alone. An immediate owner snapshot
  contained only 6410, with the stack reduced to 17 after three consumed
  items. Later forward input moved the mage, restored the standing pose,
  and left no food or poison aura; the stack remained 17.

The server log contains no gameplay errors or failed spell validation.
Its warnings are the existing account-data and GM-ticket stubs.

## Evidence and cleanup

- Mage session: `/home/pikdum/.cache/thistle-wow-playtest.nWtHHx`.
- Paladin session: `/home/pikdum/.cache/thistle-wow-playtest.odZisy`.
- Screenshots include `disarm-live`, `disarm-observer`, `boomerang-cooldown`,
  `food-first`, `poison-expired`, and `food-normal-live`.
- Owner evidence: `/tmp/thistle-conditional-native-*.log`, especially
  `parent-hit`, `control-sample-3`, `disarm-visible`, `item-hit`,
  `food-baseline`, `food-first`, `expired`, `food-normal-live`, and
  `food-cleanup`.
- Server log: `/tmp/thistle-conditional-triggers-server.log`.
- WoW processes 2767299 and 2768085 each reported `amdgpu`, nonzero graphics
  engine counters, and allocated VRAM in their own DRM file descriptors.

Both helper-owned client services and the retained server were stopped.
Logs and screenshots were retained. No changes were pushed.
