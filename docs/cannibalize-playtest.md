# Cannibalize and triggered channels

Cannibalize (20577) requires a nearby, visible, nonfriendly humanoid or undead
body. Dead players and released player corpses qualify; living units, ghosts,
taxi riders, other creature types, and bodies in another world copy do not.
The five-yard range includes both bounding radii and checks vertical distance.
The body is not consumed. Corpse processes retain their owner's faction metadata
so eligibility remains correct after the owner leaves.

The player boundary checks eligibility before starting, and the shared cast
requirements effect checks it again before paying costs or starting cooldowns.
Missing bodies produce the native no-edible-corpses error and clear the client's
predicted cooldown. An existing cooldown still rejects the cast normally.
These spells validate their nearby body independently of the selected unit.

A successful cast starts the real triggered channel 20578 through the caster's
owner process. Triggered channels retain their selected target and trigger
context, use ordinary channel packets and cleanup, and skip normal cast costs,
reagents, global cooldowns, cooldown starts, and cast-complete procs. Cannibalize
heals seven percent of maximum health every two seconds for ten seconds. Its
root spell retains the two-minute cooldown.

Removing a channel's own aura now ends the channel in the same transition.
This covers Cannibalize's damage interruption, including periodic damage.
The eating pose starts with the healing ticks and clears on aura removal.
The pose also applies to energy and rage users; unlike the local VMangos
script's power-type guard, it does not require mana.

The existing spell override loader now caches `spell_mod.AuraInterruptFlags`.
Cannibalize needs its damage-interrupt correction because the DBC field is zero.
No database queries were added to gameplay paths, and the architecture dependency
allowlist is unchanged. Spatial candidates remain behind `World`.

Local references: VMangos `spell_special.cpp` Cannibalize scripts,
`Spell::FindCorpseUsing`, `AnyDeadUnitObjectInRangeCheck`, and the `spell_mod`
entry for 20578. Automated coverage checks eligibility and world isolation,
faction retention by a real corpse process, prelaunch rejection and packets,
cooldown preservation, exact healing ticks, damage and cancellation cleanup,
DBC loading, VMangos corrections, and original-owner channel delivery.

## Native acceptance

Acceptance uses an isolated GPU-rendered build-5875 client and Debugrogue on
Programmer Isle and in Northshire. All gameplay changes come from native input
or existing development chat commands; runtime probes only read state.

With no eligible corpse, the client displayed "There are no nearby corpses to
eat". Its `GetSpellCooldown` result was `0, 0, 1`, and the owner retained no
cast or cooldown. A successful racial cast beside a dead Defias Thug showed
the channel bar, recovery aura, eating pose, and floating `+132` heals.
The client reported a 120-second cooldown.

In the clean acceptance run, maximum health was 1,898. The owner sampler saw
the channel start at 2,195 ms, then five 132-health increases at 4,176, 6,130,
8,287, 10,259, and 12,221 ms. Separate 34-health increases came from ordinary
regeneration. The last recovery tick cleared the channel and aura, and reset
the emote from 398 to zero.

The child recovery spell was then learned separately for cancellation checks
without waiting on the racial cooldown. Moving after its first heal cleared
all three states at 6,029 ms; subsequent samples contained only normal
regeneration. Closing the helper-owned client during another channel changed
the owner from an active channel and emote 398 to offline saved state with
no cast, aura, channel, or pose. Reconnecting restored that clean state.
Damage cancellation, including periodic damage, is covered by automated tests.

The WoW process's own AMD DRM graphics counter advanced from 5,709,443,719 to
50,168,490,663 ns during the session. Both exact helper-owned systemd sessions
and the retained server were stopped after testing. The clean acceptance server
log contained no errors. An earlier preparation run was discarded after hot
reloading the world module interrupted live entities.

Local evidence:

- `/home/pikdum/.cache/thistle-wow-playtest.gGPvln/screenshots/`, including
  `no-edible-corpses.png`, `channel-animation-final.png`,
  `acceptance-before-movement.png`, `acceptance-after-movement.png`, and
  `acceptance-before-disconnect.png`.
- `/home/pikdum/.cache/thistle-wow-playtest.5SZVqX/screenshots/acceptance-reconnect.png`.
- `/tmp/thistle-cannibalize-acceptance-full.txt`,
  `/tmp/thistle-cannibalize-acceptance-movement.txt`,
  `/tmp/thistle-cannibalize-acceptance-disconnect.txt`,
  `/tmp/thistle-cannibalize-acceptance-offline.txt`,
  `/tmp/thistle-cannibalize-acceptance-reconnect.txt`, and
  `/tmp/thistle-cannibalize-server-acceptance.log`.

Validation: `mix test.all`, `mix compile --warnings-as-errors`,
`mix credo --strict`, `mix format --check-formatted`, and `git diff --check`.
