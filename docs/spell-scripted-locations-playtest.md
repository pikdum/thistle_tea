# Scripted spell destinations

Implemented and accepted on 2026-09-27 in `aa28b5b6`.

## Shared behavior

DBC target 46 now resolves a destination from nearby creatures, corpses, or game
objects using cached `spell_script_target` selectors. It reuses the creature and
object searches, including entry, life state, conditions, inverse effect masks,
modified radius, live owner presence, and world-copy isolation. An eligible
explicit creature takes precedence; otherwise candidates compete by distance
with stable GUID ordering. Object selectors can refer to the required focus.

Locations retain their supplying entity and effect index. As in VMangos, the last
location effect supplies the cast's destination. That destination replaces
client-supplied coordinates and reaches the launch packet, ground effects, and
summon context. Missing locations reject admission and are checked again before
launch costs. Missing spell focuses retain their more specific protocol error.

A primary location target also receives its effect when appropriate. Secondary
location targets supply coordinates while preserving the ordinary unit target.
Persistent ground effects do not apply directly to the creature that supplied
their position. Object hits remain distinct from unit delivery. Triggered spells
resolve at the original caster and retain the destination through delivery.

This exposed a shared summon-delivery bug: an enemy-targeted summon was removed
from the caster's effects even though its execution belongs to the caster.
Caster-executed summons now survive that filter. Summon Screecher Spirit can
therefore create its spirit at the corpse while its separate dummy effect uses
the existing corpse-removal lifecycle.

This milestone covers target 46 for unit casts and triggered spells. The later
[game-object targeting milestone](game-object-spell-targeting-playtest.md)
extends target resolution to trap and quest-object casts. Content-specific NPC
scripts remain separate work. In particular, `npc_pats_firework_guy` does not yet automatically execute
the holiday firework sequence; the native tests below cast its two spells
separately. They do not claim complete Lunar Festival behavior.

## Native acceptance

Fresh server, genuine build-5875 client, Debugmage GUID 5 on Programmer Isle, map
451. `dev_seed.ex` provides Vale Screecher 5307, Rogue Vale Screecher 5308, and
Firework Launcher 180771. Item uses and spell casts went through native client
input; Tidewave was used for read-only observation.

| Action | Client and authoritative result |
| --- | --- |
| Use Yeh'kinya's Bramble 10699 with only living Screechers nearby | “Invalid target”; item count stays one, mana remains 3693, no cast or cooldown starts |
| Kill Vale Screecher with Death Touch, then use the bramble | A visible Screecher Spirit 8612 appears at the corpse's exact position, `{16393.2, 16178.1, 69.44424438476562}` |
| Explicitly select the Vale Screecher corpse and use the bramble again | Another spirit appears at the same position; the selected corpse loses its world position through delayed removal |
| Cast Rocket, RED 26347 away from the launcher | “Requires Firework Launcher”, with the expected `requires_spell_focus` rejection |
| Move beside the launcher and cast Small Red Rocket 26286 | Its creature summon 15882 appears at the launcher's position, `{16393.2, 16138.1, 69.44424438476562}`, rather than at the caster |
| Cast Rocket, RED while that summon exists | The client receives rocket object 180851 at the same destination; the launcher shows its activation animation |
| Wait for the rocket object's five-second lifetime | A 50 ms sampler observes creation and removal 4,998 ms apart; owner, metadata, and world position are then absent |
| Cast Rocket, RED after the marker expires, while the focus still exists | “Invalid target”; the creature selector and conditioned object selector cannot supply a valid destination |

The first corpse use also demonstrated that the secondary location and explicit
unit are distinct: incoming combat had made the client select the surviving
Rogue Vale Screecher. The corpse supplied the location, but the removal dummy
remained bound to the living selection. Explicitly selecting the dead Vale
Screecher for the next cast exercised corpse cleanup.

The character died during stationary setup and reclaimed its corpse normally.
God mode was then enabled for the successful corpse and rocket cases. These
casts establish targeting, presentation, and lifecycle; resource-cost assertions
come from the automated regressions and the initial rejection before god mode.

Normal logout removed the player owner, metadata, and world position. Reconnect
retained the bramble with no active cast, channel, or script run. The log contains
the three expected validation rejections and the existing unimplemented
account-data and GM-ticket packet warnings, with no runtime errors.

## Automated coverage

`mix test.all`: **6,908 passed** in 69.4 seconds. Compilation with warnings as
errors and strict Credo passed. The architecture allowlist is unchanged.

Regressions cover competing unit/object candidates, explicit selection, client
coordinate replacement, conditions and masks, corpses, focus identity, missing
owners, hidden objects, height and copy isolation, launch rejection before costs,
per-effect healing, object-hit projection, triggered summon placement, original
caster routing, corpse removal, and ground-effect recipient exclusion. DBC tests
verify real corpse, creature, and object destination spells.

An earlier full run failed while waiting for the existing door test's temporary
open state. The isolated spawn-pool tests and the final full rerun passed; no
door code or test timing was changed.

## References and evidence

Reference checkout: `refs/vmangos`, commit
`8f4e608450460efe1e38743e4da74397d4773a3a`, especially `SpellDefines.h`,
`Spell::CheckScriptTargeting`, and `Spell::SetTargetMap`. The generated selector,
condition, and effect-override rows were checked for spells 12699, 26286, and
26347.

Native session: `/home/pikdum/.cache/thistle-wow-playtest.hErVd1`, GPU renderer,
owned unit `thistle-wow-playtest.hErVd1.service`, invocation
`9bf7aa35633f43e7993181d0345df811`. WoW PID 2075953 belonged to that cgroup; its
own DRM graphics counter advanced from 5.395 to 22.487 billion nanoseconds.

Screenshots include `living-screecher-rejected.png`,
`summoned-screecher-spirit.png`, `corpse-spirit-cleanup.png`,
`rocket-missing-focus.png`, `rocket-at-launcher.png`, `rocket-expiry-sample.png`,
and `rocket-missing-marker.png`. Server logs, timing observations, and gates are
retained under `/tmp/thistle-location-*`.

The helper stopped the owned client unit; it is inactive with an empty cgroup and
WoW PID 2075953 is gone. Disconnect also removed the player owner, metadata, and
position. The server PTY was stopped and ports 4000, 3724, and 8085 were free.
No push was performed.
