# Golemagg's Trust validation and pending acceptance

Implementation commit: `d71a3c0c`.

Golemagg's aura 20556 now refreshes Trust 20553 every second only while its
living caster is engaged. The duplicate creature combat timer was removed.
The scripted pulse selects living Core Ragers within a strict 30-yard
horizontal surface radius, including both bounding radii, in the caster's
world copy. Each rager receives one triggered cast with Golemagg as its source.
The shared typed request is `Effects.TriggerCreatureSpellInRange`.

The reference is `GolemaggsTrustScript` in
`refs/vmangos/src/scripts/eastern_kingdoms/burning_steppes/molten_core/boss_golemagg.cpp`,
with the horizontal distance filter in `AllCreaturesOfEntryInRange` in
`refs/vmangos/src/game/Maps/GridNotifiers.h`. Current supported spell data
represents 20556 as a periodic trigger; the handler also supports the scripted
dummy-aura form. Buff 20553 lasts two seconds, adds 500 physical damage,
increases melee attack speed by 50%, and increases scale by 20%.

## Completed checks

The idle-pulse regression failed before the fix: an idle boss emitted a
triggered cast instead of an empty event list. The focused suite passed all
33 tests afterward, including:

- combat-only one-second pulses, idle/dead/foreign-caster suppression, and
  the scripted dummy form;
- strict horizontal radius, both bounding radii, vertical separation,
  life state, absent owners, and instance isolation;
- one cast per recipient, boss caster identity, normal buff expiry, damage
  bonus, and swing periods changing from 2,000 to 1,333 ms and back;
- actual DBC pulse/buff data, the VMangos script label, existing periodic
  triggers and Separation Anxiety, Molten Core scripts, and architecture.

`mix compile --warnings-as-errors` passed. The implementation commit's strict
Credo and formatting hooks passed. Full `mix test.all` has not been run for
this change. The previous Core Rager leash milestone passed 8,843 tests; that
result does not validate this implementation.

## Pending native acceptance

A fresh native 1.12.1 build-5875 client entered Blackrock Depths through its
real entrance and then the Molten Core portal, reaching map 409, copy 2.
Debugshaman (GUID 8) was level 60 with god mode. Debugwarrior (GUID 1) provided
the raid partner through an owned headless connection and stayed on Programmer
Isle. A separate raid admitted Debugpaladin (GUID 2) to copy 3 through normal
instance destination and worldport acknowledgement; Debugrogue (GUID 3) stayed
on Programmer Isle.

Preparation observed 20553 with Golemagg as caster on both engaged ragers,
500 physical damage bonus, and 1,333 ms swing periods. This is an isolated
state read, not accepted native lifecycle evidence. The attempted continuous
sampler did not complete, so native packet delivery, distance departure and
return, post-wipe idle suppression, repeat pull, and copy isolation remain
unverified. No accepted native trace was produced.

The playtest server exited during preparation. The kernel reported a global
OOM kill of BEAM PID 191327 at 2026-10-10 21:06:11 local time, with anonymous
RSS 19,183,040 KiB. The last gameplay telemetry reported 17,053,439,584 bytes
of runtime memory, 3,165 mobs, and run queue 1,574. The cause is unresolved;
these observations do not establish whether the new pulse, fixture movement,
another gameplay path, or another component caused the growth. Investigate
that failure before claiming acceptance.

The client was stopped through its recorded helper-owned service invocation.
The server was already terminal. Its headless player owners ended with the
server. The work is paused with native acceptance, the OOM investigation,
and the full suite outstanding.

Evidence directory: `/home/pikdum/.cache/thistle-wow-playtest.EtdcRa`.
Owned unit: `thistle-wow-playtest.EtdcRa.service`; invocation:
`767b8e0ed1c84029ac142e09795f42b7`. The retained logs include:

- `thistle-golemagg-trust-idle-before.log`
- `thistle-golemagg-trust-focused.log`
- `thistle-golemagg-trust-compile.log`
- `thistle-golemagg-trust-server.log`
- `kernel-oom.txt`

Preparation screenshots and GPU ownership records are retained there; they
do not substitute for the missing acceptance trace.
