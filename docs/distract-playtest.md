# Distract

Rogue Distract (1725) now turns responsive units toward the selected ground
point and pauses creature navigation for the effect's duration. The vanilla
DBC supplies a 10-yard radius and a 10-second pause. Players turn without
receiving a navigation lock. Dead, fighting, stunned, confused, feared, and
feigning-death targets ignore the effect.

`Logic.Distraction` owns the pure turn/pause rules. The typed navigation
blackboard retains the patrol destination while its distraction deadline is
active. Mob and pet behavior trees hold idle movement; aggro checks remain
active, and `Logic.Engagement.enter` clears the pause on combat entry.
The existing movement effects publish the stop and facing change.

The spell loader now recognizes the vanilla `NO_THREAT` and
`ALLOW_WHILE_STEALTHED` attributes. Hostile targeting remains separate from
combat initiation: Distract can select enemies and roll a resist without
starting combat or breaking the caster's stealth. This does not implement
Pick Pocket or other deferred spell effects.

References in the pinned VMangos checkout:

- `src/game/Spells/SpellEffects.cpp`: `Spell::EffectDistract`.
- `src/game/Spells/SpellDefines.h`: effect 69 and extended attribute bits
  `0x400` (no threat), `0x20` (allow while stealthed).
- `src/game/Spells/Spell.cpp`: hit/miss combat initiation checks.
- `src/game/Movement/IdleMovementGenerator.cpp`: distraction lifetime.

## Real-client check

Tested with the isolated build-5875 client as Debugrogue, using the normal
spell and ground-target click, against wandering Riverpaw Outrunner spawn
81116 in Elwynn Forest. No runtime mutation was used to trigger the effect.

1. Start a fresh server, wait for `Debug seed ready`, and launch the helper.
2. Select Debugrogue. Travel to `.go xyz -9010 -815 73 0`, allow terrain to
   load, and cast Stealth. If the map transfer places the client beneath
   terrain, repeat the same teleport after loading finishes.
3. Target Riverpaw Outrunner. Cast Distract and click the ground near it.
   On the tested camera, the click was near `(745, 285)` in the 1280x720
   client; recheck the mob and camera before reusing that coordinate.
4. Observe the creature turn and stop, then resume walking after 10 seconds.
   Confirm the rogue's stealth aura remains and no combat starts.

A read-only owner sampler recorded the second cast while the creature was
already walking. Times below are seconds relative to sampler startup;
columns show the creature's world position and orientation in radians.

| Sample | X | Y | Facing | Pause active |
| --- | --- | --- | --- | --- |
| 0 | -8993.529 | -818.328 | -3.085 | No |
| 1 | -8998.007 | -818.581 | 2.194 | Yes |
| 2 through 10 | -8998.007 | -818.581 | 2.194 | Yes |
| 11 | -8998.147 | -818.588 | -3.085 | No |
| 12 | -8999.370 | -818.657 | -3.085 | No |

Both owners remained out of combat, and the rogue remained stealthed in
all 17 samples. Server logs recorded two `CMSG_CAST_SPELL: Distract - 1725`
requests with no gameplay errors. Existing unrelated unimplemented login
and trade-query warnings were present.

Retained local evidence:

- `/home/pikdum/.cache/thistle-wow-playtest.7rcuEK/screenshots/`
- `/tmp/thistle-distract-timed.txt`
- `/tmp/thistle-distract-server.log`

Automated regression coverage includes moving-position interpolation,
expiry and patrol resumption, combat cancellation, ineligible targets,
player facing, spell dispatch, stealth retention, owner-level hit/resist
handling, and the real DBC definition. Combat cancellation and player
facing were checked automatically, not with a second player client.

Final validation: `mix compile --warnings-as-errors`, `mix test.all`
(2,773 passing tests), and `mix credo --strict` all passed. The isolated
client and local server were stopped after testing; evidence was retained.
