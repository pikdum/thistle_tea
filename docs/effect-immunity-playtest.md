# Aura-state and spell-effect immunity

The spell loader now maps state immunity (aura 38) and effect immunity
(aura 37), including their target aura/effect values. Pure gameplay rules
filter individual effects before melee avoidance and mechanic-resistance
rolls. A fully blocked spell produces one immune result; mixed spells keep
their unblocked effects. Positive and negative immunity holders respect
incoming effect polarity, with the explicit both-polarities and
restriction-ignoring attributes honored.

State immunities with the purge attribute remove matching existing holders
through the normal aura transition funnel. The same attribute lets a caster
use matching stun, fear, or confusion protection while controlled. Removing
or expiring one protection leaves overlapping sources effective, and normal
death cleanup removes temporary protection.

Reference: `Unit::IsImmuneToSpellEffect`, `Aura::HandleAuraModStateImmunity`,
and `Aura::HandleAuraModEffectImmunity` in `refs/vmangos/src/game/`.

## Real-client acceptance

Used two isolated build-5875 clients, Debugrogue (GUID 3) and Debugpaladin
(GUID 2), dueling on Programmer Isle with god mode disabled. Actions used
client casts and the existing `.learn` and `.modify hp` commands. Runtime
probes only observed owner state.

- Thickskull (829) protected the rogue from Pyroclasm (18093). The paladin's
  client displayed floating **Immune**, while the rogue retained protection
  and had no stun aura or stun flag.
- Pyroclasm first stunned an unprotected rogue. Casting the real DBC spell
  zzOLDHunter's Will (1542) while stunned immediately removed Pyroclasm and
  cleared the stun flag. The timeline recorded the transition from flags
  819208 to 557064, with the ten-second protection replacing the stun.
- After protection expired, another Pyroclasm applied normally. The rogue's
  client displayed its debuff and the owner retained it for approximately
  three seconds, then cleared the aura and stun flag.
- The rogue applied Veil of Darkness (28350) to the paladin. Holy Light
  rank 1 completed while Veil was active, displayed **Immune**, and did not
  heal: health remained 1410 across cast completion. Ordinary regeneration
  was sampled separately.
- After Veil expired, Holy Light healed normally. The second timeline
  recorded health increasing from 1512 to 1591 across completion, including
  that interval's regeneration.

An initial duel setup used the Lua accept function without dismissing the
request dialog; its later cancellation invalidated that attempt. Acceptance
used the actual Accept button and a fresh duel. A hidden NPC spell could be
learned but not cast by name from the client, so the effect-immunity check
used Veil of Darkness instead. No gameplay owner or network exceptions were
observed. Both clients and the local server were stopped afterward.

Overlapping sources, explicit removal, death, partial spells, polarity,
restriction bypass, and melee-roll ordering are covered by automated tests.

## Final validation

- `mix test.all`: 3,019 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Focused immunity tests: 14 passed; DBC mapping and cast-validation
  regressions also passed in the full suite.

## Evidence

- Paladin screenshots: `/home/pikdum/.cache/thistle-wow-playtest.C9trHF/screenshots/confirmed-immune.png`
  and `healing-immune.png` in the same directory.
- Rogue screenshot: `/home/pikdum/.cache/thistle-wow-playtest.jZsWCn/screenshots/stun-restored.png`.
- Authoritative samples: `/tmp/thistle-immunity-confirmed.txt`,
  `/tmp/thistle-immunity-lifecycle.txt`, `/tmp/thistle-immunity-expired.txt`,
  and `/tmp/thistle-immunity-healing.txt`.
- Server log: `/tmp/thistle-immunity-server.log`.
- Final checks: `/tmp/thistle-immunity-{all,compile,credo}-final.log`.
