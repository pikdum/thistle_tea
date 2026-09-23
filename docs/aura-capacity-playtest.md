# Buff and debuff capacity

Aura capacity now limits active visible holders, rather than merely hiding
icons after the client slots fill. Each unit supports 32 visible buffs and 16
visible debuffs. Overflow removes the lowest-priority holder; equal priorities
prefer newer applications. Refreshing protects the refreshed holder, stacks
share one slot, and replacements reuse freed slots without moving other icons.

Buff priorities distinguish permanent, externally cast, item-cast, and ordinary
self-cast effects. Debuff priorities retain the VMangos spell-family and rank
exceptions, followed by aura-type, triggered-cast, and channel rules. The local
references are `SpellAuraHolder::CalculateForBuffLimit`,
`CalculateForDebuffLimit`, `IsMoreImportantVisualAuraThan`, `IsNeedVisibleSlot`,
and `Unit::RemoveAuraDueToVisibleSlotLimit` in `refs/vmangos`.

Hidden passives and pure persistent area damage do not consume visible slots.
Passive area auras distinguish their caster from recipients and totems.
Dynamic-object ticks retain the original spell's visibility when their effect
is converted into an ordinary aura application. Hurricane's secondary slow
still requires a slot, while Blizzard's plain damage does not.

Capacity decisions are pure. Accepted changes use `Aura.Transition` for stats,
periodic effects, movement control, diminishing recovery, channels, and packet
projection. Rejected incoming control effects do not consume diminishing
returns. Cast item, triggered-cast, and totem provenance are retained explicitly.
No gameplay database queries or architecture allowlist entries were added.

## Automated coverage

Tests cover stat removal, periodic tick cancellation, rejected control effects,
root cleanup and diminishing recovery, channel cancellation, refreshes,
stacking, expiry, independent capacities, hidden passives and area damage,
death, deterministic ties, and source priority. Separately tagged DBC tests
verify real class debuff priorities and Blizzard/Hurricane visibility.

## Native acceptance

An isolated GPU-rendered build-5875 client used Debugmage on Programmer Isle.
Actions used native input, `/cast`, cancellation, and the existing `.learn`
command. Tidewave probes only read state. Native Lua counted projected auras;
the default buff bar displays fewer icons than the client actually retains.

The mage reached 32 visible buffs with nine hidden passives. Mark of the Wild
rank 1 replaced Lesser Strength in slot zero. Both client and owner retained
32 visible buffs, and Strength decreased from 112 to 108 immediately. The
sampler observed the replacement at 2,555 ms. Mark of the Wild rank 1 grants
armor, so it did not replace the removed Strength bonus.

A second isolated client reconnected to the retained character. It saw Mark
of the Wild, no Lesser Strength, Strength 108, and nine hidden passives. Fury
of the Bogling expired before the reconnect observation, leaving 31 visible
buffs. Native cancellation removed the remaining visible buffs and restored
Strength 28; the nine hidden passives remained.

Local buff evidence:

- `/home/pikdum/.cache/thistle-wow-playtest.4SokUo/screenshots/`:
  `thirty-two-buffs.png` and `buff-overflow.png`.
- `/home/pikdum/.cache/thistle-wow-playtest.Uj8GXV/screenshots/`:
  `reconnect.png` and `removed-buffs.png`.
- `/tmp/thistle-aura-capacity-before-overflow.txt`,
  `/tmp/thistle-aura-overflow-samples.txt`,
  `/tmp/thistle-aura-capacity-reconnect.txt`, and
  `/tmp/thistle-aura-capacity-removal.txt`.

The mage also applied 16 real debuffs to Prairie Wolf Alpha. The final set was
Curse of Stalvan, Mirkfallon Fungus, Fevered Fatigue, Sap Might, Muculent Fever,
Festering Rash, Piercing Shadow, Maggot Slime, Ghoul Plague, Decayed Strength,
Decayed Agility, Tetanus, Spirit Decay, Curse of the Elements, Hunter's Mark,
and Faerie Fire. Detect Magic replaced Curse of Stalvan in slot 32 while the
client and owner both retained 16 debuffs. The sampler recorded the full set
at 2,324 ms and replacement at 7,481 ms; Strength rose from -52 to -47 as the
evicted penalty disappeared. God mode protected the mage during this setup;
the target retained its ordinary health and aura rules.

An earlier attempt let Faerie Fire expire before Detect Magic, so that attempt
does not establish overflow. The repeat above sampled both transitions.
Death cleared the debuffs; respawn restored 176 health, Strength 30, and no
auras. During a separate native Blizzard cast on the fresh mob, the sampler
retained hidden spell 10 with zero visible slots, observed successive
25-damage ticks, and then observed death with no remaining holders. The test
at all 16 occupied slots is automated; the final native Blizzard measurement
started with no debuffs.

Additional local evidence:

- `/home/pikdum/.cache/thistle-wow-playtest.Uj8GXV/screenshots/`:
  `debuff-overflow-verified.png`, `ground-input.png`, and
  `blizzard-hidden-active.png`.
- `/tmp/thistle-aura-debuff-overflow-verified.txt`,
  `/tmp/thistle-aura-debuff-respawn.txt`,
  `/tmp/thistle-aura-blizzard-hidden.txt`, and
  `/tmp/thistle-aura-capacity-server.log`.

WoW's own AMD DRM graphics counter advanced from 1,601,790,391 to
21,997,428,564 ns in the first session and from 5,909,046,355 to
38,520,733,619 ns in the second. Both helper-owned client units and the
retained server were stopped. No gameplay process errors appeared. Logs retain
the existing unsupported login requests and one rejected preparatory NPC buff
cast that failed its equipment requirement. Some exploratory client commands
and ground-targeting inputs were rejected before the successful native casts.

Validation: `mix test.all`, `mix compile --warnings-as-errors`,
`mix credo --strict`, `mix format --check-formatted`, and `git diff --check`.
