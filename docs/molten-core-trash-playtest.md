# Molten Core Firewalker and Firelord acceptance

Tested on 2026-10-10 with the native 1.12.1 build-5875 client against a
fresh local server. The source is
`refs/vmangos/src/scripts/eastern_kingdoms/burning_steppes/molten_core/molten_core.cpp`.

## Implemented behavior

- Firewalker enters zone combat, roots itself after six seconds, and fires
  six Fire Blossoms at one-second intervals. Each shot resolves a random
  current opponent. The burst repeats every twelve seconds; Incite Flames
  targets its victim every twenty seconds. Evade and death invalidate any
  unfinished burst receipts.
- Firelord applies its Incinerate retaliation aura on aggro, casts Soul Burn
  on random players, and summons Lava Spawns after 7.5–12.5 seconds and then
  every 15–20 seconds. Each new spawn immediately attacks a random opponent
  of its summoner.
- Wild summons can resolve their summoner and its current opponents through
  the same pure script targeting path as pets. The boundary supplies those
  observations even when they are outside the child's ordinary radius.

## Native acceptance

The isolated GPU session was
`/home/pikdum/.cache/thistle-wow-playtest.427SLO`, unit
`thistle-wow-playtest.427SLO.service`. WoW PID 108935 had amdgpu client 324
inside that cgroup; its graphics counter increased from 4,008,748,219 to
9,301,481,288 ns. Both the client and retained server PTY were stopped after
testing. Screenshots, packet traces, root transitions and `server.log` remain
in the session directory.

Debugshaman (GUID 8, level 60, god mode) entered Blackrock Depths through its
real entrance, then walked through the Molten Core portal while in a raid.
The resulting world was map 409, instance 2. Combatants were ordinary seeded
spawns; nearby unrelated enemies were cleared through `Entity.debug_damage/3`
to isolate each ability chain.

Firewalker DB GUID 91268, runtime GUID 17379391157758333716:

- The client selected Firewalker and displayed the blossom effects.
- In a 43-second owner packet trace, roots occurred at 3.052, 15.076, 27.090
  and 39.108 seconds. Each complete burst contained exactly six shots,
  separated by approximately one second, hitting GUID 8.
- Incite Flames occurred at 17.080 and 37.105 seconds.
- A separate owner sampler observed the root aura and one pending burst,
  followed by the aura's removal and zero pending bursts about six seconds
  later. Teleporting away reset combat and left zero active scripts.

Firelord DB GUID 56785, runtime GUID 17379391157791888222:

- Aggro applied aura 19396; actual client melee swings triggered Incinerate
  19397 on the player. Soul Burn 19393 appeared on the player and repeated
  about every four seconds, within the EventAI tick's timer resolution.
- Split 19569 occurred at 13.426 and 30.441 seconds in a trace whose aggro
  occurred at 2.415 seconds. The first Lava Spawn was observed 68 ms after
  the summon packet, already fighting GUID 8, visible to the client, and in
  the same world as its Firelord summoner.
- The client selected Lava Spawn and displayed its split announcements.
  Existing database EventAI multiplied the spawns, removed their parents,
  and retained engagement in the descendants. All six children in the final
  sample were alive, visible, in the same copy, and attacking GUID 8.
- The fresh server log contained no warnings or errors.

## Bug found and fixed

The first native trace exposed additional Firewalker casts from its database
spell list. VMangos's overridden `UpdateAI` handles its own timers and never
calls `UpdateSpellsList`; this port was also running the generic spell-list
subtree. Both new scripts now select an empty generic list on each aggro,
while retaining their spellbook for scripted casts. A regression exercises
default-list presence, combat entry, reset, and a second pull. The fresh
native trace confirmed that the additional casts disappeared.

## Automated validation

`devenv shell mix test.all`: 8,802 passed. Compilation with warnings as
errors, strict Credo, formatting, and `git diff --check` passed. Focused
creature-script, observation and architecture checks passed: 40 tests, one
excluded map integration test.

Implementation: `de1ceb8b`; duplicate-cast repair: `3e2147fe`.
