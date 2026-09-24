# Creature entry transitions

## Implementation

`c14eed7b` implements script command 27, `UPDATE_ENTRY`, through a pure
`CreatureEntry` transition. A creature changes its template without replacing
its GUID, process, spawn incarnation, position, threat, victim, or tap. Health
and mana retain their previous percentages. Model, scale, geometry, canonical
stats, faction, flags, equipment, spell list, and loot use the new definition.
Existing auras are recomputed against the new inputs; template addon auras are
replaced, while spawn addon overrides remain. Respawn restores the original
definition through the existing lifecycle.

Archetypes are loaded into an ETS cache at boot. Behavior-tree contexts receive
the definitions needed by their scripts, including weighted level and display
choices. Scripts execute the transition synchronously, so subsequent commands
see the changed creature. Existing EventAI and phase state remain intact.
Equipment reset uses the current template. Metadata publishes current entry
and appearance through the owning mob boundary. Entry-sensitive quest, gossip,
vendor, training, condition, loot, and script consumers use current identity
instead of assuming that the entry encoded in a stable GUID is still current.

`fd2c8f82` fixes a bug discovered during native acceptance: incoming EventAI
spell-hit callbacks were restricted to spells that start combat. They now run
after successful spell reception, including neutral quest spells. Resisted,
immune, and reflected outcomes do not invoke the callback. The regression tests
exercise a noncombat dummy spell and a resisted spell.

References:

- `refs/vmangos/src/game/Maps/ScriptCommands.cpp`: `ScriptCommand_UpdateEntry`.
- `refs/vmangos/src/game/Objects/Creature.cpp`: `InitEntry`, `UpdateEntry`, and
  temporary-faction restoration.
- `refs/vmangos/src/game/Spells/Spell.cpp`: successful-hit gating and the
  post-effect `AI()->SpellHit` callback.
- Generated VMangos EventAI 535701: spell 23359 changes Land Walker 5357 into
  Zapped Land Walker 14604. Item 18904 casts that spell. Quest 7003 needs item
  18956, Miniaturization Residue, from the changed creature's loot table.

## Automated validation

All source checks passed on `fd2c8f82` before the final native server launched:

- `mix test.all`: 5,411 passed, including DBC, VMangos, and map integration.
- `mix compile --warnings-as-errors`.
- `mix credo --strict`: zero issues.
- `mix format --check-formatted`, `git diff --check`, and commit hooks.

Coverage includes resource ratios, retained engagement and casting state,
derived aura effects, addon ownership, dead creatures, repeated transformations,
faction restoration, current equipment, same-batch script ordering, immutable
perception, weighted choices, cached boundary dispatch, client update fields,
metadata publication, and respawn. No architecture allowlist was expanded.

Logs are `/tmp/thistle-entry-tests-final.log`,
`/tmp/thistle-entry-compile-final.log`, and `/tmp/thistle-entry-credo-final.log`.
No source changed during the final native run.

## Native acceptance

A fresh server on `fd2c8f82` used genuine build-5875 clients on Programmer Isle.
Debugmage (5, level 60) performed the actions; Debugwarrior (1) observed.
Developer commands supplied the item, quest, position, level, and god mode.
Native item use, spell casts, targeting, and loot interaction drove gameplay;
Tidewave probes were read-only. The seeded Land Walker uses low GUID 991400
and a 30-second respawn.

- Native Frostbolt damaged and tapped the original Land Walker. Ultra-Shrinker
  use sent `CMSG_USE_ITEM` and spell 23359. Both clients displayed the smaller
  creature and the name Zapped Land Walker.
- A 50 ms sampler observed entry 5357 become 14604 in the same owner
  `#PID<0.2373.0>`, GUID 17379391051899281576, and incarnation 20. Health changed
  from 6034/6414 to 2514/2673, preserving the fraction with integer truncation.
  Tap player 5, victim 5, combat state, and threat 380 remained intact. Model
  changed from 10037 to 14675, scale from approximately 1.45 to 1.0, spell list
  from 53570 to 146040, and loot ID from 5357 to 14604.
- Native combat killed the transformed creature. Its corpse session contained
  quest item 18956 and retained the correct tap. The native loot window later
  displayed Miniaturization Residue by name.
- Automatic respawn restored entry 5357, model 10037, health 6414/6414,
  original scale, spell list 53570, and loot 5357. Threat, victim, and tap were
  cleared, and the incarnation advanced. The same process remained alive.
- A second Ultra-Shrinker use worked after respawn without starting combat or
  creating a tap. The observer left visibility range and returned, then could
  target Zapped Land Walker. Further transformations and deaths restored the
  original creature each time. The final read showed incarnation 225, full
  original health, no original-template snapshot, and no loot session.

The initial run left native inventory collection unverified. Early attempts missed the
short corpse window. Later attempts opened a populated loot window within that
window, but native `LootSlot`, button calls, and coordinate clicks produced no
observed `CMSG_AUTOSTORE_LOOT_ITEM` or inventory change. A client diagnostic
reported three loot slots, the server session included the Mage as a viewer,
and the backpack had empty slots. Work was paused at the user's request after
recording this evidence. The follow-up below resolves collection and quest-item
progress through native loot-window clicks.

The final server log has no error-level entries, owner crashes, unsupported
script commands, or spell-validation failures. Existing unimplemented account
data, ticket, and meeting-stone requests remain outside this change.

## Evidence and cleanup

- Owner session: `/home/pikdum/.cache/thistle-wow-playtest.ciLEB1`.
- Observer session: `/home/pikdum/.cache/thistle-wow-playtest.aVZuKb`.
- Screenshots: owner `baseline`, `shrunk`, `dead`, `loot-diagnostic`, and
  `loot-buttons`; observer `observer-shrunk` and `observer-reentered`.
- Server log: `/tmp/thistle-entry-server-final.log`.
- Runtime evidence: `/tmp/thistle-entry-transform-final.txt`,
  `/tmp/thistle-entry-respawn-final.txt`, `/tmp/thistle-entry-corpse-final.txt`,
  `/tmp/thistle-entry-second-final.txt`, `/tmp/thistle-entry-loot-diagnostic.txt`,
  and `/tmp/thistle-entry-cleanup-final.txt`.

Both WoW processes used AMDGPU device `0000:0c:00.0`. The owner's graphics
counter advanced from 1,661,733,648 to 34,346,749,990 ns; the observer's advanced
from 1,231,711,566 to 27,476,700,453 ns. Counter samples are retained in
`/tmp/thistle-entry-{owner,observer}-gpu-{start,end}.txt`.

Both final clients and the two preliminary clients were stopped through their
owned helper services. The retained server PTY exited. Artifacts remain local;
nothing was pushed.

## Collection follow-up, September 24

The first follow-up reproduced the populated loot window on a Zapped Cliff
Giant. A coordinate click on Miniaturization Residue sent
`CMSG_AUTOSTORE_LOOT_ITEM` and collected the item. The native client displayed
the loot message and, after relogging, reported quest progress `1/15`.
The earlier Lua attempts did not establish a server loot-transfer failure.

Two setup defects were fixed during this check:

- `8331070b` rejects incomplete teleport coordinates, trailing numeric junk,
  and negative map IDs. An incomplete `.go xyz` command previously crashed
  the player owner. Regression tests cover malformed input, explicit maps,
  and preservation of the current instance copy.
- `75d76943` clears alternate creature-template IDs in developer seed rows.
  The requested Land Walker previously inherited its source spawn's random
  alternatives and could become a Cliff Giant. Playground spawns now keep
  their requested entry.

A fresh server on `75d76943` repeated the complete collection path with
Debugmage (5) and the intended Land Walker:

- The seed published entry 5357, name Land Walker, and GUID
  `17379391051899281576`. Malformed native `.go xyz 1 2` and
  `.go xyz 1 2 3 nope` commands left the same player owner alive.
- Native Ultra-Shrinker use changed the creature into Zapped Land Walker
  14604. Native Frostbolt casts killed it, and right-clicking the corpse
  opened loot containing one Miniaturization Residue and 60 copper.
- Clicking the two loot slots collected both rewards. The client displayed
  the item receipt, `Miniaturization Residue: 1/15`, and the copper receipt.
  The player owner and `CharacterStore` each retained one item 18956;
  coinage increased from 100,000,000 to 100,000,060.
- Respawn restored entry 5357 and health 6414/6414, cleared the creature's
  loot session, and the player's loot GUID was nil after collection.
- Logout removed the player owner while the store retained the item and
  copper. Relogging created a new owner with both rewards intact.

Final source gates passed: `mix test.all` (5,413 tests),
`mix compile --warnings-as-errors`, `mix credo --strict`, formatting,
diff checks, and commit hooks. No source changed after those gates.

Evidence is in `/tmp/thistle-loot-{seed,shrunk,corpse,collected}-final.txt`,
`/tmp/thistle-loot-server-final.log`, and the `shrunk`, `loot-open`,
`collected`, and `quest-progress` screenshots in
`/home/pikdum/.cache/thistle-wow-playtest.fl8knq/`. The preliminary session
is `/home/pikdum/.cache/thistle-wow-playtest.GeeOi3/`; its `retained-progress`
screenshot records the Cliff Giant collection after relogging.

The final server log contains no error-level entries or spell-validation
failures. WoW's own AMDGPU graphics counter on `0000:0c:00.0` advanced from
3,345,359,465 to 7,856,360,388 ns; samples are in
`/tmp/thistle-loot-final-gpu-{start,end}.txt`. Both helper-owned clients and
both retained server PTYs were stopped, with artifacts retained. Nothing
was pushed.
