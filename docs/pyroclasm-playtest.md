# Pyroclasm and resolved spell feedback acceptance

Validated with the build-5875 client on 2026-09-26 (America/Chicago).
Implementation: `4d65da97`; feedback fix: `bceb3909`.
Reference: `refs/vmangos` at `8f4e608450460efe1e38743e4da74397d4773a3a`,
particularly `Unit::HandleProcTriggerSpellAuraProc` in `UnitAuraProcHandler.cpp`
and the triggered-stun classification in `SpellEntry.cpp`.

## Behavior

Both Pyroclasm talent ranks now replace the DBC dummy trigger with stun 18093.
Soul Fire uses the full rank chance; channels divide that chance over their
ticks, matching the reference core:

| Talent rank | Soul Fire hit | Each Hellfire tick | Each Rain of Fire tick |
| --- | --- | --- | --- |
| 1 (18096) | 13% | 13% / 15 | 13% / 4 |
| 2 (18073) | 26% | 26% / 15 | 26% / 4 |

The proc requires a living recipient other than the caster. Hellfire's
self-damage cannot stun its caster. Existing proc flags and spell-family
restrictions still reject unrelated spells and unsuccessful outcomes. The
stun uses normal triggered delivery, immunity, diminishing returns, aura
projection, expiry, and death cleanup.

Client testing exposed a second issue: spell-outcome handlers only looked up
the triggering damage spell in the owner's learned spellbook. Hellfire's
damage subspell 5857 is not learned, so its feedback was discarded. The event
sink now carries the resolved spell with the outcome. Player and creature
owners prefer that snapshot, retaining the existing spellbook fallback for
older payloads. This also preserves the actual resolved spell without adding
database queries or architecture dependencies.

## Native acceptance

Two isolated hardware-rendered clients used level-60 Debugwarlock (GUID 6) and
Debugrival (GUID 12), both with godmode disabled. Setup used existing developer
commands; spell casts, ground targeting, logout, and reconnect used the real
client. Proc chances were unchanged. Tidewave probes were read-only.

The final server was freshly started with both commits. Acceptance positions
were `{16303.2, 16218.1, 69.44}` and `{16306.2, 16218.1, 69.44}` on map 451.
An earlier position overlapped neutral merchants and the caster died there;
the isolated area allowed exact self-damage accounting without that overlap.

| Scenario | Client and authoritative evidence |
| --- | --- |
| Unlearned damage spell | Before the fix, owner inspection confirmed learned Hellfire 1949 and Rain of Fire 5740, but no learned Hellfire Effect 5857. The final acceptance retained that normal spellbook arrangement. |
| Hellfire proc | During rank-1 Hellfire with rank-2 Pyroclasm, the sixth 87-point tick left caster health 2072 and recipient health 2907. The recipient gained stun 18093 with caster GUID 6 and an exact 3000 ms lifetime. Its diminishing group was `:triggered_stun`. |
| Client presentation | Both clients displayed the target's Pyroclasm affliction. The victim showed the stun pose, overhead effect, and debuff icon. The caster still displayed its active Hellfire channel and had no Pyroclasm aura. |
| Hellfire expiry | The stun disappeared after three seconds while Hellfire continued. All 15 self-damage ticks completed, leaving caster health 1289 from 2594. The channel then cleared; neither player retained stun 18093. |
| Rain of Fire | Ground-targeted rank-1 Rain of Fire also triggered stun 18093 on the final code. The probe captured channel 5740, recipient health 3085, caster GUID 6, and another exact 3000 ms stun. The recipient client displayed the affliction and stun pose. |
| Ground-spell cleanup | After the Rain of Fire channel ended, casting was nil, channel state was cleared, and both players had no Pyroclasm stun. The warlock retained passive talent 18073. |
| Logout and reconnect | Logout removed both characters from entity registration, metadata, and world presence. Reconnect retained the learned passive talent, with no expired stun or active channel. |

Soul Fire was cast normally during acceptance but did not proc on the sampled
attempts. Its positive proc path, both talent ranks, and exact chance boundaries
are covered by automated tests. Native tests exercised rank-2 Pyroclasm;
they do not estimate proc probabilities statistically.

WoW's own `amdgpu` graphics counters increased from 4,490,123,323 to
57,645,393,585 ns for PID 1435035, and from 4,705,633,464 to 56,917,237,507 ns
for PID 1435809. Duplicate file descriptors were not summed.

## Automated validation

`mix test.all`: **6,426 passed**. `mix compile --warnings-as-errors` and
`mix credo --strict` passed; Credo reported zero issues across 2,358 files.
Formatting and commit hooks passed.

Pure tests cover both ranks' chance boundaries, channel normalization, the
Soul Fire exception to the shared Hellfire family mask, unrelated spells,
self-damage, dead recipients, and missing feedback. DBC tests follow actual
damage feedback, verify talent-rule inheritance, and deliver the
stun through player and creature owner callbacks without a learned damage
spell. They verify client aura-duration effects, triggered-stun classification,
expiry, and death cleanup. A VMangos-tagged test verifies the first-rank proc
mask used by both talent ranks. Event-sink tests retain the resolved spell and
target-owned life/resource facts.

## Retained evidence

- Caster client: `/home/pikdum/.cache/thistle-wow-playtest.p7EmyH`.
- Recipient client: `/home/pikdum/.cache/thistle-wow-playtest.OP4WnK`.
- Final screenshots include `hellfire-accepted-1-caster.png`,
  `hellfire-accepted-1-victim.png`, `final-rain-caster.png`,
  `final-rain-victim.png`, `final-stun-expired.png`,
  `final-logged-out.png`, and `final-reconnected.png`.
- Feedback diagnosis: `/tmp/thistle-pyroclasm-feedback-gap.log` and
  `/tmp/thistle-pyroclasm-final-spellbook.log`.
- Final native evidence: `/tmp/thistle-pyroclasm-final-before.log`,
  `/tmp/thistle-pyroclasm-hellfire-accepted-1.log`,
  `/tmp/thistle-pyroclasm-hellfire-accepted-1-watch.log`,
  `/tmp/thistle-pyroclasm-hellfire-cleanup.log`,
  `/tmp/thistle-pyroclasm-final-rain.log`,
  `/tmp/thistle-pyroclasm-final-rain-cleanup.log`,
  `/tmp/thistle-pyroclasm-logout.log`, and `/tmp/thistle-pyroclasm-reconnect.log`.
- GPU evidence: `/tmp/thistle-pyroclasm-gpu-before.log` and
  `/tmp/thistle-pyroclasm-gpu-after.log`.
- Server and checks: `/tmp/thistle-pyroclasm-final-server.log`,
  `/tmp/thistle-pyroclasm-all.log`, `/tmp/thistle-pyroclasm-compile.log`,
  and `/tmp/thistle-pyroclasm-credo.log`.

The final server recorded no owner crashes or unsupported aura/effect errors.
Existing account-data, GM-ticket, and meeting-stone message warnings remain
outside this gameplay path.

Both helper-owned clients and the retained server were stopped. Logs and
screenshots remain available locally. No push or deployment was performed.
