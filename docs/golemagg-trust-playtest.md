# Golemagg's Trust acceptance

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

Final validation passed on 2026-10-11: `mix test.all` passed all 8,852 tests;
`mix compile --warnings-as-errors`, `mix credo --strict`, and
`mix format --check-formatted` passed.

## Native acceptance

A fresh native 1.12.1 build-5875 client entered Blackrock Depths through its
real entrance and then the Molten Core portal, reaching map 409, copy 2.
Debugshaman (GUID 8) was level 60 with god mode. Debugwarrior (GUID 1) provided
the raid partner through an owned headless connection and stayed on Programmer
Isle. A separate raid admitted Debugpaladin (GUID 2) to copy 3 through normal
instance destination and worldport acknowledgement; Debugrogue (GUID 3) stayed
on Programmer Isle.

The accepted repeat used a fresh GPU client session
`/home/pikdum/.cache/thistle-wow-playtest.qOoOel`, service
`thistle-wow-playtest.qOoOel.service`, invocation
`7f6d73adaef84f9da1c39891203aabda`. WoW PID 228089 belonged to that cgroup and
used amdgpu client 660. Its graphics counter increased from 18,606,350,525 to
26,433,786,077 ns between retained reads. The client entered both instances
through their real portals. No screenshots were attached to the agent's
conversation; retained captures and client Lua text probes supplied UI evidence.

The native player was level 60 with god mode. Existing script commands stopped
combat movement and moved the selected rager to controlled distances. A
224.206-second trace retained 1,078 state samples and 925 projected messages
to the native player owner:

- Golemagg refreshed both fighting ragers at one-second intervals. All 305
  Trust casts named the same boss as caster and exactly one recipient each.
  Normal adjacent intervals were 997–1,002 ms.
- The selected rager moved from inside the radius to 40 yards from the boss's
  center, outside the 30-yard surface radius but inside its reset leash.
  Trust expired, damage bonus returned to zero, swing period returned to
  2,000 ms, and scale returned from 1.8 to 1.5. The other rager stayed buffed.
- Moving that rager back to 10 yards restored Trust, the 500 damage bonus,
  1,333 ms swings, and scale 1.8. Refreshes retained the boss's caster GUID.
- Moving the native player away stopped combat. The existing boundary evade
  API then reset the boss and ragers. After the ragers' temporary spawn auras
  expired, the idle encounter produced no boss-sourced Trust casts. The boss's
  permanent pulse aura was restored and remained idle.
- The native player returned, selected Golemagg, and used `.damage 10000`.
  The second pull restored the same buff behavior and left the boss at
  816,088/826,088 health.
- Copy 3's three units retained full health, idle combat state, base swing
  periods, and their original incarnations throughout acceptance. Zero
  projected messages referenced their GUIDs, and none entered the native
  player's visible or tracked roster.

The client itself reported `UnitAttackSpeed("target")` through ordinary chat:
1.333 seconds nearby, 2 seconds outside the radius, 1.333 seconds after returning,
2 seconds after reset, and 1.333 seconds on the second pull. This verifies that
the client received and applied the swing-period projection. The retained
accepted capture includes the final client readout. Runtime memory stayed
between 1,449,525,984 and 2,980,242,232 bytes during the accepted trace.

| Unit | Seed DB GUID | Runtime GUID in copy 2 |
| --- | --- | --- |
| Golemagg | 56684 | 17379391163160597291 |
| Core Rager | 56685 | 17379391157858997026 |
| Core Rager | 56699 | 17379391157858997017 |

Acceptance was saved before the separate Firelord overload investigation.
That investigation deliberately engaged copy 3 after the isolation trace had
ended; its resulting state is not part of this acceptance.

## Earlier interrupted attempt

The playtest server exited during preparation. The kernel reported a global
OOM kill of BEAM PID 191327 at 2026-10-10 21:06:11 local time, with anonymous
RSS 19,183,040 KiB. The last gameplay telemetry reported 17,053,439,584 bytes
of runtime memory, 3,165 mobs, and run queue 1,574. Those original observations
did not establish an allocation cause. The subsequent acceptance and separate
Firelord reproduction are recorded above and in `golemagg-playtest-overload.md`.

The earlier client was stopped through its helper-owned service invocation.
The server and its headless owners were already terminal. The accepted repeat
above replaces that incomplete attempt; the separate overload investigation
is recorded in `golemagg-playtest-overload.md`.

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

The accepted session retains `thistle-trust-state.jsonl`,
`thistle-trust-packets.jsonl`, `thistle-trust-isolation.json`,
`thistle-trust-acceptance-summary.json`, final validation logs, GPU records,
and the accepted client capture. Its client was stopped through the recorded
service invocation. The subsequent overload reproduction's server exited,
ending its headless owners too.
