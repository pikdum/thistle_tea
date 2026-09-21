# Ammunition selection and ranged launch costs

`CMSG_SET_AMMO` selects a carried ammunition entry or clears the choice with
zero. Selection checks life state, inventory ownership, item type, level,
class, race, skill, and existing item reputation requirements. The normal
inventory projection recomputes ranged damage and saves the selection in the
runtime character store. A chosen ammo type remains selected after its last
stack is consumed, matching VMangos.

Ranged launches now require an available, unbroken weapon and compatible
ammunition. Bows and crossbows consume arrows; guns consume bullets. Thrown
attacks consume the equipped stack itself, or one durability point for a
nonstacking thrown weapon. Wands and the VMangos Blind, Net-o-Matic, and
Expose Weakness exceptions do not consume selected projectiles.

## Ownership and launch ordering

`Logic.Ammunition` validates immutable item inputs and plans costs through
`Inventory.Batch` and `Inventory.plan`. `Player.Ammunition` owns the commit.
Cast-time attacks wait for a typed `LaunchRanged` command before launching;
the Auto Shot tree emits the same command for each repeat. `EventSink.Context`
routes the command to the player owner. No inventory or process dependency
was added to the behavior-tree node.

The owner checks that the request still matches the current cast or pending
repeat. Canceled and already completed requests cannot launch again. It
validates the current weapon and ammo, prepares launch effects with the
weapon still equipped, commits the inventory cost, then emits those effects.
The final thrown item therefore retains its damage and projectile display
even though the ranged slot becomes empty before delivery. Failed payments
emit neither a projectile nor damage; depletion cancels Auto Shot and sends
the native cast failure. Trade and vendor cost settlement also recognize
pending ranged launches.

## References

- `refs/wow_messages/wow_message_parser/wowm/world/item/cmsg_set_ammo.wowm`
  defines the four-byte item-entry payload.
- `refs/vmangos/src/game/Handlers/ItemHandler.cpp`, `HandleSetAmmoOpcode`,
  validates life state and ownership before selection or clearing.
- `refs/vmangos/src/game/Objects/Player.cpp`, `CanUseAmmo`, `SetAmmo`,
  `RemoveAmmo`, and `_ApplyAmmoBonuses`, define selection and damage bonuses.
- `refs/vmangos/src/game/Spells/Spell.cpp`, `TakeAmmo` and the ranged weapon
  checks, distinguish projectiles, thrown stacks, durability, and exceptions.

## Native client acceptance

An isolated World of Warcraft 1.12.1 build-5875 client used Debughunter on
Programmer Isle against code commit `43247ef1`. All mutations used client
inventory actions, casts, existing debug chat commands, and logout/login.
Tidewave probes only read the authoritative player and target state.

- Added two Rough Arrows (`2512`) and selected them with the normal backpack
  use action. The server received `CMSG_SET_AMMO`; displayed ranged damage
  changed from 145.553–186.553 with Jagged Arrows to 114.503–155.503.
- Cast Auto Shot at a level-50 Skeletal Flayer. A 250-ms sampler recorded
  two arrows, one arrow, then zero; the repeat remained active until its next
  scheduled attempt, then stopped. The client displayed **Out of ammo**.
  The choice remained `2512`, and no replacement stack was consumed.
- Selected Light Shot (`2516`) with the bow equipped. Ranged damage fell to
  110.453–151.453, without a projectile bonus. The native client refused the
  shot with its ammo-slot error. Both the 200 bullets and 200 Jagged Arrows
  remained untouched. Server-side mismatch rejection is also automated.
- Picking up the ammo slot while it referenced an owned stack cleared
  `ammo_id` to zero without consuming that stack. Clearing the cursor can
  select the carried ammo again; sampling occurred before that action.
- Learned Thrown (`2567`) and Throw (`2764`) through the debug chat commands,
  equipped two Balanced Throwing Daggers (`2946`), and cast Throw. The first
  attack consumed one dagger and dealt 37 damage while leaving all 200
  selected Jagged Arrows intact. After resetting the target, the final dagger
  was consumed and the ranged slot became empty. The target still took the
  final 37-damage hit; separate five-point Entangling Roots ticks were visible
  in the sample. Ranged damage became zero after equipment removal.
- Re-equipped the bow, selected Jagged Arrows, logged out, and re-entered.
  The same bow GUID, selected entry `11285`, both 200-item projectile stacks,
  and 145.553–186.553 ranged damage survived. The spent arrows and daggers
  stayed absent, with no active cast or Auto Shot loop.

Entangling Roots (`339`), pet passive mode, god mode, and chat teleports
provided the combat setup. Some preliminary attempts were blocked by the
client's range checks; the depletion and final-item results above come from
accepted casts. The nonstacking thrown durability branch uses synthetic
automated fixtures; the generated vanilla item data contains no such item.

The weapon swap exposed a debug seed issue: the dwarf hunter started with
a bow without Bows proficiency. Commit `9982ab56` adds Bows (`264`) before
initial skill derivation. A fresh server and isolated client confirmed Bows
at 250/250, successful native unequip/re-equip of the same bow, and the correct
restored ammo damage, without a manual proficiency grant. The normal
bind-on-equip confirmation was accepted in the client.

Neither acceptance server logged gameplay owner or network errors. Normal
unimplemented account-data, raid-info, GM-ticket, and meeting-stone requests
remain. Both clients and servers were stopped after validation.

## Automated coverage and retained evidence

Tests cover packet dispatch, selection and clearing, restrictions, banked
ammo, compatible projectiles, cast-time depletion without mana payment,
exact repeat costs, duplicate/canceled requests, final thrown damage and
projectile fields, thrown durability, broken weapons, and no-cost exceptions.
The architecture dependency ratchet remains unchanged.

Final code gates: **4,269 tests passed** with `mix test.all`; compilation with
warnings as errors, strict Credo, and formatting checks also passed.

Retained local evidence:

- Main client: `/home/pikdum/.cache/thistle-wow-playtest.Y4dK1H`, including
  `depleted-confirmed.png`, `mismatched-bullets.png`, and `reconnected.png`.
- Fresh seed client: `/home/pikdum/.cache/thistle-wow-playtest.LdMzFb`,
  including `ammo-arrival.png` and `reequipped.png`.
- `/tmp/thistle-ammo-shots-confirmed.txt`, `/tmp/thistle-ammo-last-throw.txt`,
  `/tmp/thistle-ammo-clear.txt`, `/tmp/thistle-ammo-mismatched-bullets.txt`,
  `/tmp/thistle-ammo-reconnected.txt`, and `/tmp/thistle-ammo-seed-*.txt`.
- `/tmp/thistle-ammo-server.log`, `/tmp/thistle-ammo-seed-server.log`,
  `/tmp/thistle-ammo-final-tests.log`, and `/tmp/thistle-ammo-final-credo.log`.
