# Periodic health funnels and leech lifecycle

Aura 62 (`periodic_health_funnel`) now uses the shared periodic leech path.
It applies stacked damage, resistance and absorption, then transfers actual
health lost through the caster's owner. Overkill cannot increase healing.
Transfer ratios use `EffectMultipleValue`, default to one when unspecified,
and support spell modifier 27. Friendly funnels retain positive aura polarity.

The receiving boundary checks caster presence, world and life state at each
due tick. A dead, missing or differently instanced caster suppresses both
damage and healing while deadlines continue advancing. Ordinary damage-over-time
effects retain their existing behavior. Healing delivery rejects dead and
ghost recipients and emits the ordinary heal combat log without introducing
another helpful-spell proc.

Follow-up fixes apply snapshotted outgoing school and creature-specific
percentage damage bonuses to periodic damage, leech and funnels, excluding
fixed damage, ignored caster modifiers and Ignite. Self-targeted funnels now
return their healing effect through the same owner delivery path.

## Reference and data boundaries

- `refs/vmangos/src/game/Spells/SpellAuras.cpp`: aura handlers and the shared
  periodic leech/funnel tick, including caster life checks and actual damage
  transfer.
- `refs/vmangos/src/game/Objects/SpellCaster.cpp`: outgoing damage bonuses and
  heal combat feedback.
- `refs/vmangos/src/game/Spells/SpellEntry.cpp`: aura polarity, coefficient
  calculation and the fallback count of six ticks for health funnels.
- Original DBC spell 24322, Blood Siphon, drains 200 every second with a
  transfer ratio of five. Spell 24617, Blood Funnel, drains 500 every second
  with a ratio of ten. These ratios come from the multiple-value columns.

VMangos overrides both original funnel spells with separate periodic damage
and healing effects. Those overrides remain authoritative in the running
server. The tagged DBC test temporarily isolates the original effects from
the in-memory override cache and restores it afterwards. Native acceptance
below uses Siphon Life to exercise the shared leech fixes; it does not claim
that the overridden Blood Funnel runtime spell exercised aura 62.

## Automated verification

Commits `3db2b46f`, `a395f7bc` and `7394ad30` passed the final suite with
5,445 tests, compilation with warnings treated as errors, strict Credo with
zero issues, formatting and commit hooks. Focused regressions cover timing,
final expiry, removal, stacks, shields, overkill, immunity, damage reduction,
spell power, outgoing percentages, transfer modifiers, friendly polarity,
self-targeting, coefficients, dead targets, caster death, missing casters,
world separation, resumed schedules, heal feedback and healing threat.

## Native client acceptance

Two isolated GPU-rendered WoW 1.12.1 build-5875 clients used Debugmage and
Debugbuyer on Programmer Isle. All gameplay mutations used native client
actions and existing development chat commands. Tidewave only read state.

Siphon Life, spell 18265, applied to the development Devilsaur at spawn
990200. Its three-second ticks dealt 15 damage and restored 15 health.
Both messages appeared in the mage's chat, and authoritative health changes
matched. The first full cast expired normally.

For the accepted death run, Debugbuyer retained the Devilsaur's attention
after stopping autoattack. A read-only sampler started before the mage cast:

| Relative time | Caster health | Target health | Aura state |
| --- | ---: | ---: | --- |
| 2.238 s | 275 | 7,526 | Applied, 15 per tick |
| 5.277 s | 290 | 7,511 | First drain |
| 8.311 s | 305 | 7,496 | Second drain |
| 10.331 s | 0 | 7,496 | Caster killed through `.die` |
| 11.149–29.233 s | 0 | 7,496 | Due ticks advanced without draining |
| 32.264 s | 0 | 7,496 | Aura expired and was removed |

The target remained engaged with Debugbuyer throughout the death window.
Earlier out-of-range casts and a Devilsaur leash reset were excluded from
acceptance. Native corpse recovery was also exercised between attempts.

A fresh server at `7394ad30` repeated Siphon Life through all ten ticks:
target health fell from 7,599 to 7,449 and caster health rose from 117 to
267, with 15-point damage and healing messages and final aura removal.
Arcane Power was active at application, but its runtime effects are
class-masked spell modifiers that exclude Siphon Life. This run confirms the
ordinary drain path on the final source; percentage-bonus acceptance remains
automated rather than native.

## Local evidence

- Lifecycle screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.5OZQzm/screenshots/`
  (`siphon-first`, `leech-living-final`, `leech-dead-final`).
- Second client:
  `/home/pikdum/.cache/thistle-wow-playtest.a4HHE4/`.
- Final-source client:
  `/home/pikdum/.cache/thistle-wow-playtest.gWZeDq/screenshots/`
  (`arcane-power-drain`, `retained-bonus`). The latter filename records the
  attempted check, not evidence of a matching bonus.
- Authoritative samples: `/tmp/thistle-funnel-siphon-live.txt` and
  `/tmp/thistle-funnel-death-final.txt`; final-source samples are in
  `/tmp/thistle-funnel-bonus-live.txt`.
- Lifecycle server log: `/tmp/thistle-funnel-server.log`.
  No server errors were found. Login reported existing unimplemented account
  data, GM ticket and meeting stone messages.
- Gate logs: `/tmp/thistle-funnel-all-final-passed.log`,
  `/tmp/thistle-funnel-followup-compile.log`,
  `/tmp/thistle-funnel-followup-credo.log`.
- Both owned WoW processes used `amdgpu` on `0000:0c:00.0`. Their graphics
  counters advanced from 4,550,677,193 to 30,974,161,948 ns for the mage and
  from 2,754,030,628 to 31,105,851,749 ns for the second client. Samples are
  retained in `/tmp/thistle-funnel-gpu-{start,end}-*.txt`.

All isolated clients and both retained server sessions were stopped. No push
or deployment was performed. Work paused at the user's request for a reboot.
