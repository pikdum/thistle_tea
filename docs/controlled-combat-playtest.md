# Controlled creature owner combat acceptance

Gameplay commit: `b1960d91`, validated on 2026-09-27.

## Behavior and reference

Actual hostile contact by a player-owned creature now enters its owner into
combat. Incoming contact refreshes the owner's timer; outgoing contact also
adds the owner to the opponent's threat table at zero threat. An Attack command
alone does not propagate contact. Successful Feign Death blocks incoming
propagation and inherited threat, while outgoing pet attacks can refresh the
owner's combat timer without adding owner threat.

The primary summoned companion's incoming threat references can retain an
already active owner combat state. They remain separate from the owner's own
references, so dismissal cannot remove an overlapping direct reference.
Ownership, world, life state, and enemy incarnation are checked against immutable
observations. Creature templates with `NO_OWNER_THREAT` are exempt. Contact
supports canonical companion, independent guardian, and totem ownership; native
acceptance below uses a hunter pet.

`ControlledCombat` contains the pure transitions. Typed effects deliver contact
to the player boundary, which validates current ownership and wakes its timer.
Mob owners publish their incoming reference projection. Player combat now
reconciles through shared maintenance before regeneration, consuming the same
immutable context as pet combat. The dependency ratchet removes the two old
PlayerCombat world/metadata exceptions and adds none.

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Unit::SetInCombatWithAggressor`, `Unit::SetInCombatWithVictim`, the player/pet
combat timer, and `CREATURE_STATIC_FLAG_2_NO_OWNER_THREAT` (`0x20`).
`Unit::SetFeignDeath` deliberately applies its six-second delay only when a pet
is in combat **and has a victim**. A passive pet with no victim permits immediate
successful Feign Death; that existing behavior is retained.

## Native contact and Feign Death

Both sessions ran the committed build without source edits or live recompilation.
The build-5875 client used Debughunter, level 50, and its level-49 Prairie Wolf
Alpha against Blackrock Warlock on map 451. All actions came from the real client;
Tidewave observations were read-only.

First session: `/home/pikdum/.cache/thistle-wow-playtest.ESJx4O`.
Pet `17383894611314868326` was sent at the caster, then recalled and made
Passive/Stay. The caster was `17379391079934011414`, incarnation 65.

- At sample 3,826 ms the pet had an attack target but the owner remained out of
  combat. At 6,739 ms the owner entered combat and appeared on caster threat at
  zero, before the first damaging pet hit. The pet later dealt 52 total damage.
- With pet victim zero, Fireballs continued to refresh owner contact. Owner
  state and metadata had combat flags `561160`; the client reported both units
  in combat and rejected logout with “You can't logout now.”
- Successful Feign Death removed the owner's reference and zero-threat entry.
  While the pet took repeated Fireballs, the owner remained out of combat with
  flags `36872`, empty references, and a successful feign aura. The client
  reported owner combat `nil`, pet combat `1`.
- After standing at sample 32,417 ms, the next Fireball at 34,679 ms restored
  owner combat. The owner's references stayed empty, and the caster still had
  only the pet on its threat table. This isolates incoming propagation from
  outgoing pet damage or the owner's direct threat membership.

Evidence: `/tmp/thistle-owner-combat-{baseline,ranged,feign}.log` and
`/tmp/thistle-owner-combat-server.log`. Screenshots: `combat-logout.png` and
`feigned.png` in the first session. The later `progress.log` probe encountered
a missing pet process and is not acceptance evidence.

## Fresh lifecycle repeat

Second session: `/home/pikdum/.cache/thistle-wow-playtest.uoMqGy`.

| Scenario | Observed result |
| --- | --- |
| Recall before contact | Pet `17383894611314868330` entered its attack behavior, then returned without contact. Owner combat and references stayed empty. Logout admitted a countdown, which was cancelled. |
| Actual contact | A subsequent pet attack added owner `7` to the caster at zero threat. Follow, Stay, and Passive retained combat. Logout was rejected; `combat-logout-confirmed.png` shows the client error. |
| Owner takes over | Auto Shot, Arcane Shot, and Serpent Sting moved caster victim to owner `7`. The passive pet stayed at 468 health while references remained. Initial Auto Shot facing errors ended after turning the client toward the caster. |
| Caster death | In `final-cleanup.log`, caster death at 9,460 ms cleared threat and pet references. Pet combat ended immediately. Owner references emptied but the contact window remained until 14,755 ms, about 5.3 seconds after the final contact. State and metadata both cleared the owner combat flag. |
| Regeneration | Pet health advanced from 468 to 1,180, 1,892, then 2,138 at 22,798 ms. `recovered.png` reports both units out of combat and full pet health. |
| Respawn | At 39,442 ms the caster had incarnation 153, full health, victim zero, and empty threat. Owner and pet stayed out of combat. |
| Teleport and logout | Teleport replaced the pet with `17383894611314868385`. The old pet's process, position, and metadata were absent. A normal logout then removed player `7` and both prior pet identities from all three surfaces. |
| Reconnect | New pet `17383894611314868405` had 2,138 health, flags `4152`, Passive/Follow, no victim, empty references, and nil last contact. Both owners' metadata showed no combat. |

Evidence:

- `/tmp/thistle-owner-combat-final-{ranged,kill,cleanup}.log`
- `/tmp/thistle-owner-combat-final-{teleport,logout,reconnect}.log`
- `/tmp/thistle-owner-combat-final-server.log`
- Second-session screenshots `combat-logout-confirmed.png`, `recovered.png`,
  `logged-out.png`, and `reconnected.png`.

No gameplay handler or AI errors and no recompilation appeared in either server
log. Warnings were the existing account-data/GM-ticket opcodes and expected
Auto Shot facing validation. The final WoW process, PID 2416811, belonged to
`thistle-wow-playtest.uoMqGy.service`, invocation
`8e0c322d31fe410cb9acbdc0d6a6407d`. Its own `amdgpu` graphics counter increased
from 1,591,811,459 to 12,973,583,232 ns.

Both helper-owned client sessions were stopped, and both retained server
sessions exited successfully. Logs and screenshots were retained.

## Automated verification

`mix test.all`: **7,181 passed**, 76.1 seconds. Compilation with
`--warnings-as-errors` and `mix credo --strict` passed. Logs:
`/tmp/thistle-owner-combat-accepted-{all,compile,credo}.log`.

Regressions cover contact versus commands, missed attacks, pet spell damage and
channeled ticks, totem contact, guardian ownership, dead or removed owners,
ownership replacement, independent overlapping references, stale incarnations,
Feign Death, untargetable owners, template exemptions, distant snapshots,
explicit effect delivery, and waking an idle player timer.
