# Parry haste

Parried auto-attacks now advance the defender's next melee swing. This
applies to players and mobs through `Combat.receive_attack/4`. The pure
`ParryHaste` module updates the existing combat blackboard; no additional
timer or persistent state is introduced. Mob attack delivery already wakes
AI. Player attack delivery now replaces the pending tick when its combat
blackboard changes, so the earlier swing deadline is actually honored.

Rules follow the pinned `refs/vmangos/src/game/Objects/Unit.cpp`,
`Unit::DealMeleeDamage`, and `Objects/Unit.h`, `GetAttackTime`:

- Choose the hand due first; ties favor the main hand.
- Subtract 40% of that hand's unmodified weapon period.
- Floor the remaining wait at 20% of that period.
- Leave swings already within the floor, ready swings, and absent timers alone.
- Use the unmodified period even under melee haste, matching VMangos.

The reference applies this in auto-attack damage delivery. Separately
resolved spell misses are unchanged. Ranged attacks cannot roll a parry.
Dual wielding and threshold cases are covered automatically; the live
check used a warrior's main hand and ordinary mob swings.

## Real-client acceptance

Used an isolated build-5875 client with Debugwarrior, level 50, on Programmer
Isle. The existing `.tgm` command kept the character alive. Combat and
movement were driven through normal client input; runtime inspection only
read entity owners.

1. Wait for `Debug seed ready`, log in, and select Debugwarrior.
2. Enable `.tgm` and use `.go xyz 16260 16338 69.44 451`.
3. Select a living Skeletal Flayer with Tab and start auto-attack using
   `/script AttackTarget()`.
4. Face the enemies. Holding Left through the helper's
   `key SESSION --delay 1500 Left` produced about 2.26 radians of rotation.
5. Sample player and target combat deadlines while exchanging melee swings.

The accepted sequence used warrior GUID 1 and Skeletal Flayer GUID
17379390991937510294. The following are server monotonic milliseconds:

| Defender | Weapon period | Original deadline | Deadline after parry | Next swing observed |
| --- | --- | --- | --- | --- |
| Warrior | 2,100 | -576460467165 | -576460468005 | -576460467966 |
| Flayer | 1,300 | -576460474719 | -576460475239 | -576460475225 |

The warrior's deadline moved 840 ms earlier and the mob's moved 520 ms
earlier. The sampler observed each following swing within 39 ms and 14 ms
of its new deadline, respectively, both before the original deadline.
The warrior's authoritative reactive outcome was `:parry`. Additional
samples recorded floor-limited reductions of 4 ms for the warrior and
349 ms for the mob. Screenshots show ongoing client combat, targeting,
damage feedback, and the combat log.
The client's saved combat log also records `Skeletal Flayer attacks. You
parry.` at 02:48:10.079, 02:48:19.247, 02:49:14.190, and 02:49:18.159.

Initial sampling with the warrior facing away did not establish player
parries. A Lua turning macro was blocked by the client; keyboard turning
worked. Repeated samplers initially shared a file, leaving sparse zero
bytes; the retained evidence file strips those bytes. The table above uses
complete, chronological records from the accepted sequence.

No gameplay owner crashes or server errors occurred. Existing unimplemented
login/query, account-data, and cancel-trade packet warnings were present.

Evidence retained locally:

- `/home/pikdum/.cache/thistle-wow-playtest.wGTyIw/screenshots/`
- `/home/pikdum/.cache/thistle-wow-playtest.wGTyIw/combat-log.txt`
- `/tmp/thistle-parry-evidence.log`
- `/tmp/thistle-parry-server.log`
- `/tmp/thistle-parry-tests.log`

Validation: `mix compile --warnings-as-errors`, `mix test.all` (2,798
passing tests), `mix credo --strict`, formatting, and diff checks.
The isolated client, X server, and local game server were stopped afterward.
