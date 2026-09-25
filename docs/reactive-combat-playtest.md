# Reactive combat windows acceptance

Validated on 2026-09-25 with the native WoW 1.12.1 build-5875 client.
Implementation: `ad849c08`; expiry scheduling follow-up: `365334df`.

## Rules and regression coverage

Reference: VMangos `8f4e60845`, `Unit::ProcSkillsAndReactives`,
`Unit::UpdateReactives`, `Unit::ClearAllReactives`, and the Mongoose Bite and
Counterattack scripts in `spell_hunter.cpp`.

- Hunter dodge opens the Defense state (`0x01`); Hunter parry opens the separate
  Hunter Parry state (`0x40`) and updates the client combo target marker. Each
  window retains its own attacker and four-second deadline.
- Mongoose Bite and Counterattack validate their respective attacker. One
  reaction no longer replaces the other ability's target or timer.
- Rogue dodge does not open or refresh Riposte. Parrying either an ordinary
  swing or a special attack opens Defense. Warrior Revenge and Overpower keep
  their existing class rules.
- Lethal damage clears both defensive windows and combo state through the
  shared death transition. Login also clears transient reactive state.
- The behavior tick policy schedules the earliest defensive or Overpower
  expiry, including after combat has ended.

Deterministic tests cover ordinary and special attacks, overlapping targets,
refreshes, exact expiry boundaries, cast validation, death/resurrection,
preservation of unrelated aura states, idle scheduling, and native DBC aura
state requirements for all affected ability ranks.

## Hunter client acceptance

Session: `/home/pikdum/.cache/thistle-wow-playtest.776xAU`.
Server log: `/tmp/thistle-reactive-server.log`.

Debughunter fought the seeded Skeletal Flayers on Programmer Isle. The client
learned Counterattack `19306`, Deterrence `19263`, and Deflection `19300` through
ordinary developer chat commands. God mode prevented incoming damage during
the combat checks. Casts used the native action button or `/cast` commands.

Client-side `IsUsableAction` diagnostics displayed all four combinations of
Mongoose Bite and Counterattack availability. Screenshots `hunter-active.png`
and `hunter-results.png` retain these transitions and the action bars.

The read-only trace `/tmp/thistle-reactive-hunter-confirmed.log` captured both
bits (`65`), followed by Hunter Parry alone (`64`), then neither (`0`). At the
first overlapping sample, the dodge deadline was `11,468 ms` and the parry
deadline was `12,769 ms` relative to the sampler start. Refreshing parry moved
only its deadline to `14,070 ms`.

The server recorded successful native casts of Mongoose Bite `14270` and
Counterattack `19306` against GUID `17379390991937510292`.
`/tmp/thistle-reactive-hunter-damage-root.log` captured the target changing from
498 to 448 health as the Counterattack aura and cooldown appeared. The root
remained after both reactive windows had expired.
`hunter-successful-casts.png` shows the damaged target and Counterattack's
native tooltip and cooldown presentation.

After disabling god mode, `.die` produced the native death screen
(`hunter-dead.png`). The death trace retained zero reactive bits and empty
windows. Active-window cleanup before natural expiry is covered by the lethal
damage regression test. Reconnecting the Hunter restored ghost state with
empty defensive windows, zero combo points, and no internal combo target:
`/tmp/thistle-reactive-hunter-reconnect.log`. Its remaining aura-state bit `2`
was the health state, not a reactive window.

## Expiry scheduling follow-up and Rogue acceptance

The first Hunter trace exposed delayed client state cleanup: a window expiring
at `11,468 ms` was first observed cleared at `12,320 ms`. Cast validation already
rejected expired windows, but the general behavior cadence could leave the
button lit in the meantime. Commit `365334df` adds reactive deadlines to the
existing tick plan rather than introducing another timer owner.

A fresh server and native client validated the final implementation:

- Session: `/home/pikdum/.cache/thistle-wow-playtest.DPcfGG`.
- Server log: `/tmp/thistle-reactive-final-server.log`.
- Character: Debugrogue, with Riposte `14251` and Deflection `13856` learned.
- Target: the seeded Skeletal Flayers; god mode enabled for combat acceptance.

`rogue-avoidance.png` shows Evasion, a visible Dodge, and unavailable Riposte.
During the 25-second initial trace, the defensive window remained empty and
the aura state stayed zero despite repeated dodges.
`rogue-riposte-combat.png` also records native dodge messages with
`Riposte=nil`, alongside the rejected cast feedback.

Subsequent parries enabled Riposte; `rogue-windows.png` records native parry
messages and the availability transitions. The server accepted Riposte casts,
and `/tmp/thistle-reactive-rogue-casts.log` captured the target changing from
536 to 411 health as Disarm aura `14251` and the new cooldown appeared. Disarm
expired afterward. Riposte's defensive window remained independent of that
aura's lifetime.

The same trace records a reactive deadline at `862 ms` and the first cleared
sample at `932 ms`; another deadline at `12,057 ms` was cleared in the sample
recorded at `12,125 ms`. Each sampler row is timestamped after a 50 ms sleep,
so these timestamps include that observation delay. The prior general-tick
delay is absent.

## Verification and cleanup

- `mix test.all`: **6,236 passed**, 66.8 seconds;
  `/tmp/thistle-reactive-final-tests.log`.
- `mix compile --warnings-as-errors`: passed;
  `/tmp/thistle-reactive-final-compile.log`.
- `mix credo --strict`: zero issues;
  `/tmp/thistle-reactive-final-credo.log`.
- Both native sessions used the GPU renderer. The final WoW process itself
  reported `amdgpu` and increasing graphics-engine counters, from
  `3,902,151,155 ns` to `10,774,992,639 ns`; see
  `/tmp/thistle-reactive-rogue-gpu-start.log` and
  `/tmp/thistle-reactive-rogue-gpu-end.log`.
- No owner crashes, rescued gameplay errors, or server cast-validation
  warnings occurred. The logs contain the existing unrelated account-data,
  GM-ticket, and meeting-stone unimplemented-message warnings.
- Both helper-owned client services and both retained server processes were
  stopped. Screenshots and logs were retained. No push was performed.
