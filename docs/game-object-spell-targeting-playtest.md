# Game-object spell targeting

Implemented and accepted on 2026-09-27 in `c0357e95`.

Traps and quest objects now resolve spell recipients by effect. They share the
unit, object, and destination selectors used by ordinary casts: entry and life
state, conditions, inverse effect masks, radius, live presence, and world-copy
isolation. Launch packets retain the resolved recipients and destination;
deliveries retain effect indices. A missing required creature produces no
delivery instead of substituting the player who activated the object.

The source is the actual game object, so conditions can inspect its entry and
geometry without a fabricated unit. Owned traps retain their owner's damage
attribution, level, faction, and control relationship while searching from the
trap's position. Persistent trap areas retain their existing lifecycle. This
work covers target resolution and immediate deliveries; it does not implement
every object-cast summon or content-specific script.

Native testing exposed a separate combat bug. Damage from an ownerless object
could make a creature attack that object, then evade and restore full health.
Combat admission and threat now accept unit opponents only. Object damage still
reduces health, applies auras, and can kill; it preserves an existing fight with
a unit. It does not create an object opponent or put an idle player in combat.

## Native acceptance

Genuine build-5875 client, Debugmage GUID 5, fresh local server, Programmer Isle
map 451. God mode was enabled to survive stationary observation. Object use,
player spells, teleporting, logout, and reconnect used native client input.
Tidewave supplied read-only owner and projection observations.

The development playground contains Challenge to Urok button 175584 and its
linked trap 175589 at `{16043.2, 16134.1, 69.44436645507812}`. Nearby are Urok Ogre
Magus **10602** (low GUID 992900) and Urok Enforcer **10601** (992901). The generated
selector for trap spell 16452, Kill Urok Minion, names **10602**. The two creature
names were initially reversed in test commentary; the entry IDs and database
names above are the verified mapping.

| Native action | Observed result |
| --- | --- |
| Right-click the skull-pile button within interaction range | `CMSG_GAMEOBJ_USE` for 175584 reaches the button and activates its linked trap |
| Activate with both living creatures nearby | Magus health falls from 10,455 to 455; spell 16452's stun and visible spell animation appear; Enforcer health stays 13,070 |
| Let the stun expire | Magus remains outside combat with no victim or threat; health recovers through ordinary regeneration in 3,485-point steps instead of an evade reset |
| Engage the creatures with player spells, then activate again | Trap damage preserves the existing player opponent; it does not add object threat |
| Reactivate after the button resets | The wounded Magus dies; health is zero, target zero, threat empty, combat false, and auras empty; the client shows its corpse |
| Activate while the only matching creature is dead | The button activates, but the Enforcer retains health 12,311 and player threat 759 from the player's earlier spells; no fallback hit occurs |

Before the combat fix, a 50 ms sampler captured Magus health 10,130 -> 130, with
the trap GUID as victim, followed by a reset to 10,130 when the stun ended.
After the fix, the sampler retained health 455 through stun removal, then
observed ordinary regeneration to 3,940 and 7,425 with no victim or threat.

Normal logout removed the player owner, metadata, and world position. Reconnect
returned Debugmage with no active cast, channel, combat, or script run. The fixed
server log contains the existing unimplemented account-data and GM-ticket
packet warnings, with no runtime errors.

## Automated coverage

`mix test.all`: **6,919 passed** in 69.5 seconds. Compilation with warnings as
errors and strict Credo passed. The commit hooks also passed Credo and formatting.

The new regressions cover separate effect recipients and actual healing,
source-entry conditions, absent and out-of-range creatures, copy isolation,
source and destination areas, resolved destination coordinates, owner
attribution and faction, object actions, goober completion, one-shot trap
delivery and owner/presence cleanup, and object damage against idle or engaged
creatures and players. Existing Frost Trap persistent-area and campfire damage
tests also pass. The architecture allowlist is unchanged.

## References and evidence

Reference checkout: `refs/vmangos` at
`8f4e608450460efe1e38743e4da74397d4773a3a`, especially game-object trap casting and
`GameObject::Use`, scripted target selection in `Spell.cpp`, and its distinction
between world-object casters and unit combat opponents. The local generated
game-object templates, creature names, DBC spell, and `spell_script_target`
record were inspected directly.

Client session: `/home/pikdum/.cache/thistle-wow-playtest.gNpTTI`.
Owned unit: `thistle-wow-playtest.gNpTTI.service`, invocation
`fb4a0401726a4d0e8acaab54bdc085fb`.
WoW PID 2095498 belonged to that cgroup; its own DRM graphics counter increased
from 719,827,511 to 21,852,593,485 ns during acceptance.

The helper-owned client service is stopped with an empty cgroup and its WoW PID
gone. The retained server PTY exited successfully; ports 4000, 3724, and 8085 are
free. Logs and screenshots remain available.

Retained evidence includes `urok-close.png`, `urok-fixed-hit.png`,
`urok-magus-killed.png`, and `urok-dead-selector.png`; server logs
`/tmp/thistle-object-native-server.log` and `/tmp/thistle-object-native-fixed.log`;
and `/tmp/thistle-urok-native-samples.log`, `/tmp/thistle-urok-fixed-samples.log`,
and `/tmp/thistle-urok-native-final.log`.
Final gate logs are `/tmp/thistle-object-final-all.log`,
`/tmp/thistle-object-final-compile.log`, and `/tmp/thistle-object-final-credo.log`.
