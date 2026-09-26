# Liquid spells and quest reward acceptance

Naxxramas slime now applies spell 28801 while a living player is submerged:
90% lower stats and 100 nature damage every two seconds. Leaving removes the
aura through the normal aura lifecycle. Repeated terrain samples preserve its
periodic deadline; an aura removed during continued exposure is applied again.
Bodies and ghosts clear the tracked spell, and login samples current terrain.
Ordinary slime has no generic damage pulse.

`Terrain.Liquid` identifies the liquid spell using the reference's quantized
submersion threshold. `Player.LiquidSpells` resolves its cached spell at the
boundary; `Logic.LiquidSpells` applies it through `SpellEffect` and removes it
through `Aura`. Movement and immutable AI context share the sampled liquid.
Reconciliation runs before periodic aura ticks so leaving cannot produce an
overdue damage tick. No architecture allowlist entries were added.

Reference: VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`src/game/Objects/Player.cpp` environmental-liquid handling and
`src/game/Maps/GridMap.cpp` liquid entry 21 and immersion classification.
The actual build-5875 spell supplies both effects; gameplay code does not
duplicate its damage or stat amounts.

## Quest reward follow-up

Preparing native attunement exposed missing generic quest reward behavior.
Completed quests now dispatch their reward spell after the inventory plan
commits. `RewSpellCast` takes precedence over `RewSpell`. Creature questgivers
cast spells that teach, create items, or explicitly target a unit; other
rewards cast from the player. Delivery uses a typed trigger request and the
entity owner.

Flag quests marked `AUTO_REWARDED` can complete without a quest-log entry.
They use the reference's level, class, race, skill, and prerequisite checks,
then the existing atomic inventory and reward path without opening a reward
dialog. Quest-completion spell effects credit the recipient. Arcane Cloaking
28006 triggers 29296, whose periodic spell 29294 credits hidden quest 9378.

Reference: `Player.cpp` `CanCompleteQuest`, `CompleteQuest`, `RewardQuest`,
and `AreaExploredOrEventHappens`; `SpellEffects.cpp` Arcane Cloaking and
quest-completion effects. Tests separately cover giver/player selection,
hidden spell precedence, recipient credit, and the real DBC and quest rows.

## Map preparation

The generated map list now includes map 533, whose internal client name is
`Stratholme Raid`. With the patched MapBuilder used for WMO metadata:

```bash
MapBuilder --data "$WOW_DIR/Data" --map 'Stratholme Raid' --output ./maps --threads 8
```

This bake generated 6,144 tiles in 70 seconds. Restart after baking.
The release MapBuilder was
`/nix/store/68rxhgrvmbhaf19h4vjv00617hpvz1xh-namigator-mapbuilder-pikdum-185394d/bin/MapBuilder`.
Compilation and runtime used
`NAMIGATOR_SRC=/nix/store/3nds85i5fyjgpqcgjnk03fdfgs798vfn-namigator-with-wmo-metadata`;
the inherited shell variable still named an older unpatched source.

## Native acceptance

Build-5875 GPU clients ran against fresh source `f3715e69`, including liquid
commit `fd2c4909`. Debughunter (GUID 7) was raised to level 60 and exalted
with Argent Dawn through native developer commands. Debugbuyer (GUID 10)
accepted the invitation and the group converted to a raid through the client.
All mutations used native client input; Tidewave probes were read-only.

- At Archmage Angela Dosantos, native Accept and Complete Quest clicks
  completed free exalted attunement 9123. The client displayed Arcane Cloaking
  and quest completion. A sampler recorded rewarded quests changing from
  empty to `[9123]`, aura 29296 appearing, then `[9123, 9378]`.
  `attunement-reward-cast.png` records the visible cast.
- From `3124 -3730.29 138.66` on map 0, forward movement entered actual
  area trigger 4055. The server admitted the player to map 533, instance 1,
  owned by party 1. `.instance info` and the character sheet are visible in
  `naxx-dry-baseline.png`. The portal sampler ended before movement, so the
  admission claim rests on native input, packet logs, and the resulting
  authoritative world, not that sampler.
- Initial exposure at `3100 -3125 293.5` applied the slime aura and its first
  100-point tick. Nearby Sludge Belchers also attacked and killed the player.
  Death removed the aura and restored stats; the following maintenance pass
  cleared liquid ownership. This run is not evidence for isolated tick damage.
  Release Spirit and actual portal reentry resurrected the player in the
  same instance.
- A quieter pool at `3510 -3330 264.4` settled at z=264.279816, below
  surface 264.811340. Combat stayed false throughout the recorded run.
  Strength changed 95 to 9, Stamina 165 to 16, and maximum health 2937 to
  1483. Four ticks lowered health 1483, 1383, 1283, 1183, 1083, at roughly
  two-second intervals. The holder kept one application timestamp and
  advanced each deadline by exactly 2000 ms. `clean-slime-stats.png` shows
  the red stats, debuff, and 100-point damage feedback.
- Returning to `3005.87 -3435.01 293.882` in the same copy removed the aura
  and ownership marker. Strength, Stamina, and maximum health returned to
  95, 165, and 2937. Health initially remained 1083, then normal regeneration
  resumed; no further slime damage occurred. See `dry-stats-restored.png`.
- Reentering the quiet pool and logging out retained the liquid marker and
  aura in `CharacterStore`, while removing the live entity, metadata, and
  projected position. God mode protected this 20-second logout and reconnect
  interval. Login returned to instance 1 at the same position with exactly
  one slime holder, Strength 9, Stamina 16, maximum health 1483, and both
  attunement quests still rewarded. Metadata also projected the aura.
- Disabling god mode after reconnect produced three further 100-point ticks
  with combat still false. Departure again cleared the spell and restored
  stats. `reconnected-slime-damage.png` shows the active debuff and character
  sheet after damage protection was disabled. Native ghost exposure was not
  tested; the deterministic lifecycle test covers ghost exclusion.

The first attunement click was rejected because the character stood 5.010
yards away; moving within range resolved it. A later click selected nearby
Huntsman Leopold and accepted quest 9124; it did not contribute to attunement.
An attempted `InteractUnit` Lua call was unavailable in vanilla. Actual
acceptance used NPC model clicks and verified dialog titles.

## Runtime and cleanup

Both clients used isolated GPU sessions. The primary WoW process, PID 1803116,
held AMD DRM client 5423; its graphics counter advanced from 735,171,693 ns to
42,357,642,260 ns. Duplicate descriptors for that DRM client were counted once.
This verifies the game process rendered on the GPU, separately from Gamescope.

The helpers stopped units `thistle-wow-playtest.tEjOqy.service` and
`thistle-wow-playtest.B3hsIn.service` using recorded invocation IDs
`66341aa3fd334e8b9263d7c5b6c2df8d` and `4f957cb2b35e4cb883c128b1725eeb2a`.
Both units were inactive afterward. Neither player remained in the entity
registry, metadata, or spatial projection; instance 1 had no players.
The retained server PTY exited and ports 4000, 3724, and 8085 were free.
Logs and screenshots were retained.

The server log had no errors. Existing unsupported account-data, ticket, and
meeting-stone requests remained; no quest, liquid, or instance-path warning
appeared. Exploratory Tidewave expressions with an incorrect function
signature or state shape were corrected; they were read-only diagnostics.

## Automated checks

- `mix test.all`: 6,714 tests, zero failures.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2,430 source files.
- Formatting and pre-commit checks passed for both implementation commits.

Coverage includes liquid thresholds, unchanged periodic deadlines, aura
replacement and reapplication, unrelated aura preservation, bodies and ghosts,
resurrection, departure before an overdue tick, stationary death, actual spell
data, and generated Naxxramas geometry. DBC, VMangos, and map tests use separate
integration tags. Native acceptance does not claim a dispel test or additional
raid copies.

## Retained evidence

Primary client: `/home/pikdum/.cache/thistle-wow-playtest.tEjOqy`.
Secondary client: `/home/pikdum/.cache/thistle-wow-playtest.B3hsIn`.
Screenshots named above are under the primary session's `screenshots/`.

- `/tmp/thistle-liquid-spells-server.log`
- `/tmp/thistle-liquid-spells-map-build.log`
- `/tmp/thistle-liquid-spells-map-probe.log`
- `/tmp/thistle-liquid-spells-quest-reward-trace.txt`
- `/tmp/thistle-liquid-spells-dry-baseline.txt`
- `/tmp/thistle-liquid-spells-entry-exit-trace.txt`
- `/tmp/thistle-liquid-spells-clean-entry-exit.txt`
- `/tmp/thistle-liquid-spells-logout.txt`
- `/tmp/thistle-liquid-spells-reconnected.txt`
- `/tmp/thistle-liquid-spells-reconnect-damage.txt`
- `/tmp/thistle-liquid-spells-cleanup.txt`
- `/tmp/thistle-liquid-spells-gpu-start.txt`
- `/tmp/thistle-liquid-spells-gpu-end.txt`
- `/tmp/thistle-liquid-spells-tests-final.log`
- `/tmp/thistle-liquid-spells-credo-final.log`
- `/tmp/thistle-quest-rewards-compile.log`
