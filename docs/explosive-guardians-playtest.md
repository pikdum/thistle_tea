# Explosive engineering guardians

## Behavior

Explosive Sheep and Goblin Bomb Dispenser use the shared guardian, pet AI,
melee proc, spell targeting, and death pipelines. Their first landed melee
swing consumes a single proc charge and triggers an area explosion. Idle
sheep detonate after three minutes; bombs detonate after one minute. Both
leave a corpse for five seconds.

The dispenser chooses a summon with 90% probability or a party-area
malfunction with 10% probability. Its successful child cast retains the
item identity so engineering skill still determines the bomb's level.
The trinket starts its ordinary 30-minute cooldown immediately. Sheep
hold their one-minute item category cooldown until death or removal.
The stored cast timestamp prevents an old guardian from activating a
newer cooldown, and departure updates the cooldown before saving the owner.

Triggered area spells now retain recipients separately for each effect.
Explosion damage reaches enemies; the self-targeted Quiet Suicide reaches
the summon once, including when no enemies are nearby. Destination-only
caster effects retain the caster even when an enemy is selected.

## Reference and data

Compared with local VMangos revision
`8f4e608450460efe1e38743e4da74397d4773a3a`:

- `src/scripts/world/npcs_special.cpp`: engineering guardian passives,
  aggressive behavior, lifetime explosions, and five-second corpse delays.
- `src/game/Spells/SpellEffects.cpp`: dispenser probabilities, retained cast
  item, and Explosive Sheep's deferred cooldown.
- DBC spells 4051/4050 and 13260/13259: one-charge melee proc, enemy area
  damage, and self-targeted Quiet Suicide 3617. Spell 13261 targets the
  nearby party, not every friendly unit.

The local sheep seed also supplies aura 8327, which triggers plain Suicide
8329 after 180 seconds. Guardian creation excludes this redundant timer
and applies the creation passive once. The cached seed remains unchanged.
Activating deferred cooldowns on other deaths and owner departure is a
local lifecycle safeguard in addition to VMangos's explosion callback.

## Automated acceptance

`mix test.all`: **7,092 passed**. `mix compile --warnings-as-errors` and
`mix credo --strict` pass. Tests cover proc charge consumption, missed swings,
damage ranges, multiple recipients, empty areas, self-destruction, malfunction
selection, retained items, one-shot expiry, death, departure, stale cooldown
events, loader configuration, and unchanged cached addon data.

Final logs:

- `/tmp/thistle-explosives-addon-all.log`
- `/tmp/thistle-explosives-addon-compile.log`
- `/tmp/thistle-explosives-addon-credo.log`

## Native acceptance

Build 5875, Debugwarrior, engineering 300, isolated hardware-rendered client.
Setup used ordinary GM commands; casts used native item actions. Runtime
probes only read owner state, inventory, registry, spatial, and metadata data.

First session: `/home/pikdum/.cache/thistle-wow-playtest.Tcw8ko`.
Server log: `/tmp/thistle-explosives-server.log`.

- Using item 4384 consumed one sheep and retained a pending cooldown.
  Teleport departure removed the guardian and activated the 60-second timer.
- Against a nearby Defias Thug, the sheep consumed aura 4051's charge,
  killed the target, and reached zero health with itself as killer.
  The cooldown activated in the same transition. Registry, position, metadata,
  and owner reference were absent five seconds later.
  `/tmp/thistle-explosives-defias.log` records these transitions.
- A sheep killed by higher-level enemies retained its unspent charge and
  still released its cooldown. Early idle attempts were within range of a
  Bloodseeker Bat; they were not accepted as lifetime tests.
- The dispenser's native item path created a level-60 bomb and retained its
  30-minute cooldown. The first combat bomb spent its passive and died;
  precise damage was not sampled in that attempt.

Retest after removing the redundant addon timer:
`/home/pikdum/.cache/thistle-wow-playtest.9yYVNx`.
Server log: `/tmp/thistle-explosives-retest-server.log`.

- At an isolated location, both guardians started alive with their single
  creation passive. The sheep had 1,003 health; the level-60 bomb had 3,662.
  The sheep had no aura 8327. Deadlines were exactly 180,000 and 60,000 ms
  from construction. The sheep cooldown was pending; the dispenser cooldown
  was already running. See `/tmp/thistle-explosives-idle-initial.log`.
- The bomb completed its lifetime and cleanup while the sheep remained
  idle and alive past two minutes.
- The sheep's recorded expiry deadline was `-576460490329`. Its resulting
  cooldown deadline was `-576460430252`, putting activation 77 ms after the
  three-minute expiry. The guardian disappeared and its selected client
  target cleared. The live and later empty client views are retained as
  `sheep-awaiting-expiry.png` and `sheep-expiry-1.png`. The longer sampling
  request exceeded the CLI's HTTP timeout, so no detailed idle death trace
  is claimed from that request.
- A second sheep was alive with a pending cooldown before `/logout`.
  Logout removed its process and spatial/metadata projections. Reconnect
  retained three sheep items, the activated sheep cooldown, and the
  dispenser's original cooldown; the guardian collection remained empty.
  See `/tmp/thistle-explosives-before-logout.log` and
  `/tmp/thistle-explosives-reconnect.log`.
- The final code repeated contact detonation against an 86-health Defias
  Thug. Both target and sheep reached zero health, the sheep named itself
  as killer, and its aura list was empty. `contact-result-5.png` shows both
  corpses and the client's Explosive Sheep corpse tooltip. The observer
  caught the death transition but raced process removal on its final read;
  `/tmp/thistle-explosives-final-cleanup.log` separately confirms all owner,
  registry, spatial, and metadata state was removed. Two sheep items remained.

The retest WoW process used AMDGPU; its own graphics-engine counter advanced
from 4,284,648,703 to 11,280,217,335 ns. Logs contained no gameplay owner errors.
Existing account-data and GM-ticket login warnings remained.

The 10% malfunction branch is covered deterministically with the real DBC
spell and weighted outcome tests; it was not observed in the native runs.

Both isolated clients and local servers were stopped. Evidence remains in
the recorded session directories. No changes were pushed.
