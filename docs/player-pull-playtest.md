# Spell-driven player pulls

Implementation: `e5285ff2` (`feat(spells): support ballistic player pulls`).

## Behavior and references

DBC effect 124 is now `:player_pull`, dispatched through the movement semantic.
Tractor Beam, Magnetic Pull, Spider Web, and all four Web Wrap variants load
through this shared path.

The launch uses horizontal speed `max(misc_value, 1) / 10`. Flight time comes
from horizontal distance minus the two units' bounding radii. The vertical
speed accounts for the caster's height and client gravity, 19.29110527038574.
Caster radius is captured with the existing cast snapshot; target geometry is
read at effect receipt. Self, overlapping targets, and another world produce
no launch.

This follows the projectile model in
[CMaNGOS Classic's `EffectPullTowards`](https://github.com/cmangos/mangos-classic/blob/master/src/game/Spells/SpellEffects.cpp),
with distance semantics from
[`WorldObject::GetDistance`](https://github.com/cmangos/mangos-classic/blob/master/src/game/Entities/Object.cpp).
Local VMangos `8f4e60845` explicitly marks its generic `EffectPlayerPull`
calculation as incorrect and replaces it in Thaddius's Magnetic Pull script.
The gravity constant also appears in its `Movement/spline/util.cpp`.

Pull uses the existing typed `Knockback` effect and controller/observer packet
path. That retains single-use acknowledgement validation, cast and auto-repeat
interruption, fall tracking, possession routing, and teleport invalidation.
Root, stun, death, taxi, and server-controlled movement block it. Ordinary
creatures retain the existing interruption behavior without a client impulse.
Pull has its own effect immunity and does not inherit knockback's Dream Fog
removal. Encounter-specific Web Wrap scripting is outside this acceptance.

## Automated acceptance

- `mix test.all`: **4,818 passed**.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 1,872 source files.
- Focused movement, packet, and DBC tests: 18 passed.

New regression cases cover trajectories to lower, level, and higher casters;
bounding radii; no-op geometry and invalid speed; cast interruption; movement
restrictions; independent effect immunity; and all seven real DBC spells.
Existing knockback packet, possession, and lifecycle tests remain green.

## Native build-5875 acceptance

Two isolated clients used Debugwarrior (GUID 1) and Debugpaladin (GUID 2), level
60, on open-world map 451. God mode was not enabled. Setup used `.learn 8690`
on the warrior and `.learn 28337` on the paladin. No runtime mutation probes
were used.

The warrior started at `{16363.0, 16318.0996, 69.4400}`, the paladin at
`{16303.2002, 16318.0996, 69.4400}`. The warrior cast Hearthstone; the paladin
targeted it and cast Magnetic Pull through native chat commands. Server logs
recorded both `CMSG_CAST_SPELL` requests.

The first pull showed an interrupted cast bar and landed the warrior beside
the paladin at x=16304.0. Its sampler timed out, so the same action was repeated
with a longer probe deadline. The repeat captured these authoritative states:

| State | Evidence |
| --- | --- |
| Preparing | Hearthstone 8690 active; movement counter 3 |
| Launch | Cast cleared; pending counter 3 carried impulse `{-1, ~0, 30, -18.9766}`; next counter 4 |
| Acknowledged | Pending map empty; airborne flags 8193 |
| Flight | Position `{16333.0, 16318.0996, 78.7710}`; owner and world projection agreed |
| Landing | Position `{16304.0400, 16318.0996, 69.4445}`; flags 0; no cast, fall, or pending acknowledgement |
| Control restored | Native forward key moved the warrior to x=16310.3818, then stopped normally |

The warrior retained 3,299 health throughout. The paladin's client showed the
warrior airborne and subsequently beside it; the warrior's client displayed
the interrupted Hearthstone cast and landing. Final owner and public world
positions agreed for both players.

No movement, owner, visibility, or gameplay errors appeared. The only warnings
were the existing account-data, raid-info, GM-ticket, and meeting-stone requests.
Both clients, private X servers, and the retained server were stopped.

## Retained evidence

- Warrior: `/home/pikdum/.cache/thistle-wow-playtest.PqD5ik/screenshots/`, including
  `pulled-airborne.png`, `pulled-landed-repeat.png`, and `walking-after-pull.png`.
- Paladin: `/home/pikdum/.cache/thistle-wow-playtest.KtLYRQ/screenshots/`, including
  `observer-before.png`, `observer-airborne-repeat.png`, and `observer-landed.png`.
- Server: `/tmp/thistle-pull-server.log`.
- State: `/tmp/thistle-pull-baseline.json`, `/tmp/thistle-pull-first-landed.json`,
  `/tmp/thistle-pull-flight-repeat.json`, and `/tmp/thistle-pull-final.json`.
- Gates: `/tmp/thistle-pull-{focused,tests,compile,credo}.log`.
