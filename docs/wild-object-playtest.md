# Ownerless summoned world objects

Spell effect 76 now creates world objects independently of the caster. The
spell's object template supplies interaction, loot, and trap behavior; its
duration controls removal. Logging out does not remove an ownerless object.
This supports reusable mechanics such as Summon Chicken Egg and Sand Trap.

The pure spell effect emits a typed summon request once per effect, even when
the spell has another selected target. The boundary creates the object and
its optional linked object in the caster's world. Explicit destination
coordinates, including zero coordinates, are preserved. Untimed summons have
no expiry timer. Runtime GUID allocation avoids collisions with seeded objects.

Summoned chests use the existing lock and loot systems. Consuming one removes
it permanently instead of scheduling the static chest respawn. Parent removal
also removes linked objects, with process, visibility, position, and metadata
cleanup. Linked trap activation uses the existing object interaction path.

Ownerless traps detect living players, respect their template radius and arming
delay, and cast through the shared spell resolver. Owned traps retain hostile
target selection. Charge zero means unlimited activations; positive charges
decrease, and the final activation depletes the trap before asynchronous
removal. Repeating traps respect their cooldown. A zero-radius linked trap
requires explicit activation.

Wild objects publish level zero, as VMangos does. Publishing the summoner's
level made the vanilla client refuse to open the egg before sending any
opening request. Environmental trap spell resolution separately uses the
template level, then a positive object level, then level 60. The spell caster
snapshot uses the typed internal component so area spells can resolve its
world position correctly.

References: `Spell::EffectSummonObjectWild` in
`refs/vmangos/src/game/Spells/SpellEffects.cpp`, and trap activation, linked
objects, and `GameObject::GetLevel` in
`refs/vmangos/src/game/Objects/GameObject.cpp`.

This implements the shared summon and interaction paths. It does not add
content-specific quest scripts, battleground flag bookkeeping, or collision
clipping for offset destination placement.

## Automated validation

- `mix test.all`: **4,392 passed**.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Commit formatting and lint hooks: passed.

Tests cover caster-only execution, multiple effects, explicit zero coordinates,
offset placement, untimed objects, template loot and locks, linked cleanup,
expiry, consumed chest removal, trap charges and cooldowns, and real DBC area
spell delivery. The DBC trap test verifies the level-60 fallback and rejects a
second activation queued before the first activation's removal. Loader tests
use Summon Chicken Egg, Sand Trap, and the two-object Gordunni spell.

A full-suite run also exposed a pre-existing nondeterministic avoidance proc
fixture: its block scenario could randomly parry first. The fixture now removes
earlier avoidance outcomes explicitly; production combat logic was unchanged.

Logs: `/tmp/thistle-wild-level-{all,compile,credo,commit}.log`.
Implementation commits: `c8ce772f` and `cce58196`; fixture correction: `fba7d96a`.

## Native client acceptance

Used two isolated build-5875 clients on map 451: level-50 Human Warlock
Debugwarlock (GUID 6) and Human Mage Debugbidder (GUID 11). God mode was off.
Existing `.go xyz` and `.learn` commands supplied staging. Casts, opening,
looting, logout, and reconnect used native client actions. Tidewave probes
only read state.

| Scenario | Observed result |
| --- | --- |
| Summon Chicken Egg 13563 | Created Farm Chicken Egg 161513 at the caster's position, with no owner, loot template 10100, and a 120-second lifetime. Both clients queried and displayed the object. |
| Caster logout | The Warlock logged out; the Mage continued to see and interact with the egg. |
| Opening and loot | The Mage right-clicked the egg, sent Opening 3365, saw Chicken Egg in the native loot window, and clicked its loot slot. Item 11110 increased from zero to one. |
| Consumed cleanup | The egg disappeared. Its process, world position, and metadata were absent. |
| Reconnect | The Mage logged out and back in and retained the acquired egg in the runtime character store. |
| Natural expiry | In the earlier run on `c8ce772f`, an unlooted egg disappeared after its 120-second lifetime while its caster was logged out. |
| Sand Trap 25648 | Created ownerless object 180647. The nearby Warlock went from 2,059 health to zero; the Mage 25 yards away remained at 1,875 health. The trap disappeared and all three cleanup probes returned nil. |
| Timed trap activation | A second trap, cast by the Mage, appeared at sample time 2,543 ms with level zero, one charge, radius 15, and a 4,000 ms arming delay. At 6,552 ms, the Mage went from 1,875 health to zero and the trap was absent. Its process, position, and metadata were also absent. |

The final native run used `cce58196`'s source. The initial run exposed the
object-level interaction bug; the final run verified normal opening and loot.
The deterministic DBC test exposed and fixed the typed caster snapshot bug.
Linked objects, repeated trap charges, zero-coordinate placement, and duplicate
activation suppression were validated by automated tests rather than by a
native content chain.

No gameplay owner crashes or failed spell casts appeared in the final server
log. Existing unimplemented account-data, raid-info, GM-ticket, and
meeting-stone notifications remain. A temporary diagnostic sampler initially
failed to encode its trap struct; after converting the snapshot to a map, the
second trap run captured the timing above.

## Retained evidence

- Final server: `/tmp/thistle-wild-level-server.log`.
- Initial expiry run: `/tmp/thistle-wild-server.log` and
  `/tmp/thistle-wild-{before,summoned,logout,expired,trap}.txt`.
- Final egg probes: `/tmp/thistle-wild-level-{before,summoned,opened,looted,reconnected,cleanup}.txt`.
- Trap probes: `/tmp/thistle-wild-level-trap-{death,cleanup,sample-mage,cleanup-mage}.txt`.
- Final Mage screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.q9PWk8/screenshots/`, including
  `wild-level-loot.png`, `wild-level-observer.png`, and
  `wild-level-trap-death.png`.
- Final Warlock screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.cdnQwL/screenshots/`, including
  `wild-level-trap-triggered.png`.
- Initial expiry screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.bvcMDD/screenshots/`, including
  `wild-after-caster-logout.png` and `wild-expired.png`.

All helper-owned clients, displays, and native test servers were stopped.
No changes were pushed.
