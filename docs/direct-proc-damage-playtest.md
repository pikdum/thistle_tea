# Direct damage aura procs

Implemented and tested on 2026-09-21. Two isolated build-5875 clients ran against
`e101f4da` on a fresh server.

## Behavior and reference

Aura 43 now loads as `proc_trigger_damage`, distinct from aura 15 damage shields.
It uses the shared incoming and outgoing proc rules, including hit outcomes,
chance, cooldowns, and charges. Flameblade can therefore trigger on its carrier's
melee attacks, while Holy Shield and Blessing of Sanctuary require blocked hits.

The spell loader also inherits missing proc rules from the first spell in a rank
chain, preserving explicit overrides. This fixes higher Holy Shield and Sanctuary
ranks losing their block-only restriction.

The typed `ProcDamage` effect prepares the original aura effect as direct damage,
preserving its dice and coefficient. Damage uses the carrier's current inputs and
credits that carrier, even when another character applied the aura. Delivery uses
the normal damage, immunity, absorption, resistance, threat, and combat-log paths.
It cannot crit, reflect, damage a corpse, or start another proc chain. It does not
emit a new spell cast. Harmful magic procs roll hit chance; positive source spells
follow the reference's no-miss rule.

Reference checkout: `refs/vmangos` at `8f4e60845`:

- `src/game/UnitAuraProcHandler.cpp`, `HandleProcTriggerDamageAuraProc`:
  carrier attribution, original effect calculation, and direct damage delivery.
- `src/game/Objects/SpellCaster.cpp`, `SpellHitResult`: original-spell hit rules.
- `src/game/Spells/SpellMgr.cpp`: rank-chain proc-rule inheritance.
- Supported-build `spell_proc_event` rows: block outcome `0x40` for shield spikes,
  Holy Shield, and Blessing of Sanctuary.

## Automated acceptance

`mix test.all` passed **4,581 tests**. Compilation with warnings as errors passed;
strict Credo reported zero issues across 1,794 source files.

Coverage includes incoming/outgoing selection, avoided and fully blocked hits,
chance, cooldowns, charge exhaustion, cancellation, expiry, death, carrier
attribution, coefficients, absorption, immunity, hit rolls, reflection and proc
recursion suppression, missing/dead targets, owner delivery, and client packet
projection. Separately tagged DBC and VMangos tests verify real spell definitions,
rank chains, and proc rules without combining unavailable data sources.

## Native client acceptance

Debugpaladin (GUID 2) and Debugwarrior (GUID 1) were level 60 on Programmer Isle.
Setup used native `.character level`, `.debug skills`, `.learn`, and `.go`
commands. Both had god mode enabled to protect the fixtures; player damage and
mana expenditure are not acceptance claims. Tidewave probes only read state.

Flameblade 7808 excludes its caster, so the Paladin cast it on the Warrior.
The server logged `CMSG_CAST_SPELL` with target 1, and the Warrior's aura holder
retained caster GUID 2. With the nearby Skeletal Flayer selected, the Warrior
auto-attacked for approximately ten seconds. Its native log displayed six
**"Your Flameblade hits Skeletal Flayer for 14 Fire damage"** messages. The owner
sampler observed corresponding damage, including separate 14-point reductions
between melee updates; total mob health fell from 2,980 to 2,333.

After auto-attack stopped, a separate ten-second observation showed the buff
still present and the Flayer still attacking the Warrior. Mob health stayed at
2,333 and its threat table stayed at `{1, 517.6}`, with no Paladin threat entry.
Incoming-only attacks did not trigger Flameblade. Right-clicking its client buff
icon removed the aura, confirmed by the owner probe.

The Paladin then faced the reset Flayer with a drawn shield, auto-attack disabled,
and the existing QA block aura 10021. Rank-three Holy Shield 20928 inherited
`proc_ex: 64` and started with four charges. The native log showed four hits of
**130 Holy damage**. The sampler observed:

| Time from sampler start | Charges | Flayer health |
| --- | ---: | ---: |
| 664 ms | 4 | 2,980 |
| 2,577 ms | 3 | 2,850 |
| 3,909 ms | 2 | 2,720 |
| 5,180 ms | 1 | 2,590 |
| 7,843 ms | removed | 2,460 |

Health stayed at 2,460 through the remainder of the 24-second sample despite
continued incoming attacks. Away from combat, a second Holy Shield cast retained
all four charges and expired about 9,961 ms after its first observed application.
The final owner probe showed neither tested damage aura and no auto-attack.

The live run proves outgoing damage, recipient attribution, incoming-only
suppression, native cancellation, block-triggered damage, charge exhaustion, and
timed expiry. Other proc variants and defensive edge cases use automated coverage.
Initial self-target and distant-target setup attempts were corrected before
these observations; they are not counted as acceptance.

There were no server errors or spell-validation failures. Only existing
account-data, raid-info, GM-ticket, and meeting-stone login warnings appeared.
Both helper-owned clients, Xvfb processes, and the server were stopped afterward.

## Local evidence

- Paladin session: `/home/pikdum/.cache/thistle-wow-playtest.B9O1Xf`;
  screenshots `holy-shield-procs.png` and `holy-shield-expired.png`.
- Warrior session: `/home/pikdum/.cache/thistle-wow-playtest.iSIWld`;
  screenshots `flameblade-melee.png` and `flameblade-before-cancel.png`.
- Server log: `/tmp/thistle-proc-damage-server-2.log`.
- Probes: `/tmp/thistle-proc-damage-{buffed,incoming,pre-holy,cleanup}.txt`.
- Samplers: `/tmp/thistle-proc-damage-warrior-melee.txt`,
  `/tmp/thistle-proc-damage-holy-sample.txt`, and
  `/tmp/thistle-proc-damage-holy-expiry.txt`.
- Gates: `/tmp/thistle-proc-damage-{focused,dbc,vmangos,all,compile,credo}.log`.
