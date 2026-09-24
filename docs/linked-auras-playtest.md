# Linked auras and Barkskin

## Implementation

`741b8045` adds shared support for aura 192, which attaches a passive spell to
an active parent aura. Spell loading resolves child definitions at the boundary
and cuts missing or cyclic references. Pure `Aura.Linked` reconciliation runs
through the existing aura transition funnel; gameplay does not query the DB.

Each child belongs to a particular parent application. Refresh replaces that
generation, and parent removal removes its descendants. Children retain their
own charges and duration. An unrelated transition cannot recreate a consumed
or expired child, and removing a parent preserves independently applied copies
of the same spell. Periodic children cannot tick after their parent expires.

The VMangos override for Barkskin (22812) links Barkskin Effect (DND), spell
22839. The parent supplies pushback protection and the extra second of cast
time; the hidden child supplies 20% physical damage reduction and 25% longer
melee attack periods. Both actual Vanilla definitions last 15 seconds.

`b5de6f32` fixes attack periods exposed by this implementation. `AttackSpeed`
derives all three projected weapon periods from canonical weapon inputs,
shapeshift, disarm, equipment haste, and aura modifiers. Positive haste divides
the period; a negative modifier increases it directly. Independent modifiers
multiply, while ordinary melee slows use the strongest penalty and passive
penalties coexist. Aura 9 affects all weapon hands; aura 138 affects melee only.

Combat and client fields now use the same derived periods. Damage calculations,
proc rates, and parry haste retain unmodified weapon periods where required;
ranged haste no longer reduces damage per shot. Equipment sync supplies the
new canonical offhand input. Units without a canonical input keep their
existing projection. Attack-time fields remain integers on the wire, matching
VMangos's explicit conversion during object updates.

References:

- `refs/vmangos/src/game/Spells/SpellAuras.cpp`: `HandleAuraAuraSpell`,
  `HandleModAttackSpeed`, `HandleModMeleeSpeedPct`, and `ComputeExclusive`.
- `refs/vmangos/src/game/Objects/Unit.cpp`: `ApplyAttackTimePercentMod`.
- `refs/vmangos/src/game/Objects/Unit.h`: `GetAttackTime`.
- `refs/vmangos/src/game/Objects/Object.cpp`: attack-time update conversion.
- Generated VMangos `spell_effect_mod` and DBC spell rows for 22812 and 22839.

## Automated validation

Tests cover child ownership, refresh, rejection, independent copies, nested
links, consumed state, every transition removal cause, expiry, death, and late
periodic ticks. Separate DBC and VMangos tests verify the real definitions and
override. The DBC-backed Barkskin test verifies 100 physical damage becomes 80,
cast-time and pushback changes, and complete restoration on expiry.

Attack-speed tests cover both melee hands, multiplicative modifiers, exclusive
slows, ranged separation, quivers, weapon swaps, forms, missing canonical inputs,
and stable damage and attack-power snapshots. Existing parry, wand, rogue,
warrior, and target-attack-power coverage remains green.

All source gates passed on `b5de6f32` before the native server launched:

- `mix test.all`: 5,392 passed, including DBC, VMangos, and map integration.
- `mix compile --warnings-as-errors`.
- `mix credo --strict`: zero issues.
- `mix format --check-formatted`, `git diff --check`, and commit hooks.

Logs: `/tmp/thistle-barkskin-tests.log` and `/tmp/thistle-barkskin-credo.log`.
No source changed after these gates or during native acceptance.

## Native acceptance

A fresh server on `b5de6f32` used genuine build-5875 clients on Programmer Isle:
Debugdruid (9) and Debugwarrior (1), both level 60 with god mode disabled. Native
casts, a requested and accepted duel, buff cancellation, spirit release,
corpse retrieval, and reconnect drove the checks. Runtime probes only read state.

- Barkskin produced one visible parent and one hidden child. The owner's
  physical multiplier was 0.8 and attack period was 2,500 ms. Native
  `UnitAttackSpeed("player")` changed from 2.0 to 2.5 seconds. Natural expiry
  removed both holders and restored 2,000 ms and multiplier 1.0.
- During the duel, protected Healing Touch (9888) took 4,500 ms. Two melee hits
  reduced health from 2,281 to 2,186 to 2,100 without changing its cast deadline
  or adding pushback. The cast completed and healed the druid to 2,373.
- After expiry, the same spell took 3,500 ms. Incoming attacks increased
  pushback count from zero to one to two; native events reported 634 and 800 ms
  delays. The client displayed the restored 2.0-second attack period.
- The warrior's target query displayed 2.5 seconds during a fresh Barkskin.
  Native cancellation removed both holders, and the observer subsequently
  displayed 2.0 seconds. Native hit amounts vary with weapon rolls and armor;
  the exact 20% reduction is established by the deterministic tests and live
  modifier, rather than inferred from those varying samples.
- Death during another Barkskin removed both holders and restored 2,000 ms.
  The client displayed Release Spirit with no Barkskin icon. After release,
  a developer teleport shortened the corpse run and native `RetrieveCorpse()`
  restored the living druid with no linked effects or finalized-death state.
- Disconnecting during a fresh cast saved both holders and the 2,500 ms period
  in the runtime character store. After their deadline, reconnect removed both
  holders and restored 2,000 ms. The client displayed normal controls and
  attack speed; keyboard input moved x=16303.2 to x=16306.7.

The native server log contains no error-level entries, owner crashes, or spell
validation failures. Existing unimplemented account-data, ticket, and
meeting-stone requests remain outside this change.

## Evidence and cleanup

Sessions under `/home/pikdum/.cache/thistle-wow-playtest.*`:

- Druid: `PIN6mm`, including `barkskin-active.png`, `protected-cast.png`,
  `restored-casting.png`, `cancelled.png`, `death-cleanup.png`, and `recovered.png`
  under `screenshots/`.
- Warrior: `1E15kD`, including `observer-speed.png` and `observer-restored.png`.
- Reconnected druid: `zdIJ1c`, including `reconnected-movement.png`.

Both initial WoW processes used `amdgpu` device `0000:0c:00.0`. Druid PID 2524583's
graphics counter advanced from 640,168,737 to 27,313,863,743 ns; warrior PID
2525735's advanced from 5,046,341,548 to 22,540,800,907 ns.

Runtime captures use `/tmp/thistle-barkskin-*.txt`: `protected-cast`,
`unprotected-cast`, `expiry`, `before-cancel`, `cancel`, `before-death`, `death`,
`recovered`, `before-disconnect`, `disconnected`, `reconnected`, and
`reconnected-movement`. The protected-cast capture truncates its final sample;
the earlier cast, damage, unchanged deadline, and completed heal are retained.
GPU evidence uses `gpu-{start,end}` and `warrior-gpu-{start,end}`. The server log
is `/tmp/thistle-barkskin-server.log`.

All three helper-owned clients and the retained server were stopped after
acceptance. Artifacts were retained. Nothing was pushed. This completes linked
aura support and the associated attack-period corrections; broader Vanilla
parity remains ongoing.
