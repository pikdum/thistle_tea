# Pacification and silence

DBC aura 60 now loads as `mod_pacify_silence`. Combined control shares the
same derived restrictions and client flags as ordinary pacification and
silence. It supports Wisp Costume, Gift of Stone, Web Wrap, and other spells
using that aura without spell-specific handling.

Silence prevents spells whose prevention type is silence; pacification
prevents pacify-sensitive abilities, both melee hands, queued swing attacks,
extra attacks, and ranged auto-repeat. Neither control roots the target.
Spells with no prevention type remain available. Overlapping independent
and combined holders retain each restriction until its final source ends.

Two related bugs were fixed:

- Ordinary pacification did not suppress the shared auto-attack execution
  path. Pacified swings now wait without spending the queued ability, and
  ranged auto-repeat cancels without delivering a shot or consuming ammo.
- Aura interruption cleared casting fields without normal channel cleanup
  or failure feedback. It now uses `Casting.cancel/1` and typed interruption
  feedback, including channel timers, remote auras, and owned channel objects.

VMangos references: `Aura::HandleAuraModPacifyAndSilence`,
`Aura::HandleAuraModSilence`, and `Unit::CanAutoAttackTarget` in
`refs/vmangos/src/game/Spells/SpellAuras.cpp` and
`refs/vmangos/src/game/Objects/Unit.cpp`.

## Client acceptance

An isolated World of Warcraft 1.12.1 build-5875 client controlled level-50
Debughunter on Programmer Isle against a fresh local server. Existing `.learn`
commands supplied Wisp Costume (24740) and Gift of Stone (16470). All casts,
movement, and cancellation used client input; Tidewave probes were read-only.

- Wisp Costume displayed the wisp model and buff. Authoritative display ID
  changed from 54 to 10045, and unit flags from 32776 to 172040. Both control
  predicates were true.
- Mend Pet displayed "Can't do that while silenced". Raptor Strike displayed
  "Can't attack while pacified". The client rejected these actions locally;
  automated cast-validation tests separately exercise server rejection.
- Forward movement changed X from 16303.2002 to 16303.6758 while both controls
  remained active.
- Right-click cancellation restored the original model and flags. Mend Pet
  then visibly channeled, and the server logged its normal cast.
- Gift of Stone displayed its ten-second buff and armor bonus. A 250-ms owner
  sampler recorded `{false, false, 32776, 896}`, then
  `{true, true, 172040, 1896}`, then the original state after natural expiry.
  The tuples contain pacification, silence, flags, and armor, respectively.
- After expiry, Mend Pet channeled again and Raptor Strike was accepted into
  `next_swing_spell` as spell 14265.

Automated coverage additionally verifies refresh deadlines, overlapping
sources, death cleanup, interruption of active casts and channels, state
immunity feedback, both melee hands resuming, extra-attack suppression, and
ranged cancellation. Real DBC tests cover Wisp Costume and all four Web Wrap
variants. Active-channel interruption, death, creature combat, and a second
observer were not exercised in the client session.

No error-level server logs occurred. The existing unimplemented account-data,
raid-info, GM-ticket, time-query, and meeting-stone UI requests appeared as
warnings. The isolated client and retained server were stopped afterward.

## Evidence

- Screenshots: `/home/pikdum/.cache/thistle-wow-playtest.8dqHQb/screenshots/`.
- Server: `/tmp/thistle-combat-control-server.log`.
- Owner probes: `/tmp/thistle-combat-control-{wisp,moved,released,expiry,restored-attack}.txt`.
- Full suite: `/tmp/thistle-combat-control-tests.log` — 3,445 tests passed.
- Strict Credo: `/tmp/thistle-combat-control-credo.log` — no issues.
- `mix compile --warnings-as-errors` passed.
