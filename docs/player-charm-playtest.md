# Charmed-player AI

Ordinary charm can now drive a player through the shared behavior tree. The
victim follows its controller, chooses hostile targets, approaches or faces
them, attacks, and uses eligible learned class spells. Player controllers can
issue attack, follow, stay, and reaction commands through the pet bar. Manual
possession remains a separate control mode.

The target owns incoming control and its original faction/control flags. Aura
transitions stop obsolete casting, combat, and movement and grant or release
control through typed effects. Controller observations are immutable behavior
tree inputs. Spell requests carry the controller, spell, and application
identity and are validated again by the player owner before normal casting.
Expiry, death, controller loss, world separation, and NPC combat end converge
on the existing aura cleanup path. Fear cannot restore input while charm remains.

The reference is `refs/vmangos/src/game/AI/PlayerAI.cpp`, together with the charm
handlers in `Spells/SpellAuras.cpp` and cast validation in `Spells/Spell.cpp`.
Spell selection excludes passive, hidden, generic-family, AI-disabled, positive,
and damage-breaking crowd-control spells and keeps the highest learned rank.
NPC controllers use their threat candidates; player controllers assist or
honor an explicit command. Only Chains of Kel'Thuzad (28410) activates aura 177;
the other two DBC spells using that aura remain inert as in the reference.

## Bugs found during acceptance

The first native NPC-charm run exposed a clock assumption: zero-initialized
AI deadlines never became ready because Erlang monotonic time was negative.
Unscheduled deadlines now start as `nil`. A regression starts the first cast
and navigation request with a negative clock.

A later combat run exposed missing ground targets. Blizzard could consume
mana and channel without spawning an area because the AI supplied only a
unit GUID. The owner now aims hostile destination spells at the victim's
current position through pure `SpellTarget.aim_at_unit/3`. Caster-centered
areas and direct spells retain their original targeting. The reference's
persistent-area handling likewise derives the destination from the unit.

The added Salia fixture was moved from a steep hillside to flat terrain at
`{16203.2, 16318.1}` on Programmer Isle. The surrounding ten-yard square has
ground heights between 69.437 and 69.445.

A fresh character also exposed Namigator's unsigned unknown-area sentinel.
`{4294967295, 4294967295}` was passing the positive-area guard and reaching
player metadata. `Pathfinding.get_zone_and_area/2` now rejects invalid zone
and area IDs in both direct and surface queries. The map regression checks
the unlabeled patch and preserves `{22, 22}` at the labeled playground spawn;
it does not invent an area for missing geometry. Duel setup used that labeled
spawn after the unknown-area location correctly blocked admission.

## Native acceptance

Two isolated build-5875 GPU clients used Debugbuyer (warrior 10) and Debugbidder
(mage 11), both level 60. Commands and casts originated in the clients;
Tidewave only sampled state. The helper sessions are
`/home/pikdum/.cache/thistle-wow-playtest.Qvfy25` and
`/home/pikdum/.cache/thistle-wow-playtest.Lhx8MQ` respectively. The actual WoW
processes used amdgpu, with increasing graphics-engine counters.

Salia's Cause Insanity (12888) was exercised in her original Shadow Hold room.
Both players were kept on her threat table so charm did not immediately end
through the controller's combat cleanup. With god mode enabled for this NPC
check, the sampler recorded:

- Mage faction changed from 1 to 1434, flags from 36872 to 36864, and accepted
  movement input became false. Salia retained warrior 10 as a combat target.
- The mage targeted warrior 10, completed Arcane Missiles (10211), and used
  Counterspell (2139). A native frame shows the missiles and channel bar with
  disabled action buttons.
- Expiry restored faction 1, flags 36872, normal input, target 0, and empty
  charm memory with no active cast. A separate one-target attempt also
  exercised immediate release when Salia left combat.

The player-controlled cases used a client-requested duel and learned Gnomish
Mind Control Cap (13181). God mode was disabled on the mage for combat:

- The controller received the minion portrait and command bar. Follow moved
  the mage from x=16318.2 to x=16313.6 as its owner backed away.
- Clicking Stay held the mage at x=16318.2 while the owner moved to x=16309.8.
- Clicking Attack set the explicit Land Walker GUID and command `:attack`.
  Passive followed by Stay cleared the target and held the mage at
  `{16325.6, 16300.5}`. A one-second forward keypress from the controlled
  mage did not move it; the expiry snapshot retained that position.
- A combat sample recorded Arcane Missiles costing 500 mana and Land Walker
  health falling from 100% through 97%, 94%, and 92%, then to 82% after another
  attack. Subsequent Blizzard consumed mana but produced no area in this
  pre-correction sample; that result motivated the targeting fix above.
- Expiry cleared incoming control, command target, casting, and AI memory and
  restored movement input. Both clients observed the controlled spell effects.

The NPC sample is `/tmp/thistle-charm-fixed-sample-11.log`. Player samples are
`/tmp/thistle-player-charm-{1,3,4,5}.log`; sample 2 exceeded the diagnostic
printer's limit and is not used for complete lifecycle evidence. Screenshots
include mage `fixed-felwood-28.png` and `player-charm-damage.png`, and warrior
`player-charm-follow.png`, `player-charm-stay-button.png`,
`player-charm-explicit-attack.png`, and `player-charm-passive.png`.

The initial server log is `/tmp/thistle-charm-fixed-server.log`. It contains
existing unsupported account-data, GM-ticket, and meeting-stone requests;
no new charm owner, movement, or projection failure appeared.

## Ground-spell correction acceptance

A fresh server with `1b9ea201` and fixture correction `0b934436` reused the
isolated clients. A newly created human mage, Charmmage (12), was leveled to
60 and learned Blizzard (10185). Its only eligible charm spells were Fireball
(133) and Blizzard; god mode remained off. The warrior requested a duel at
the labeled playground spawn, charmed the mage, selected Land Walker, and
clicked the pet Attack button.

The sampler recorded the following sequence:

| Time from sample start | Authoritative result |
| --- | --- |
| 7,749 ms | Charm 13181 active; victim input disabled; mana 2808 |
| 13,920 ms | Blizzard channel active; destination `{16343.2, 16278.1, 69.4444}`; one live area object; mana 1873 |
| 14,859–16,847 ms | Land Walker health fell through 98%, 97%, and 95% |
| 17,575 ms | Charm and channel gone; zero live area objects; victim input restored |

The native client shows falling ice, ground impacts, the channel bar, and
disabled victim actions in `Lhx8MQ/screenshots/ground-blizzard-28.png`.
Land Walker also attacked and stunned the mage during this sequence. Final
owner snapshots show faction 1, no control, no charm memory, no controller
monitor, no cast, no outgoing companion, and no area processes on either
player. A subsequent native movement key moved the mage from
`{16326.3431, 16294.9573}` to `{16325.5391, 16295.7607}`.

Evidence is `/tmp/thistle-charm-ground-sample-2.log`,
`/tmp/thistle-charm-ground-cleanup-{before,after}.log`, and
`/tmp/thistle-charm-ground-server.log`. The fixture is visible in warrior
`flat-charm-fixture.png`; `/tmp/thistle-charm-flat-terrain.log` records ground
queries. The final server log contains the existing startup requests and
expected duel admission rejections during setup (combat and unknown area),
with no owner, movement, area-tick, or projection error.

WoW PID 331741's graphics counter increased from 89,134,711,750 to
108,195,337,219 ns, and PID 332602's from 94,157,104,724 to 115,223,902,925 ns;
both reported amdgpu device `0000:0c:00.0`.

## Final validation and cleanup

`mix test.all` passed all 5,777 tests, including DBC, VMangos, and map
integration. Compilation with warnings as errors, strict Credo, formatting,
and diff checks passed. Logs are `/tmp/thistle-charm-complete-tests.log` and
`/tmp/thistle-charm-complete-credo.log`. The isolated-client systemd units are
inactive, both WoW processes have exited, and the retained server PTY exited.
Screenshots and logs remain available locally. No commits were pushed.

The main implementation is `fc9659cb`; stale-action and clock fixes are
`69f40f7d` and `017be790`. Ground-spell targeting is `1b9ea201`, and fixture
placement is `0b934436`. Automated coverage also checks spell eligibility,
negative clocks, controller lifecycle, charm/possession distinction, the
Chains-only aura behavior, command validation, fear/root/stun overlap,
hostility, movement routing, and obsolete cast and movement messages.
