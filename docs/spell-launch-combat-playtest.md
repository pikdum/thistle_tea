# Spell launch combat acceptance

Gameplay commit: `8e25287b`, validated on 2026-09-27.

## Behavior and reference

Player-controlled hostile projectiles enter the caster into combat at launch,
before damage or victim threat. The hold covers flight plus 500 ms. Targets
using a PvP combat timer impose a five-second minimum. The explicit recipient's
effect mask determines hostility; helpful effects, self projectiles, ordinary
NPC projectiles, and the no-threat, no-initial-threat, and threat-only-on-miss
attributes do not create this projectile hold. A missed projectile still does.

The `ACTIVE_THREAT` spell attribute independently requests five seconds of
combat. A peaceful self cast does not start combat. Overlapping requests retain
the later expiry. Combat holds do not select a victim or create threat, and a
pet's launch does not engage its owner before actual contact. PvP flagging can
still reach the controlling player through the existing owner boundary.

Prepared casts, triggered casts, and repeated ranged shots share the rule.
Pure launch decisions produce typed effects; entity owners apply the timer and
publish combat flags. Missile delivery and launch holds share the same caster
position and flight calculation, including the five-yard minimum distance.
Foreign-caster delivery now uses that caster's position. No dependency-ratchet
allowances were added.

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Spell::cast` delayed launch, `Spell::OnSpellLaunch`, target flight calculation,
`Unit::SetInCombatWithVictim`, `Unit::SetInCombatState`, and
`Unit::UsesPvPCombatTimer`. This change adds launch windows to the existing
contact model; it does not replace the existing five-second contact timeout
with VMangos's target-aware PvE timer shortening.

## Native projectile timing

The build-5875 client ran the committed code without source edits or live
recompilation. Session: `/home/pikdum/.cache/thistle-wow-playtest.PSpofv`.
Debugmage, GUID `5`, level 50, used Fireball rank 1 against Defias Cutpurse
`17379390963600795669` on map 451. The mage stood approximately 30 yards away
at `{16687.2, 16268.1, 69.44}`. God mode prevented incoming damage. Actions
came from the client; Tidewave only observed state.

The complete repeat is in `/tmp/thistle-launch-combat-fireball-verified.log`:

| Sample time | Observed transition |
| --- | --- |
| 2 ms | Both units peaceful, target health 120, empty threat and player references. |
| 2,960 ms | Fireball preparing; caster still peaceful. |
| 4,469 ms | Launch completes. Caster state and metadata flags become `561160`, with a 1,749 ms hold. No attack intent or player references. Victim remains peaceful at 120 health with no victim or threat. |
| 5,721 ms | Impact reduces health to 97 and creates victim threat. This is 1,252 ms after the observed launch. |
| 5,772 ms | Player receives the victim's threat reference and ordinary contact extends its window to 5,000 ms. |
| 7,258 ms | Nearby Defias Thug joins through assistance and contributes a separate reference. |
| 8,711 ms | Fire Blast kills the cutpurse and clears its threat. Its player reference disappears in the next sample. |

A client Lua observer waited for player combat while the target was peaceful,
printed `Launch: player combat, target peaceful`, and requested logout. The
client displayed `You can't logout now.` Screenshot `launch-logout.png`
records that first successful run; `fireball-verified.png` records the repeat.
The first sampler's default output was truncated, so the complete repeat above
is the timing evidence.

## Active threat and cleanup

To exercise the instant attribute directly, the mage learned Charge Stun
`7922` and Battle Stance `2457` through existing developer commands. The first
attempt without Battle Stance was correctly rejected by the client. A learned
Boar Charge was not used as acceptance evidence.

Charge Stun executed from 22 yards and entered the caster into combat while
the cutpurse remained peaceful with 120 health, no victim, and no threat.
The client automatically enabled melee for this spell. That intent refreshed
the ordinary combat timer until `AttackTarget()` stopped it; this native run
therefore verifies attribute execution and lifecycle integration, while the
automated tests isolate the launch-only five-second rule.

In `/tmp/thistle-launch-combat-active-threat-cleanup.log`, caster combat begins
at 2,881 ms, attack intent stops at 4,336 ms, and state plus metadata return to
flags `36872` at 9,388 ms. The target remains peaceful throughout. Screenshots
`active-threat-verified.png` and `active-threat-cleanup.png` show the stun,
rejected logout, and final peaceful state.

After the Fireball repeat, the assisting thug was selected directly and killed
with Fire Blast. `/tmp/thistle-launch-combat-cleanup-after.log` records no
player combat, empty references, and the dead thug. `cleanup-confirmed.png`
shows both kills and the client's peaceful state. An attempted
`CancelShapeshiftForm()` diagnostic used an unavailable vanilla Lua function;
its dialog was dismissed and was unrelated to server gameplay. The earlier
`both-enemies-defeated.png` was captured before the thug's successful kill and
is not cleanup evidence.

Normal logout removed player `5` from the entity registry, spatial state, and
metadata. Both enemies subsequently had full health, no victim, and empty
threat, with new incarnations `253` and `238`.
`/tmp/thistle-launch-combat-logout.log` and `logged-out.png` record this state.
Reconnect restored the mage with 1,875 health, flags `36872`, no combat,
attack, cast, references, or last contact; metadata agreed. Evidence:
`/tmp/thistle-launch-combat-reconnect.log` and `reconnected.png`.

## Verification and shutdown

`mix test.all`: **7,196 passed**, 67.4 seconds. Compilation with
`--warnings-as-errors` and `mix credo --strict` passed. Logs:
`/tmp/thistle-launch-combat-final-{all,compile,credo}.log`.

Regressions cover interrupted preparation, explicit effect masks, missed
projectiles, threat exemptions, active-threat DBC flags, longer overlapping
holds, dead casters, pet owner isolation, PvP flag delivery, ranged repetition,
triggered casts, foreign caster position, point-blank flight, self casts, and
world separation.

`/tmp/thistle-launch-combat-server.log` contains no gameplay handler errors or
live recompilation. Warnings are the existing account-data and GM-ticket
opcodes. WoW PID `2426777` used `amdgpu`; its own graphics counter increased
from `2584728227` to `33247721154` ns. The owned service was
`thistle-wow-playtest.PSpofv.service`, invocation
`1e81114f43704fdb88e2a182118d2d0a`.

The helper stopped that service, verified inactive/dead. The retained server
exited successfully; both recorded process IDs were gone. Logs and screenshots
were retained. No push was performed.
