# Net-o-Matic backfires and charge movement

Implementation: `10d944e8`. Nonweapon accuracy fix: `02a982cc`.
Reference: local VMangos revision `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Spells/SpellEffects.cpp`, `Spells/SpellAuras.cpp`, `Spells/Spell.cpp`,
`Objects/SpellCaster.cpp`, `Movement/PointMovementGenerator.cpp`, and
`Maps/PathFinder.cpp`.

Gnomish Net-o-Matic Projector (10720) now resolves its dummy spell through the
shared weighted-effect pipeline. The target requests one outcome from the
caster, preserving ownership of triggered movement and spell delivery.

| Weight | Outcome |
| --- | --- |
| 80% | Spell 13099 roots the target for ten seconds. |
| 10% | Spell 16566 roots the caster for thirty seconds. |
| 10% | Spell 13119 charges toward the target and applies a twenty-second root; its transient marker 13139 triggers the caster's twenty-second root, 13138. |

These weights follow the current local reference. VMangos itself labels the
historical backfire probabilities uncertain. Marker 13139 never enters the
retained aura list, preventing a permanent marker or another self-root on login.
Caster-directed trigger effects no longer add a duplicate execution recipient
for this mixed-target spell. Explicit trigger roles survive owner handoff and
allow the backfire's enemy-selector aura to affect its caster.

Triggered spells now resolve charge paths at launch. Player and creature owners
accept the same command and publish the movement from their resulting state,
so the packet and authoritative spline share an ID and duration. Paths approach
the target's melee reach; speed is four times running speed, capped at 24 yards
per second, following the reference. Dead, rooted, taxi-bound, self-targeted,
and cross-world movement is rejected. Owner admission checks again when a
queued path arrives.

New roots and stuns defer movement blocking until an active charge finishes.
Ordinary creature behavior waits for charge arrival. Interruption applies any
pending root at the current position; death clears charge state; an old arrival
cannot halt a superseding spline. Existing logout and teleport funnels retain
ownership of cancellation.

Testing also exposed incorrect accuracy for physical abilities that do not use
a weapon. Their cast snapshots now use level-derived skill. Melee-range and
weapon-required abilities retain learned weapon skill, including disarmed
unarmed attacks.

Automated validation passed: `mix test.all` ran **6576 tests**, compilation with
warnings treated as errors succeeded, and strict Credo found zero issues.
The architecture dependency ratchet and commit hooks passed without allowlist
changes. Default tests cover weighted dispatch, transient markers, pending roots
and stuns, death, interruption, stale arrivals, creature behavior, and attack
skill selection. Separate DBC tests exercise the real net spell chain; map tests
verify player and creature paths, movement admission, source-owner handoff, and
observer packet/spline agreement. Database and map tags remain exclusive.

Native acceptance used two build-5875 GPU clients. Debugbidder (GUID 11, mage)
learned Engineering through existing development commands, equipped and bound
the actual trinket, and used it on a Stonetusk Boar. The observer saw its net
animation. Sampling recorded root 13099 with an exact 10,000 ms lifetime, followed
by an empty holder list and cleared root state. The item remained owned, and its
cooldown entry retained item ID 10720 and a 600,000 ms interval. A second native
use displayed "Item is not ready yet."

Debugbuyer (GUID 10, warrior) then learned parent spell 13120 with the existing
`.learn` command. Repeated native casts exercised the random outcomes without
resetting the trinket's cooldown or forcing RNG. A Land Walker provided a durable
target. Both the ordinary net and thirty-second self-root occurred naturally;
sampling captured a 30,000 ms self-root and its removal at expiry.

The charging outcome also occurred naturally. Sampling recorded charge state
and an advancing world projection, then arrival from x=16318.20 to x=16336.59 at
y=16278.10 on Programmer Isle. The client showed the forward movement and then
the caster caught in its own net. The target held 13119 and the caster held
13138, each with an exact 20,000 ms duration; neither retained 13139. Subsequent
normal nets coexisted with the target's charging-net root. After expiry, charge
state, arrival timer, and self-root were absent. This native run covered player
charge movement; creature-owner handling and mid-flight interruption have
automated coverage.

Debugbuyer logged out after expiry, disappeared from registry, position, and
metadata, and reconnected with no net holder, charge state, arrival timer, or
replayed backfire. Final disconnect removed both players from world presence;
their saved characters retained no net markers or charge state. Both owned
client services became inactive, WoW PIDs 1612349 and 1612387 were gone, and the
retained server exited. No error-level server entries or spell-validation
failures appeared. Existing unsupported account-data, ticket, and meeting-stone
requests were the only unsupported-message warnings.

WoW's own amdgpu graphics counters increased from 3,881,018,262 to
37,308,623,930 ns for PID 1612349 and from 3,972,257,392 to 37,981,536,250 ns for
PID 1612387. Duplicate descriptors were not summed.

Evidence is retained at:

- Mage/observer client: `/home/pikdum/.cache/thistle-wow-playtest.qQkvv4`.
- Parent-spell caster: `/home/pikdum/.cache/thistle-wow-playtest.gszsLT`.
- Server log: `/tmp/thistle-engineering-server.log`.
- Actual item: `/tmp/thistle-engineering-real-item-samples.txt` and
  `/tmp/thistle-engineering-real-item-state.txt`; screenshots `real-item-net.png`,
  `real-item-observer.png`, and `item-cooldown.png`.
- Self-root: `/tmp/thistle-engineering-random-6.txt` and
  `/tmp/thistle-engineering-random-5-late.txt`; screenshots `random-18.png`
  through `random-20.png`.
- Charge: `/tmp/thistle-engineering-random-7.txt` and
  `/tmp/thistle-engineering-charge-expired.txt`; screenshots `random-25.png`,
  `random-26.png`, and `random-7-observer.png`.
- Reconnect and cleanup: `/tmp/thistle-engineering-logged-out.txt`,
  `/tmp/thistle-engineering-reconnected.txt`, and `/tmp/thistle-engineering-cleanup.txt`.
- GPU evidence: `/tmp/thistle-engineering-gpu-before.txt` and
  `/tmp/thistle-engineering-gpu-after.txt`.
- Final gates: `/tmp/thistle-engineering-final-{all,compile,credo}.log`.

Nothing was pushed. This establishes the behavior above, not full vanilla parity.
