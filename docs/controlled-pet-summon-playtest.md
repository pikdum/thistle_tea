# Controlled pet summon acceptance

Date: 2026-09-25. Implementation: `a3df16cf`.

Spell effect 28 now creates one controlled combat pet for either a player or
a creature. This covers the real Bloodscalp and Skullsplitter pet spells,
Summon Imp, Summon Treant Ally, Summon Doomguard, and timed elementals.
The reference is VMangos `8f4e60845`, `Spell::EffectSummon` in
`refs/vmangos/src/game/Spells/SpellEffects.cpp`, minion target placement in
`Spell.cpp`, and current-pet restoration and lifetime in `Objects/Pet.cpp`.

## Rules and ownership

- Any occupied combat-pet slot blocks effect 28, including a dead pet. The
  existing effect 56 retains its same-entry dead-pet replacement rule.
- The shared `SummonedPet` loader retains template names and spells, scales
  canonical stats from the owner level, applies passives, and fills resources.
  NPC pets are aggressive; player pets are defensive. Tameable templates
  summoned by effect 28 are summoned pets rather than hunter pets.
- Implicit minion placement uses the front-left radius and resolves terrain
  collision at the boundary. Explicit destinations remain explicit. Summons
  execute on the caster even when another unit is selected.
- Typed owner-local requests go through `EventSink.Context`. Player attachment
  records the canonical relationship before processing another request. NPC
  ownership uses the existing monitored slot and metadata publication.
- Positive durations use the existing unconditional summon timer. Timed pets
  are excluded from automatic restoration; permanent pets restore through
  their original summon effect. Termination clears actors, world projections,
  owner references, and the player's pet bar.

## Native setup

Fresh local server, genuine WoW 1.12.1 build 5875, level-50 Debugmage and
Debugpriest. The isolated GPU session is
`/home/pikdum/.cache/thistle-wow-playtest.kAT6TA`.
The renderer was the RX 7900 XT. WoW PID 984288 had advancing amdgpu graphics
counters, from 6,149,565,555 to 8,787,150,610 ns in the initial samples.
Runtime probes only read existing entities and projections. Spell learning,
travel, pet commands, casting, and logout used the native client.

## Permanent summons

1. Entered Northshire near Dane Winslow, spawn 79965. His ordinary spawn
   script cast 11939 without a development summon command. The client showed
   his Imp Minion beside him. The owner slot, unit summon field, and metadata
   all named pet `17383894778449494154`: entry 12922, level 8, aggressive,
   owner `17379391068944021597`, full 51 health and 105 mana, and spell 20801
   enabled for autocasting. Pet number and name timestamp were zero.
2. Learned 11939 and cast Summon Imp on Debugmage. The client displayed the
   fixed Imp Minion name, pet frame, command bar, Firebolt, and defensive
   stance. The server retained a level-50 summoned pet, not a hunter pet.
   Repeated casts retained GUID `17383894778449494557` without a second pet.
3. Moved to the nearby creatures and used native `PetAttack()`. The pet
   acquired Timber Wolf `17379390963180452081` and entered combat. The wolf's
   authoritative health changed from 55 to zero, with `alive?: false`; the
   Imp returned to idle with full health. The client also showed the earlier
   Kobold Vermin kill.
4. Logged out normally. The player actor disappeared, the saved relationship
   was `{:suspended, 12922, 11939}`, and automatic restoration remained enabled.
   The previous pet GUIDs had no actor, metadata, or world position.
5. Reconnected through character selection. Imp `17383894778449494620`
   appeared with the correct name, defensive stance, and pet bar. Native
   `PetDismiss()` then removed it for the timed-summon checks.

## Timed summons

Debugmage learned 513 and cast Earth Elemental. Pet `17383894567174013542`
appeared with the elemental model, name, portrait, and command bar. Its actor
retained entry 329, 747 health, a 60,000 ms lifetime, and automatic restoration
disabled. After expiry, both the client pet UI and the owner relationship were
empty. Actor, metadata, and world position lookups for the old GUID returned
nil. The native samples bracketed expiry rather than recording the exact
transition; the actor tests cover unconditional timer expiry during combat.

A subsequent attempt to repeat the cast was blocked by its native ten-minute
category cooldown before reaching the server. It is not evidence for
duplicate-slot handling; the successful permanent-Imp recasts above and the
owner tests cover that rule.

Debugpriest then learned 513 on a fresh seed character and summoned elemental
`17383894567174013620`. The live actor and client pet UI were present before
logout. Normal logout removed the player and pet, left no owned world entity,
and saved `{:suspended, 329, 513}` with `restore_automatically?: false`.
Reconnecting about 34 seconds after the live snapshot returned with summon
field zero and no pet frame or command bar, before the original duration
could have elapsed. The old pet's actor and projections stayed absent.

## Cleanup and evidence

Stopped the helper-owned client through its recorded systemd unit and stopped
the retained server. Before stopping the server, final reads confirmed that
both players and all six player pets observed during the run had no actor, metadata, or
world position. Dane's pet remained owned by the live NPC throughout the run.
There were no server errors or summon, control, movement, or lifecycle
warnings. The existing unimplemented account-data, GM-ticket, and meeting-stone
requests appeared during login.

Screenshots are retained under the session's `screenshots` directory:
`imp-pair.png`, `imp-accepted-combat.png`, `permanent-reconnect.png`,
`earth-current.png`, `earth-expired.png`, `timed-before-logout.png`, and
`timed-reconnect.png`. Read-only evidence is in
`/tmp/thistle-controlled-pet-{dane,duplicate,duplicate-again,combat-accepted,kill,permanent-offline,permanent-reconnect,timed-start,timed-expiry,timed-offline,timed-reconnect,final-cleanup}.log`.
The server log is `/tmp/thistle-controlled-pet-server.log`.

## Automated verification

`mix test.all`: 6,166 passing tests, including DBC, VMangos, and map integration
tests. `mix compile --warnings-as-errors` and `mix credo --strict` passed.
Coverage includes live and dead slot rejection, spell target selection,
owner-level stats and names, passives and resources, implicit wall clipping,
explicit placement, expiry during combat, pet-bar cleanup, and permanent
versus timed restoration. Existing effect-56 behavior and pet attachment
without a spawn record remain covered. No architecture allowlist was expanded.
