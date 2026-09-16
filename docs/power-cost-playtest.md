# School-based spell costs

Flat school cost auras now work, including Burst of Knowledge and Insight.
Costs combine the base spell cost and base-resource percentage, add matching
flat school modifiers, apply spell-family modifiers, then apply school
percentages. Active holder stacks contribute to both school totals. Costs
cannot become negative, and free casts do not restart the five-second mana
regeneration delay.

The aura transition rebuilds the owner's seven signed flat-cost fields and
seven floating-point percentage fields. Removal sends explicit zeros, so
tooltips and client cast availability recover immediately. These fields are
private and need no observer projection. The fields now encode as arrays of
32-bit values rather than a single integer or unsupported 224-bit float.

The shared calculation also fixes an existing bug: all-mana spells bypass
cost modifiers, preserving Lay on Hands' full resource drain.

Reference: `Spell::CalculatePowerCost`, `Aura::HandleModPowerCost`, and
`Aura::HandleModPowerCostPCT` in `refs/vmangos/src/game/Spells/`.

## Validation

- `mix test.all`: 2,988 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict` and formatting hooks: passed.
- Focused tests: 42 passed, including the new DBC integration test.
- Tests cover school filtering, stacked positive and negative modifiers,
  talent ordering, percent-of-base costs, zero-cost spending, energy costs,
  all-power costs, signed and floating-point packet fields, private-field
  visibility, cancellation, expiry, and clearing stale projections.
- The DBC test applies actual Burst of Knowledge, checks Healing Wave's
  spending and Lay on Hands' cost, then cancels and expires the aura.

## Real-client acceptance

Used an isolated build-5875 client with level-60 Debugshaman (GUID 8) on
Programmer Isle, with god mode disabled. Existing `.learn` commands supplied
Burst of Knowledge (15646), Healing Wave rank 9 (10396), and Lay on Hands
rank 1 (633). Actions used the client spell API and aura-cancellation API;
read-only Tidewave samplers recorded owner health, mana, cost, aura presence,
and the last mana-spend timestamp.

- Healing Wave rank 9 displayed 560 mana normally and 460 with Burst active.
  Its discounted cast spent exactly 460 mana: 2,895 to 2,435. The sampler
  separately recorded regeneration before cast completion.
- Burst expired naturally after ten seconds, restoring the displayed and
  authoritative cost to 560.
- A second application made Healing Wave rank 1 free. Its cast left the
  last mana-spend timestamp unchanged while ordinary regeneration continued.
  Manual cancellation restored the normal rank-9 cost before natural expiry.
- With Burst active, Lay on Hands spent all 2,935 mana. A subsequent rank-1
  Healing Wave cast was accepted at zero mana without another mana-spend
  timestamp change.
- Applying Burst again and using `.die` removed the aura, cleared both client
  cost arrays, and restored the rank-9 tooltip to 560. The player owner stayed
  alive as a process with character health zero.

No server errors occurred. Existing unsupported account-data, raid-info,
GM-ticket, query-time, and meeting-stone requests were unrelated.

Screenshots: `/home/pikdum/.cache/thistle-wow-playtest.75rVSh/screenshots/`.
Evidence: `/tmp/thistle-power-cost-final-timeline.txt`,
`/tmp/thistle-power-cost-edge-timeline.txt`,
`/tmp/thistle-power-cost-final-state.txt`, and
`/tmp/thistle-power-cost-server.log`.
Validation logs: `/tmp/thistle-power-cost-{focused,all,compile,credo}.log`.
