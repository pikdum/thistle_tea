# Damage sharing

Damage sharing now runs after school absorption and mana shields. Flat shares
run before percentage shares, with each share using the remaining damage.
Resolved aura amounts are used once, including stack counts, and shares cannot
exceed the damage available. Expired, self-cast, unavailable, and other-school
links do not reduce damage.

The receiving spell or attack boundary observes living sharing casters in the
same world. Periodic damage refreshes that observation for every due tick.
Pure logic allocates the damage and enqueues typed `SharedDamage` effects;
the recipient owner applies them through the existing health, death, and
combat-feedback paths. Delivery rechecks the recipient's life and world.
These observations follow the normal asynchronous entity-delivery model;
they are not a transaction spanning both owners.

Transfers retain the original attacker, damage school, and sharing aura.
They do not become new casts, roll another hit or critical strike, reapply
damage modifiers, trigger offensive spell procs, or recursively share damage.
Flat transfers can be resisted or absorbed by their recipient. Percentage
transfers bypass that second mitigation step. Following the reference's loop
guard, a flat recipient with its own flat-sharing aura also skips that step.
Taxi flight and creature evasion prevent transfer damage. Lethal transfers use
normal death cleanup without a death durability penalty.

The reference is `Unit::CalculateDamageAbsorbAndResist` and `Unit::DealDamage`
in `refs/vmangos/src/game/Objects/Unit.cpp`, plus
`SpellCaster::DealDamageMods` in `Objects/SpellCaster.cpp`. The build-5875 DBC
supplies 45 and 55 damage for Blessing of Sacrifice ranks 1 and 2, and 30 percent
for Soul Link. The old flat calculation added another point to the already
resolved amount; all transfers also used a fabricated spell 6940.

## Automated validation

Tests cover shield ordering, multiple flat and percentage recipients, rounding,
stacking, caps, expired and unavailable links, world changes, fresh spell and
periodic observations, exhausted shield removal, recipient resistance and
immunity, recursion prevention, taxi protection, lethal cleanup, attacker
credit, owner delivery, and the actual combat-log spell and school. A separate
DBC-tagged test checks the three real spell amounts.

On commit `492d8bbd`, `mix test.all` passed 5,924 tests. Compilation with warnings
as errors, strict Credo, formatting, and the diff whitespace check passed.
The architecture dependency allowlist was unchanged.

## Native acceptance

Two isolated build-5875 clients ran against server commit `492d8bbd`. Both actual
WoW processes used AMD GPU rendering in their helper-owned systemd cgroups.
No source edits or compilation occurred while the server was running. All
mutations came from client input; Tidewave only observed owner state.

Debugpaladin (GUID 2), Debugbuyer (10), and later Debugwarlock (6) used level 60
with damage protection disabled. Marisa du'Paige, entry 599 and GUID
`17379390972073288548`, provided ordinary attacks at the map-451 debug fixture
near `{16463.2, 16398.1, 69.44}`. Debugbuyer was the second client and observer.

- Sacrifice rank 2 appeared on the warrior with resolved amount 55 and the
  paladin as caster. The warrior stayed at 2,213 health while successive
  10–12 damage hits reduced the paladin from 3,285 to 3,196. Both combat logs
  showed the reduction and the corresponding Blessing of Sacrifice damage.
- Power Word: Shield on the warrior took precedence over Sacrifice. Its
  capacity fell from 943 to 863 while warrior health stayed at 1,916 and
  paladin health stayed at 3,172. Both clients displayed the shield and link.
- A fresh Sacrifice was active when the paladin used `.die`. At the first
  dead-caster observation, the warrior still retained the aura but its set of
  eligible sharing casters was empty. Subsequent hits reduced warrior health
  from 1,871 to 1,838. The paladin remained dead at zero health. This native
  death was environmental; the transfer-specific durability exclusion was
  checked by the automated lethal-transfer test.
- The warlock summoned an imp, selected passive behavior, and cast Soul Link.
  After moving the fixture, the link was recast on the replacement imp
  `17383894568633630969`. Both the pet and owner displayed Soul Link.
- One sampled hit reduced warlock health from 2,283 to 2,264 and imp health
  from 769 to 762: 19 plus 7 damage from a 26-damage hit. Later client feedback
  showed 22 damage to the owner and 9 to the imp from a 31-damage hit, with
  the transfer correctly named Soul Link. The passive imp regenerated between
  some hits, so individual transitions were compared rather than net loss.
- Power Word: Shield on the imp retained all 943 absorption while Soul Link
  reduced the imp's health. Its later expiry left Soul Link active. The
  observer saw the pet and the owner's link aura throughout.
- Native `PetDismiss()` removed the pet and owner link by the next sampled
  transition. Subsequent ordinary hits dealt their full 27–31 damage to the
  warlock. The observer saw the pet disappear and the owner's aura vanish.
  The dismissed pet subsequently had no process, position, or metadata.
- After both players moved away, Marisa returned home at full health with
  target zero, empty threat, and combat false. Both player owners were alive
  and out of combat, with no sharing or shield auras left.

Initial client attempts without an explicit friendly target did not cast
Sacrifice and are not acceptance evidence. The successful input selected a
party member explicitly with `CastSpell(63, "spell")` followed by
`SpellTargetUnit("party1")`. The first warlock shield also targeted the owner;
the pet-shield check explicitly selected the pet before casting.

No entity-owner, damage-transfer, or spell-processing errors appeared. Existing
unsupported account-data, GM-ticket, and meeting-stone requests were the only
warnings. Multi-recipient sharing, recipient world changes, flat-recipient
immunity, periodic sharing, and lethal transfers were covered by automated
tests rather than separate native scenarios.

Artifacts remain under `thistle-wow-playtest.Ftt2PN` and
`thistle-wow-playtest.cA2V4B` in the local cache. The accepted samples are
`/tmp/thistle-sharing-sacrifice-final.log`, `-shield.log`, `-dead-caster.log`,
`-soul-final.log`, `-dismiss.log`, and `-lifecycle.log`, with the same
`/tmp/thistle-sharing` prefix. Screenshots include `sacrifice-final`,
`shield-first`, `dead-caster`, `pet-shield`, `soul-final`, and `dismissed`.
The server log is `/tmp/thistle-sharing-server.log`.

Both helper sessions and the server were stopped, with no WoW or BEAM process
remaining. Nothing was pushed.
