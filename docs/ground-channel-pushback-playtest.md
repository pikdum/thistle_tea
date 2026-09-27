# Ground channel pushback acceptance

Validated on 2026-09-27. Gameplay commits: `2aa17b99` and `3f28342e`.

## Behavior and reference

Damage pushback now shortens a channel's persistent ground effects and their
recipient auras as well as its cast timer. Previously, Blizzard could finish
channeling while its ground source retained the original eight-second lifetime.

The pure casting logic emits `DelayAreaEffects`. The effect boundary finds the
caster's objects by spell, and each owning process reschedules its expiry and
sends its absolute deadline to recipients. Aura transitions shorten only effects
belonging to that source GUID. Overlapping effects retain independent deadlines,
and repeated or stale updates cannot subtract twice, extend an effect, or alter
a replacement source. Periodic schedules remain anchored to source creation.
Natural expiry retains the final due tick; cancellation removes recipients.

Ground holders are excluded from ordinary target-aura delay. Native testing
exposed a case where a selected enemy received both delivery paths: its holder
temporarily lost an extra second before a refresh corrected it. The follow-up
commit gives the ground source sole ownership of that deadline. Regressions
exercise both message orders. Damage cancellation also uses its supplied time
instead of reading another clock value inside the pure transition.

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Spell::DelayedChannel` in `src/game/Spells/Spell.cpp` and
`DynamicObject::Delay` in `src/game/Objects/DynamicObject.cpp`.
No dependency-ratchet allowances were added.

## Native acceptance

The final committed build ran in the genuine build-5875 client, session
`/home/pikdum/.cache/thistle-wow-playtest.tvT7JR`. Debughunter, GUID `7`,
level 50, learned rank-1 Blizzard (`10`) through `.learn`. God mode was off,
and the Prairie Wolf Alpha was passive. All gameplay actions came from the
client; Tidewave only read state at approximately 50 ms intervals.

The accepted position was `{16673.2, 16198.1}` on map 451, teleported above
terrain at height 75. The target was Blackrock Warlock
`17379391079934011414`, at `{16653.2, 16198.1, 70.7377}`. Ground targeting at
client coordinates `{665, 390}` produced an object at
`{16655.7852, 16197.8438, 71.3047}` with radius 8. Its recipient set explicitly
contained the warlock, which remained selected throughout the casts.

`/tmp/thistle-ground-pushback-accepted-repeat.log` records:

| Sample time | Authoritative result |
| --- | --- |
| 158 ms | Eight-second Blizzard active; ground object `17365880163140632766` and its recipient holder share the same expiry. |
| 2,428 ms | Fireball deals 69 damage. Cast, object, and recipient lose 1,000 ms. |
| 5,503 ms | Fireball deals 65 damage. All three lose another 800 ms, leaving a total channel duration of 6,200 ms. |
| 6,349 ms | Cast, channel fields, object, and holder have cleared. Target health is 2,468 and remains unchanged until the next cast. |
| 9,564 ms | A new Blizzard creates source `17365880163140632769`. |
| 11,835 ms | Native movement cancels that cast after two ticks. Source and holder clear; target health stays at 2,424 until its combat reset. |

Source creation occurred seven milliseconds after cast start. Object and
recipient deadlines matched exactly; their reductions matched the cast's.
An audit of both accepted samplers found matching holder, recipient-source,
and dynamic-object deadlines in all 21 recorded active snapshots. No temporary
double reduction remained. The client displayed Blizzard, damage and resists,
shortened channel updates, and `Interrupted` on movement cancellation.

The preceding accepted cast, in
`/tmp/thistle-ground-pushback-accepted.log`, also exercised exhaustion: after
one 1,000 ms reduction, a later Fireball consumed the remaining channel time
and removed its source and holder immediately.

## Lifecycle and evidence limits

The hunter eventually died during retreat after prolonged incoming Fireballs.
Spirit release, walking back to the corpse, and the native resurrection button
restored it without a cast, channel, or ground source. The warlock reset to
2,631 health with no combat, victim, cast, or Blizzard holder. Logout removed
the player's owner, world position, and metadata. Reconnect restored a living,
peaceful hunter with channel fields zero and no ground objects or stale aura.
Both measured source GUIDs remained absent from registry and world position.

Earlier placement attempts in this session are excluded from combat acceptance:
`final-native.log` placed the area short of the warlock, and `verified.log`
recorded three rejected out-of-range clicks. Those three validation warnings
are expected. Other warnings were the existing account-data and GM-ticket
opcodes. No server errors or live recompilation occurred during the run.

The preliminary session, `thistle-wow-playtest.lhGilX`, established the missing
lifetime propagation and then exposed the double-shortening defect. Its
`/tmp/thistle-ground-pushback-repeat.log` is reproduction evidence for the
follow-up fix, not final acceptance. A diagnostic Lua command exceeding the
chat limit was corrected before those measurements.

Final WoW PID `2470572` used `amdgpu`; its own graphics counter increased from
1,428,067,484 to 26,974,529,233 ns. Both helper-owned services are inactive, and
both retained servers and clients have stopped. Logs and screenshots remain.

## Verification

`mix test.all`: **7,222 passed** in 67.8 seconds.
`mix compile --warnings-as-errors` and `mix credo --strict`: passed.
Focused aura and pushback tests: 33 passed. Coverage includes source isolation,
multiple objects per spell, stale timers, independent overlapping effects,
refreshes, final ticks, cancellation, recipient duration projection, both delay
delivery orders, periodic/self damage exclusions, and pushback resistance.

Retained evidence:

- `/tmp/thistle-ground-pushback-final-{all,compile,credo}.log`
- `/tmp/thistle-ground-pushback-accepted{,-repeat}.log`
- `/tmp/thistle-ground-pushback-audit.log`
- `/tmp/thistle-ground-pushback-{death-cleanup,target-cleanup,recovered,logout,reconnected}.log`
- `/tmp/thistle-ground-pushback-final-server.log`
- `/tmp/thistle-ground-pushback-final-gpu-{before,after}.log`
- Final session screenshots: `accepted-channel.png`, `accepted-repeat.png`,
  `accepted-cancelled.png`, `reclaim-corpse.png`, `recovered.png`, and
  `reconnected.png`.
