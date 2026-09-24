# Shapeshift movement and buff cleanup

Druid forms now remove mechanic-bearing roots and removable snares when
entering, changing, or leaving form. This removes the complete spell holder,
including accompanying damage effects. Daze, protected crowd controls, and
effects with no mechanic stay. A new root or snare can still land while
shifted; unrelated aura updates do not repeat the cleanse.

Forms also remove buffs carrying `AURA_INTERRUPT_SHAPESHIFTING_CANCELS`.
Warrior stances, Shadowform, Stealth, and Moonkin retain those buffs, matching
the client's stance flag. Direct casts of sensitive buffs on shifted targets
fail with `bad_targets`. Player and creature owners publish their current form
for shared cast validation. Player publication remains in `World.Presence`.

`Logic.Shapeshift` computes holder removal before the existing aura transition
reconciles roots, speed, movement flags, linked effects, and client updates.
Spell 9033 uses the same cleansing predicate. No dependency allowlist changed.

## Reference and automated verification

VMangos references:

- `Aura::HandleAuraModShapeshift`, `Spells/SpellAuras.cpp`.
- Druid spell 9033 in `Spell::EffectDummy`, `Spells/SpellEffects.cpp`.
- `Unit::RemoveSpellsCausingAuraWithMechanic` and `Unit::IsShapeShifted`,
  `Objects/Unit.cpp`.
- `MECHANIC_NOT_REMOVED_BY_SHAPESHIFT`, `Spells/SpellDefines.h`.
- Aura target restrictions in `Spells/Spell.cpp`.

All 5,709 tests passed with `mix test.all` after the final code change.
`mix compile --warnings-as-errors`, strict Credo, formatting, and whitespace
checks passed. Tests cover form entry, replacement, cancellation, refresh,
mechanic-free effects, whole-spell removal, all protected mechanics, legacy
daze metadata, stance exceptions, area exceptions, the spell-9033 execution
path, owner publication, and recipient validation. Real DBC tests cover Frost
Nova, Entangling Roots, Frostbolt, Hamstring, Concussive Shot, Dazed, Cat Form,
Moonkin Form, and Water Walking.

## Native acceptance

Two isolated build-5875 clients used level-50 Debugdruid (GUID 9) and
Debugbidder (GUID 11, mage) on open map 451. The duel took place at
`{16318.2, 16333.1, 69.4444}` and `{16323.2, 16333.1, 69.4444}`.
God mode was off. Setup, casts, movement, duel acceptance, form cancellation,
and logout used native client input. Tidewave sampled existing owner state
and projections without mutations.

- Water Walking appeared on the druid with movement flag `0x10000000`.
  Cat Form removed the holder and flag; owner and published form both became 1.
- The mage's rank-1 Frost Nova visibly rooted the druid. Cat Form removed the
  root after 1.695 seconds, before its eight-second expiry. A native forward
  key then advanced the druid's X position from 16318.2002 to 16318.3193.
- Rank-1 Frostbolt landed on Cat Form and reduced speed from 7.0 to 4.2
  yards/sec. Clicking the active Cat Form button removed the snare after
  1.925 seconds and restored speed to 7.0 and form to 0.
- Another Frost Nova rooted Cat Form successfully. Clicking the form button
  removed both form and root after 571 ms. This confirms that being shifted
  does not grant permanent root immunity.
- The mage learned Dazed (1604) through `.learn` and cast it normally. It
  reduced speed to 3.5. Cat Form retained Dazed and the reduced speed;
  its original four-second expiry restored 7.0 while Cat Form stayed active.
- The observing mage's target portrait updated to Cat Form. After the duel
  ended, Water Walking on the shifted druid displayed "Invalid target";
  the server logged spell 546 failing validation with `bad_targets`.
- Logout removed the druid owner and metadata. The stored character retained
  Cat Form, speed 7.0, and no root, snare, daze, or Water Walking holder.
  Reconnect displayed Cat Form and restored the same authoritative state and
  published form. No removed control returned.

Native testing also exposed an unhandled `CMSG_MOVE_WATER_WALK_ACK`. The new
codec dispatches to the existing movement sequencer, which now tracks both
Water Walking and Land Walking changes. It validates mover, sequence, and
applied state, ignores stale client movement snapshots, and releases a deferred
spirit teleport after the final acknowledgement. Packet dispatch, mismatched
acknowledgements, enabling/disabling, and deferred release have regression tests.

A fresh server verified that fix with the same druid client. Water Walking
produced counter 1, flag `0x10000000`, and no pending acknowledgements. Cat Form
produced counter 2, removed the flag and holder, and again left no pending
acknowledgements. Telemetry recorded both client acknowledgements; no
unimplemented Water Walking acknowledgement warning remained.

Both WoW processes used their own amdgpu rendering contexts. Graphics counters
increased from 4,833,463,907 to 14,587,827,493 ns for PID 261786 and from
3,983,020,907 to 13,710,715,973 ns for PID 262726.

Neither server run logged an error. Existing unimplemented account-data,
GM-ticket, and meeting-stone requests remain; the first run also contains the
Water Walking acknowledgement warnings fixed above and the expected rejected
buff cast. Both clients and servers were stopped with artifacts retained.

## Evidence

- Druid client and transition traces:
  `/home/pikdum/.cache/thistle-wow-playtest.TtK6rI`.
- Mage client: `/home/pikdum/.cache/thistle-wow-playtest.duruDd`.
- Traces: `root-entry-trace.txt`, `snare-exit-trace.txt`,
  `root-exit-trace.txt`, and `daze-trace.txt` in the druid directory.
- Server: `/tmp/thistle-shapeshift-server.log`.
- Acknowledgement follow-up: `/tmp/thistle-shapeshift-ack-server.log`.
- Full suite: `/tmp/thistle-shapeshift-tests.log`.
- Strict Credo: `/tmp/thistle-shapeshift-credo.log`.
