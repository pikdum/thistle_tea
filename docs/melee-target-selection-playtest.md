# Melee targets and player selection

Implemented in `b689afe0` and accepted with the native build-5875 client on
2026-09-28.

## Behavior and reference

Player selection and an active melee victim have different lifetimes. VMangos
`8f4e608450460efe1e38743e4da74397d4773a3a` keeps `m_curSelectionGuid` separately
from `m_attacking`. `Player::SetSelectionGuid` also updates the replicated target,
but `Unit::AttackStop` clears that field only when an attack exists and sends the
stop packet for the actual victim. `Unit::Attack` stops the previous victim when
switching and leaves repeated starts against the same victim alone.

Thistle Tea now uses the existing blackboard `TargetRef` for player melee
behavior, range and facing checks, extra attacks, and stop notifications. A
selection change cannot redirect a swing. Switching victims preserves weapon
deadlines, interrupts the old queued melee spell, and permits fresh attack-start
feedback. The first attack retains already queued swings and extra attacks.

Stopping an idle attack preserves the replicated selection. Stopping an active
attack clears that field while retaining the session's client selection, as in
the reference. Death, teleport, and possession retain their stronger cleanup.
Duel cleanup uses the same attack-stop transition. Invalid victim lifetimes stop
through that transition, including before the player has entered combat.

## Automated validation

- `mix test.all`: 7,414 passed in 80.1 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: no issues.
- Commit hooks: Credo and formatting passed.

Regressions cover selection changes, idle and repeated stops, victim switching,
queued abilities, extra attacks, swing deadlines, stale victims, distant victim
observations, and duel cleanup. Existing death, teleport, possession, charm,
facing, and weapon-readiness tests also pass. No architecture allowlist changed.

Logs: `/tmp/thistle-melee-target-tests-final.log`,
`/tmp/thistle-melee-target-compile.log`, and
`/tmp/thistle-melee-target-credo-final.log`.

## Native acceptance

The server started with the committed modules; no live recompilation was used.
Debugmage (GUID 5, level 60) and Debugpaladin (GUID 2) used native chat commands,
targeting, spell casts, and keyboard turning on Programmer Isle. God mode
prevented player deaths without changing attack decisions. Tidewave only read
small owner snapshots.

- Debugmage began melee against the Urok Enforcer and switched to the Urok Ogre
  Magus. The new victim had GUID `17379391139895780996`, incarnation 57, and
  `attack_started: true`. Its health fell from 10,455 to 10,176 and then 10,017.
- The Enforcer initially produced the expected bad-facing feedback. After native
  keyboard turning, its health fell from 12,665 to 12,550. Its active target
  reference was GUID `17379391139879003781`, incarnation 58.
- Toggling the native Attack action off retained the Magus portrait and session
  selection, with replicated target zero, no melee reference, and
  `attack_started: false`.
- After stopping and explicitly reselecting the Enforcer, an idle Polymorph
  (rank 1) completed with aura 118 and sheep display 856. The caster retained the
  Enforcer in both selection fields, with no melee reference.
- Debugpaladin cleared its selection before `/assist Debugmage`. It selected the
  same Enforcer and displayed the sheep and Polymorph debuff, confirming the
  observer received the retained target.
- Teleporting both players away cleared their replicated targets, melee
  references, attack intent, and threat references.

This client uses `AttackTarget()` to toggle melee. An attempted `StopAttack()`
call produced a client Lua error because that API is absent in 1.12; dismissing
the modal and using the native toggle completed the stop check.

The server log contains no gameplay errors. Its only warnings are the existing
`CMSG_UPDATE_ACCOUNT_DATA` and `CMSG_GMTICKET_GETTICKET` messages.

## Retained evidence and cleanup

- Mage session: `/home/pikdum/.cache/thistle-wow-playtest.0CHf07`.
- Observer session: `/home/pikdum/.cache/thistle-wow-playtest.bsPXQC`.
- Screenshots include `attack-switch`, `stopped-selection`, `idle-polymorph`,
  and the observer's `assist-polymorph`.
- Owner snapshots: `/tmp/thistle-melee-native-{magus,enforcer,stop,idle-polymorph,observer,cleanup}.log`.
- Server log: `/tmp/thistle-melee-target-server.log`.

Both WoW processes had their own `amdgpu` DRM counters with nonzero graphics
time and VRAM usage. Both helper-owned systemd sessions and the fresh server
were stopped after acceptance; artifacts were retained. No changes were pushed.
