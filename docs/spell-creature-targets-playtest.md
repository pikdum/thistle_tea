# Database-selected creature spell targets

Implemented and accepted on 2026-09-27 in `ee139ddf`.

## Shared behavior

DBC target 38 now resolves a nearby creature using preloaded `spell_script_target`
rows. Selectors retain entry, living/corpse state, conditions, and inverse effect
masks. An eligible selected creature takes precedence; otherwise the resolver
chooses the nearest eligible creature in the caster's current world copy, with
GUID ordering for equal distances. Effect radius falls back to spell range and
uses the caster's radius modifiers. Nearby selection accounts for combat reach.
Missing owners, removed corpses, different copies, and out-of-range candidates
cannot satisfy the requirement.

Player admission checks the requirement before casting. The shared launch path
checks it again before paying costs. Each effect keeps its own recipients through
cast resolution and delivery, including triggered spells. A mixed spell can heal
different creatures and its caster without applying every heal to every target.
Item casts retain the selected creature in their launch target and cast context.
Scripted corpse effects can run when their matching selector requires a corpse;
ordinary damage, healing, and auras remain excluded from dead recipients.

Conditions use the existing pure condition evaluator and cached metadata. Spatial
conditions use the existing world condition boundary. Unsupported conditions fail
closed. Conditions also apply to explicitly supplied targets, rather than allowing
an explicit selection to bypass a required health threshold.

Database `script_effect` spells now enter the existing script runner at the
original caster, preserving the receiving unit as the script target. This reuses
script delays, routing, world guards, and inventory delivery. Empty Phial exposed
this missing path: VMangos overrides its DBC create-item effect with a script
effect and supplies a `create_item` command in `spell_scripts`.

This milestone covers nearest-creature target 38 for unit casts and triggered
spells. [Scripted areas and configured cones](spell-scripted-areas-playtest.md)
subsequently added modes 7, 8, and 60, followed by
[scripted destinations](spell-scripted-locations-playtest.md) for target 46.
These milestones do not claim all database-scripted content is implemented.

## Native acceptance

Fresh local server, genuine build-5875 client, Debugmage GUID 5, Programmer Isle
map 451. `dev_seed.ex` places Irradiated Invader 6213 and Irradiated Pillager 6329
near `{16523.2, 16218.1, 69.4442}` and `{16533.2, 16218.1, 69.4442}`.

Used Empty Leaden Collection Phial 9283 through the client's inventory API, which
sent `CMSG_USE_ITEM` and cast Empty Phial 11513. Both the empty and full phials are
unique items. The first reward was deleted through the client before repeating
against corpses.

| Action | Client result | Authoritative result |
| --- | --- | --- |
| Use at the island's starting point, with no eligible nearby creature | Cast rejected | Empty 1, full 0; no active cast |
| Move to `{16521.2, 16218.1, 69.44}`, clear selection, use beside living creatures | “You create: [Full Leaden Collection Phial]” | Empty 0, full 1 |
| Kill both eligible creatures with native Death Touch casts, add a fresh empty phial, clear selection and use again | A second full phial is created beside the visible corpses | Both creature metadata rows report dead; empty 0, full 1 |
| Add an empty phial, return to the starting point, use again | “Invalid target” | Empty 1, full 1; no active cast, channel, or script run |
| Log out and reconnect | Character returns with inventory intact | Empty 1, full 1; cast nil, channel fields nil, script runs empty |

God mode was enabled for the corpse setup after the living use; it was not needed
for target selection or inventory cost checks. The living attempt consumed its
empty item before god mode was enabled. The corpse attempt also consumed exactly
one empty item.

Normal logout removed the player's entity owner, metadata, and world position.
The server recorded the two expected `bad_targets` rejections and no runtime
errors during acceptance.

## Automated coverage

`mix test.all`: **6,880 passed** in 65.8 seconds. Compilation with warnings as
errors and strict Credo both passed. The architecture ratchet remains unchanged.

The new tests exercise explicit-target preference, fallback from a wrong entry,
life states, inverse masks, health and level conditions, unsupported-condition
rejection, copy/height/owner/corpse removal, radius and combat reach, launch-time
failure without costs, actual per-recipient healing, triggered delivery, original
caster routing, corpse scripts, item target projection, and database-script
handoff. Separate VMangos and DBC tests verify cached selectors and the real
phial override without mixing database tags.

## References and evidence

Reference checkout: `refs/vmangos`, commit
`8f4e608450460efe1e38743e4da74397d4773a3a`:

- `Spell.cpp`, `CheckScriptTargeting` and `SetTargetMap`.
- `GridNotifiers.h`, `NearestUnitFitConditionInCombatRangeCheck`.
- `SpellEffects.cpp`, `EffectScriptEffect` database-script fallback.
- Current generated `spell_script_target`, `spell_effect_mod`, and `spell_scripts`
  rows for 11513, plus corpse-only Symbol of Life selectors and health-threshold
  Dominion of Soul selectors.

Native session: `/home/pikdum/.cache/thistle-wow-playtest.MlfYbj`, GPU renderer,
owned unit `thistle-wow-playtest.MlfYbj.service`, invocation
`da8fa78579ff48e5bd47b0fcc3bc38f7`. WoW PID 2052917 was in that cgroup; its own
DRM graphics counter advanced from 1.468 to 3.379 billion nanoseconds.

Screenshots include `living-phial.png`, `corpse-ready.png`, `corpse-phial.png`, and
`out-of-range-retry.png`. Logs and gate results are retained under
`/tmp/thistle-unit-targets-*`.

The helper stopped the owned client unit; it is inactive with an empty cgroup and
WoW PID 2052917 is gone. The server PTY was stopped after a final check confirmed
the player owner, metadata, and position were absent. No push was performed.
