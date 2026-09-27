# Rotating spell cones and periodic sequences

Implementation: `209f66f9`.

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Spell.cpp` target 54, `WorldObject::HasInArc` in `Object.cpp`, and
`Aura::Update`, `Aura::Refresh`, and `Aura::TriggerSpell` in `SpellAuras.cpp`.

The loader now recognizes target 54 as an enemy cone and an area effect.
Lava Breath and Sand Blast use the existing configured cone path. A shared
`Spell.Cone` value carries the arc and its offset from the caster's facing;
ordinary and scripted cones use the same geometry.

Shadow Bolt Whirl's eight children use 120-degree arcs at 45-degree offsets.
The parent aura, 24834, executes a repeating sequence every five seconds.
VMangos increments the tick counter before selecting the child, so the order
starts with 24821, then 24822, 24823, 24835, 24836, 24837, 24838, and 24820.

Aura tick counts advance once per executed tick. Delayed wakeups do not emit
a burst of catch-up casts. Refresh resets the count while retaining the pending
deadline. Tick merging copies only scheduling state and the counter, preserving
current holder mutations such as consumed absorption.

## Native acceptance

A fresh server ran two isolated build-5875 clients:

- Debugpriest, GUID 4, session `/home/pikdum/.cache/thistle-wow-playtest.Iyom5Q`.
- Debugbuyer, GUID 10, session `/home/pikdum/.cache/thistle-wow-playtest.HyguSX`.

Both characters were raised to level 60 with the existing GM command. The
priest learned spells 19272 and 24834. All casts, turns, duel actions, and aura
cancellation came through the native clients. Neither character used god mode.
Tidewave only sampled owner state and public world/duel projections.

The characters settled on Programmer Isle's northern slope at these positions:

| Actor | X | Y | Z |
| --- | ---: | ---: | ---: |
| Priest | 16306.08398 | 16390.74219 | 50.99858 |
| Warrior | 16312.90430 | 16391.66602 | 46.78411 |

They remained at those positions during the accepted casts. Preparation from
the plateau's elevation caused a fall; health had fully recovered before each
damage case. Native `/duel` after explicit target selection and `AcceptDuel()`
established the active duel.

### Lava Breath

With the priest facing zero, Lava Breath 19272 hit the warrior for 1275 Fire
damage, reducing health from 3379 to 2104. The warrior's combat log showed the
spell and amount. After a native camera turn set facing to 4.86947 radians,
the warrior lay outside the 60-degree cone. Repeated casts caused no further
damage despite the warrior remaining selected and within range.

Evidence: `/tmp/thistle-rotating-cones-lava-front.log`,
`/tmp/thistle-rotating-cones-after-turn.log`, the warrior's `lava-front.png`
and `lava-outside-cone.png`, and the server's three native 19272 cast records.

### Shadow Bolt Whirl

The priest retained facing 4.86947 radians. Relative to that facing, the
stationary warrior was about 89 degrees around the caster: the first three
120-degree arcs cover that direction, while the remaining five do not.

Native spell 24834 applied the parent. Owner samples recorded tick counts
0, 1, 2, then 5 through 8; separate deterministic tests cover every intervening
step. The first two impacts changed warrior health from 3379 to 2480 and 1378.
The native combat log also showed the third impact for 791 damage. The three
hits were 899, 1102, and 791 Shadow damage. During the sample covering ticks
5 through 8, the warrior only regenerated health.

At approximately 42 seconds, native `CancelPlayerBuff` sent `CMSG_CANCEL_AURA`.
The client displayed “Shadow Bolt Whirl fades,” the holder disappeared, and
later samples contained no sequence state. The warrior continued regenerating
without further Whirl damage.

Nearby attackable NPCs were also legitimate recipients of the 100-yard sweep.
They retaliated and eventually killed the priest after cancellation, ending
the duel. This was ordinary combat, with no server errors. The cancellation
sample establishes removal while the priest was still alive; the later death
is not used as evidence of cancellation.

Evidence:

- `/tmp/thistle-rotating-cones-whirl-prepared.log`: positions, facing, full health,
  active duel, and disabled god mode.
- `/tmp/thistle-rotating-cones-whirl-first.log`: application and first two ticks/impacts.
- `/tmp/thistle-rotating-cones-whirl-second.log`: later ticks, regeneration, and cancellation.
- `/tmp/thistle-rotating-cones-whirl-cleanup.log`: absence of the holder after cancellation.
- Priest screenshots `whirl-eight-ticks.png` and `whirl-canceled.png`.
- Warrior screenshot `whirl-sweep.png`: damage feedback and other area recipients.

WoW's own DRM graphics counters increased from 3,906,963,632 to
13,461,469,857 ns for PID 2188426 and from 2,566,216,353 to 12,016,514,779 ns
for PID 2189575. Both sessions used the AMD RX 7900 XT.

The server log `/tmp/thistle-rotating-cones-server.log` contained no gameplay
errors or cast validation failures. Existing account-data and ticket-query
opcode warnings appeared at login.

## Automated checks and cleanup

All 6,980 tests passed with `mix test.all`, compilation passed with warnings
as errors, and strict Credo passed. Focused existing coverage passed 101 tests;
the new sequence and actual-DBC integration coverage passed another eight.

Tests cover a full ring of recipients for every child, nonzero caster facing,
the reference sequence over two cycles, damage and launch recipients, world
isolation, dead/friendly/distant exclusions, area classification, ordinary
trigger preservation, delayed wakeups, refresh, removal, expiry, and death.
No architecture allowlist entries were added.

Logs: `/tmp/thistle-rotating-cones-all-accepted.log`,
`/tmp/thistle-rotating-cones-compile.log`,
`/tmp/thistle-rotating-cones-focused.log`,
`/tmp/thistle-rotating-cones-sequence.log`, and
`/tmp/thistle-rotating-cones-commit.log`.

Both helper-owned services were stopped with empty cgroups; both WoW PIDs
disappeared. The server PTY exited and ports 4000, 3724, and 8085 were free.
Artifacts were retained. Nothing was pushed.
