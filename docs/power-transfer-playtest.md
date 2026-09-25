# Power transfer and energize acceptance

Validated with the build-5875 client on 2026-09-25. The implementation follows
`refs/vmangos` at `8f4e60845`: `Spell::EffectPowerDrain`, periodic mana leech,
`EnergizeBySpell`, and `WarlockLifeTapScript`.

## Changes

- Direct drains consume the victim's active resource, apply spell bonuses, and
  restore mana only when draining another entity's mana. Self drains, energy
  drains, and hunter happiness drains do not refund mana.
- Player and creature owners receive typed restoration effects. Periodic leech
  threat uses the caster's actual gain after clamping, and conversion modifiers
  come from the current caster. Dead or unavailable casters cannot continue
  periodic drains.
- Direct energize, direct drains, and periodic leech use their distinct vanilla
  combat-log packets. Periodic leech interrupts damage-sensitive auras through
  the shared aura transition path.
- Life Tap spends health directly, preserving shields and damage-sensitive
  auras. Validation checks its modified cost, and spell 31818 delivers the mana
  gain through normal energize handling.

Implementation commits: `e8c8ad3d` and `babd4e13`.

## Native acceptance

Used Debugwarlock on Programmer Isle with native chat commands, spell casts,
pet controls, and item use. Tidewave probes only read owner state. Both helper
sessions used private Gamescope displays and hardware OpenGL; WoW's own
`amdgpu` DRM counters increased in each session.

| Action | Client evidence | Authoritative evidence |
| --- | --- | --- |
| Summon Imp and cast Dark Pact rank 1 | Combat log reports 150 mana drained from Imp and 150 gained | Pet mana fell from 1,450 to 1,300; warlock mana rose from 51 to 201 in the same sampled transition |
| Cast Drain Mana rank 4 on the seeded Defias Evoker | Channel/aura visible; combat log reports 102-mana ticks and a final 72-mana transfer | Final partial tick reduced target mana from 72 to 0, raised caster mana from 2,186 to 2,258, and increased target threat from 357 to 393 |
| End the drain channel | Channel bar and target drain aura clear | Spell 11703 disappeared from the target and caster channel field became zero; target mana regenerated without further drains or leech threat |
| Use Greater Mana Potion, item 6149 | Combat log says “You gain 711 Mana from Restore Mana” | Mana rose from 151 to 862; the ordinary regeneration ticks were separately visible |
| Fresh-server Life Tap rank 1 | Combat log says “You gain 39 Mana from Life Tap” | Health fell from 2,179 to 2,140, then mana rose from 51 to 90 through the triggered energize |
| Life Tap with health set to 1 | Client displays “Fizzled” | Server rejects spell 11688 during validation; no resource effect is delivered |

The first Drain Mana attempt at the target was resisted. A subsequent native
cast landed and produced the successful evidence above. Teleport setup used a
height of 80 near `{16382, 16258}` so the player landed above the local terrain.

The first session used `e8c8ad3d`. Life Tap acceptance used a restarted server
at `babd4e13`; no hot reload was used for that acceptance. No unexpected owner,
packet, or resource errors appeared in either native server log. The deliberate
low-health Life Tap rejection logged the expected `fizzle` validation warning.

## Automated validation

`mix test.all`: **6,264 passed**. Compilation with `--warnings-as-errors` and
`mix credo --strict` passed. The architecture dependency allowlist is unchanged.

Regressions cover direct and periodic resource selection, self drains,
conversion defaults and modifiers, fractional direct gains, cap-dependent
threat, creature and player delivery, explicit owner contexts, dead recipients,
caster disappearance/world changes, immunity, aura removal/death, interrupted
aura preservation, packet bytes, and observer world isolation. Life Tap tests
also cover Improved Life Tap, coefficient/cost modifiers, shield preservation,
and matching validation/execution health checks.

## Retained artifacts and cleanup

- Initial client: `/home/pikdum/.cache/thistle-wow-playtest.4lnXN7`.
  Screenshots: `dark-pact.png`, `drain-mana-channel.png`,
  `drain-mana-ticks.png`, `drain-mana-empty.png`, `mana-potion.png`.
- Fresh Life Tap client: `/home/pikdum/.cache/thistle-wow-playtest.w90UFc`.
  Screenshots: `life-tap-result.png`, `life-tap-fizzle.png`.
- Owner samples: `/tmp/thistle-power-dark-pact.log`,
  `/tmp/thistle-power-drain-mana-4.log`, `/tmp/thistle-power-energize.log`,
  `/tmp/thistle-power-life-tap.log`.
- Server logs: `/tmp/thistle-power-server.log`,
  `/tmp/thistle-power-life-tap-server.log`.
- GPU evidence: `/tmp/thistle-power-gpu.log`,
  `/tmp/thistle-power-life-tap-gpu.log`.
- Validation: `/tmp/thistle-power-final-tests.log`,
  `/tmp/thistle-power-final-credo.log`.

Both helper-owned sessions were stopped through their recorded systemd units,
and both retained server PTYs were stopped. Artifacts remain available locally.
No push or deployment was performed.
