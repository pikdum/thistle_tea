# Combat entry and cast timing acceptance

Gameplay commits: `119d05d6` and `e8dc9c46`, validated on 2026-09-27.

## Behavior and reference

Entering combat now immediately interrupts a preparing, noninstant spell with
the `not_in_combat` attribute. Players, ordinary creatures, and pets share
`CombatState.enter/2`. Contact timers, threat-reference acquisition, creature
engagement, and pet reconciliation use that transition. Refreshing existing
combat does not repeat interruption. Dead players cannot acquire new combat
references. Boundaries supply the current time explicitly.

Creature channels with the hostile-action channel interruption flag also stop
on combat entry. Player channels retain their separate interruption rules.
Combat-capable casts, instant preparation, and already launched spells remain
unchanged. Cancellation uses the existing cast owner, cooldown reset, channel
teardown, and typed failure events. No dependency-ratchet allowances were added.

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Unit::SetInCombatState`, `SpellEntry::IsNonCombatSpell`, and channel flags in
`SpellDefines.h`. Vanilla has no general aura flag for removal merely on combat
entry; this change does not invent one.

Verification uncovered three related defects:

- Cast-failure broadcasts used an unsupported `exclude_self?` option. Both
  callers now use `include_self?: false`; the owner gets its failure packets,
  and nearby same-world observers receive the observer cancellation once.
- `Cast.new/4` normalized indefinite channel duration `-1` to zero, treating
  those channels as instant spells. It now preserves `-1`, uses no expiry
  deadline, schedules channel ticks, and follows normal cancellation cleanup.
- Ordinary cast pushback changed `ends_at` without changing the launch
  deadline used by the state machine. Accumulated delay now shifts launch,
  completion, and the first channel tick consistently while retaining the
  original cast duration for the pushback cap. This follows `Spell::Delayed`
  in VMangos and also works with negative monotonic timestamps.

## Native mount interruption

The genuine build-5875 client ran committed code without source edits or live
recompilation. Session: `/home/pikdum/.cache/thistle-wow-playtest.bunuEn`.
Debughunter, GUID `7`, level 50, used its level-49 Prairie Wolf Alpha. Actions
came from the client; Tidewave only observed state. Brown Horse (`458`),
Blackfathom Channeling (`8734`), and Conjure Food (`587`) were learned through
existing developer commands. God mode was not used.

At `{16675.2, 16268.1, 69.44}` on map 451, the hunter began Brown Horse and
sent pet `17383894611314868340` at Defias Cutpurse
`17379390963600795669`. `/tmp/thistle-combat-entry-mount.log` records:

| Sample time | Observed transition |
| --- | --- |
| 5 ms | Hunter and pet peaceful, no references, hunter health 1,962 and mana 2,655. |
| 2,438 ms | Horse preparation begins with a three-second deadline. Pet has attack intent; hunter remains peaceful. |
| 4,431 ms | Actual pet contact enters owner combat and acquires a threat reference. The mount cast clears immediately, about 1,993 ms after observed preparation. No mount aura or display appears. |
| 9,512 ms | Pet has defeated the cutpurse and assisting thug; owner and pet references are empty. |
| 14,918 ms | Owner combat clears, and state plus metadata return to flags `36872`. |

Hunter health and mana stayed unchanged throughout. The client displayed
`Interrupted`, and a Lua event observer printed `combat=1 health=1962`.
Screenshot: `mount-interrupted.png`. This isolates combat entry from damage
pushback against the hunter.

After combat cleared, the same mount cast succeeded. In
`/tmp/thistle-combat-entry-mount-retry.log`, preparation appears at 2,251 ms
and mount display `2404` plus aura `458` at 5,227 ms.
Screenshot `mount-retry.png` shows the horse. The mount was subsequently
cancelled with vanilla's `CancelPlayerBuff` API.

## Indefinite channel lifecycle

In `/tmp/thistle-combat-entry-indefinite-verified.log`, Blackfathom Channeling
enters `:channel_tick` at 2,465 ms with duration `-1`, nil expiry, channel spell
`8734`, and the matching active aura. It remains active until a client movement
input at 15,020 ms, over twelve seconds later. Movement clears the cast,
channel spell, and aura. The owner and pet remain peaceful throughout.

Screenshots `indefinite-verified.png` and `indefinite-cancelled.png` accompany
the sampler; the latter shows the client's interruption diagnostic. Automated
DBC coverage additionally advances the same real spell for a minute on a
creature, then proves combat entry cancels the channel and its projection.

An earlier attempt overlapped camera input with subsequent commands and never
left the mounted state. Its `indefinite.log` and `indefinite-channel.png` are
not acceptance evidence. A `Dismount()` diagnostic used an unavailable vanilla
Lua function; the dialog was dismissed before the verified repeat.

## Damage pushback and combat-capable casts

For the verified repeat, the hunter teleported above terrain to
`{16683.2, 16198.1, 74}` and landed at height `69.4647`. The pet was Passive
with no victim. Arcane Shot engaged Blackrock Warlock
`17379391079934011414`, incarnation `65`, at about 30 yards.

`/tmp/thistle-combat-entry-pushback-verified.log` records Conjure Food while
the hunter remained in combat:

| Sample time | Observed transition |
| --- | --- |
| 9,970 ms | Conjure Food prepares with its original three-second deadline. |
| 11,547 ms | A Fireball removes 72 health. Accumulated pushback becomes 1,000 ms, and both launch and completion deadlines move by that amount. |
| 13,964 ms | The spell completes after about four seconds and spends its 60 mana. |
| 16,317 ms | Another Conjure Food begins. |
| 19,326 ms | This cast completes after about three seconds, with no intervening hit. |

Screenshot `pushback-verified.png` shows incoming damage and two successful
Conjured Muffin creations. The sampler recorded the cast every 50 ms; the
delayed cast remained in preparation past its original launch time.
An earlier teleport used a height below local terrain and was discarded; its
`pushback.log` and `pushback-prepared.png` are not acceptance evidence.

## Cleanup and verification

Feign Death and a return to the peaceful spawn preceded normal logout. The
player and the prior pet `17383894611314868439` disappeared from registry,
spatial state, and metadata. The warlock reset to 2,631 health, no victim,
and empty threat. Reconnect restored a peaceful hunter with health 1,962,
flags `36872`, no cast, channel, mount, threat references, or timer opponent.
The new pet `17383894611314868485` also had no combat or references.
Evidence: `/tmp/thistle-combat-entry-{logout,reconnect}.log`, `logged-out.png`,
and `reconnected.png`.

`mix test.all`: **7,215 passed**. Compilation with `--warnings-as-errors`
and strict Credo passed. Final logs are
`/tmp/thistle-combat-entry-postplaytest-{all,compile,credo}.log`.
The committed gameplay build also passed all gates before native testing.
Regression coverage includes every combat-entry path, idempotency, dead units,
instant and launched casts, player versus creature channels, real DBC spell
rules, owner/observer packet delivery, indefinite timing, and authoritative
pushback deadlines. Commit hooks passed.

`/tmp/thistle-combat-entry-server.log` contains no gameplay errors, failed
validation, or live recompilation. Warnings are the existing account-data and
GM-ticket opcodes. WoW PID `2450825` used `amdgpu`; its own graphics counter
increased from `974028772` to `21730278487` ns. The helper owned
`thistle-wow-playtest.bunuEn.service`, invocation
`bd2674ebdb444ead81d8fd4f390e2cd5`.

The helper stopped its service and verified inactive/dead. The retained server
exited successfully; WoW PID `2450825` and BEAM PID `2451127` were gone. Logs
and screenshots were retained. No push was performed.
