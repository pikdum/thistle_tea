# Spell actions and game-object use

Spell effect 86 now resolves explicit, nearest scripted, and area game-object
targets separately for each effect. VMangos selectors, conditions, effect masks,
and object-use scripts are preloaded. Selection stays within the current world
copy, checks live presence, and uses deterministic distance/GUID ordering.
Required targets are checked before launch costs; optional nearest targets may
remain empty, matching the reference exceptions.

Effect 59 is now named `open_lock_item`, preserving Opening and Fire Cannon.
Normal and triggered activation spells report object hits and deliver typed
actions through the resolver and the object's owner. Actions support custom
animations, activation, lock and interaction flags, open/close/destroy/rebuild,
and despawn through the existing spawn lifecycle. Undefined reference actions
remain no-ops. Content-specific activation hooks are separate work.

Doors and buttons share pure activation and reset transitions with spell and
script operations. Template auto-close delays use their fixed-point seconds.
Revision tokens reject stale timers after later operations. Raw script state
changes preserve flags. Runtime unlocks reach key and loot-owner checks, and interaction flags,
door state, and condition metadata are projected by the owning process.
Door/button use runs cached spawn scripts and activates nearby linked traps.
Existing generic script activation is retained for other object families.

References: `Spell::EffectActivateObject`, `Spell::CheckScriptTargeting`, object
area targeting in `Spell.cpp`, `GameObject::UseDoorOrButton`,
`ResetDoorOrButton`, `Use`, and `TriggerLinkedGameObject` in `refs/vmangos`.

## Automated acceptance

Coverage includes explicit/nearest/area selection, conditions, inverse masks,
three-dimensional range, long-range lookup, missing targets before costs,
same-copy targeting and delivery, triggered casts, object hit projection,
runtime unlock/relock, independent flags, initial-open doors, destruction and
rebuild, repeated use, stale timers, and linked-trap selection. DBC and VMangos
fixtures are tagged separately. The architecture dependency allowlist is unchanged.

## Native acceptance

Debugmage used isolated GPU-rendered build-5875 clients on Programmer Isle.
All changes came from native input, `/cast`, and existing development commands;
Tidewave only inspected state. The playground now includes real templates for
Doors (138493), Door Lever (17156), Incantation of Celebras (178965), Mortar
(176557), and the stink-bomb pair (180449/180450).

- Right-clicking Doors visibly opened both panels. The owner and metadata
  changed from state/flags `1/0` to `0/1`, then returned to `1/0` after 3,009 ms.
  Loot-state projection followed `1 → 2 → 1`.
- The lever visibly moved and followed the same three-second reset. Its sampler
  observed activation at 1,020 ms and restoration at 4,029 ms.
- Casting Recite Words of Celebras (21950) selected and visibly opened the
  closed book. The sampler observed `1/0 → 0/1` at 5,457 ms and restoration
  at 15,453 ms. The book visibly closed again.
- Clean Up Stink Bomb (24973) removed both bomb and cloud. Both GUIDs lost
  their owning processes, world positions, and metadata. A second cast failed
  with `bad_targets`, with no remaining objects to act on.

The first door fixture was Galen's Cage, whose hostile template offered no
client use cursor. It was replaced with the neutral door and lever above.
Mortar Animate reached the activation path, but its screenshots did not establish
a distinct animation; animation action encoding and triggered delivery are
covered by automated tests rather than claimed as native visual acceptance.

Local evidence:

- `/home/pikdum/.cache/thistle-wow-playtest.x60ibS/screenshots/`:
  `bomb-casting.png`, `bomb-after.png`, `missing-bomb-rejected.png`.
- `/home/pikdum/.cache/thistle-wow-playtest.9mwDl0/screenshots/`:
  `door-before.png`, `door-open-mid.png`, `door-restored.png`,
  `lever-before.png`, `lever-used.png`, `book-before.png`, `book-open.png`,
  `book-restored.png`.
- `/tmp/thistle-object-actions-door-sample.log`,
  `/tmp/thistle-object-actions-lever-sample.log`,
  `/tmp/thistle-object-actions-incantation-sample.log`, and
  `/tmp/thistle-object-actions-server{,2}.log`.

WoW's own AMD graphics counter in the second session advanced from
1,607,305,042 to 10,520,781,849 ns. Both owned clients and retained servers were
stopped. No gameplay process errors appeared; the first log includes the
intentional missing-bomb rejection and the existing unsupported login requests.

Validation commands: `mix test.all`, `mix compile --warnings-as-errors`,
`mix credo --strict`, `mix format --check-formatted`, and `git diff --check`.
