# Autonomous guardian summons

Implemented in `e1fb9ffc`, with creature stat derivation corrected in
`43a79806` and combat metadata cleanup fixed in `47b4694d`. Automated and native
acceptance completed on 2026-09-22.

## Behavior and reference

Spell effect 42 now creates autonomous guardians through a typed owner-local
request. Player and creature owners retain a collection of independent guardian
identities alongside their normal combat companion and noncombat critter.
Direct player casts toggle matching entries, or replace them when the spell has
both a category and duration. Triggered casts accumulate; creature casters honor
the reference's per-entry cap. The owner monitors each actor and removes only
its matching identity when it stops.

Guardians use creature class-level statistics, template multipliers, owner
faction and PvP flags, creation auras, and the existing combat/following tree.
They have pet GUIDs and guardian ownership labels without a pet action bar.
Engineering trinkets scale their creatures from effective Engineering skill / 5;
NPC casts support level offsets. Dragonling and Battle Chicken wrapper spells
retain their cast item through the triggered summon.

Creature resource derivation applies Stamina/Intellect changes relative to the
base creature stats, while armor includes Agility. These inputs participate in
the shared pure recompute path. Aura removal and repeated recomputation do not
capture or restore stale derived values.

Aggressive acquisition checks hostility and line of sight, including nearby
players. Guardians defend their owner and may finish combat after its death.
Duration, missing/distant owners, world transfers, and logout remove them;
guardian corpses remain for up to 15 seconds and do not generate ordinary
creature loot.

Reference: `refs/vmangos` at `8f4e60845`, particularly
`Spell::EffectSummonGuardian`, engineering dummy effects in `SpellEffects.cpp`,
`Pet::InitStatsForLevel`, `Pet::Update`, and creature/pet calculations in
`StatSystem.cpp`.

The raw DBC contains 211 guardian-effect occurrences. VMangos converts 13 of
these to wild summons, including all three Target Dummies. Those retain the
wild-summon distinction and are now covered by the separate
[wild summon system](wild-summon-playtest.md).
Individual summon scripts, such as Arcanite Dragonling spell timers and Battle
Chicken behavior, remain separate content work.

## Automated acceptance

`mix test.all` passed **4,673 tests**. `mix compile --warnings-as-errors` passed,
and `mix credo --strict` found zero issues across 1,828 source files. The
architecture ratchet passed without an allowlist change.

Regressions cover DBC semantics and caster execution, actual item wrapper
contexts, multiple guardians, direct/triggered recasts, stale monitor messages,
NPC ownership and supervisor-safe termination, duration and worldport cleanup,
Engineering level scaling, NPC level bounds, hostile acquisition, owner lifetime,
corpse preservation, creature stat recomputation, late combat delivery, and
concurrent metadata updates. DBC tests use `:dbc_db`;
actor tests use cached synthetic templates.

## Native client acceptance

Three fresh local servers and isolated build-5875 clients used Debugwarlock.
Existing development commands supplied levels, skills, spells, items, travel,
and the final lethal owner transition. Summoning, item use, targeting, walking,
buffs, and logout used native client actions. Tidewave probes only read state.

- Mechanical Dragonling item 4396, at Engineering 300, summoned a visible
  level-60 guardian (entry 2678). It followed a roughly 21-yard walk and retained
  the same Imp GUID and pet bar alongside a Mechanical Squirrel.
- Its one-minute duration ended with no actor, world position, metadata, or owner
  monitor remaining. The Imp and squirrel remained active.
- Mithril Mechanical Dragonling item 10576 independently acquired and killed a
  Defias Bandit with the Imp passive. The victim had 0/156 health, named the
  guardian as its killer, and assigned its loot to player GUID 6.
- Spiked Collar and Glowing Cat Figurine summoned a level-30 Felhunter and a
  level-19 Ghost Saber simultaneously while the Imp remained active. Both
  guardians entered combat autonomously. A later idle owner death cleared both
  identities and monitors.
- On the corrected stat implementation, a Guardian Felhunter retained its GUID
  while native Power Word: Fortitude changed Stamina 115 -> 118 and maximum
  health 1,003 -> 1,033. Arcane Intellect changed Intellect 32 -> 34 and maximum
  mana 0 -> 30. Both aura icons appeared in the target frame. Armor was 1,212,
  equal to template armor 1,160 plus Agility 52.
- Reusing Spiked Collar dismissed its matching guardian. A new Felhunter and
  Ghost Saber then coexisted on the corrected implementation. Traveling from
  Goldshire to Programmer Isle removed both actors, positions, metadata rows,
  owner identities, and monitors.
- Logout removed an active guardian and reconnect did not restore it. Inspecting
  the old GUID exposed a late attacker-count decrement recreating a metadata row
  after actor shutdown. The follow-up makes counter changes conditional on an
  existing row and uses atomic compare-and-replace updates, including owner
  metadata merges, so concurrent changes are preserved.
- The fresh cleanup repeat began with guardian `17383894740432322594` in combat
  and `attacker_count: 1`. After native logout, the owner was offline and that
  guardian had no actor, world position, or metadata row. The late zero-counter
  row did not return.

## Retained evidence

- Client sessions: `/home/pikdum/.cache/thistle-wow-playtest.b4Rka0`,
  `/home/pikdum/.cache/thistle-wow-playtest.IuGCjr`, and
  `/home/pikdum/.cache/thistle-wow-playtest.0u2ENc`.
- Screenshots include `trinket.png`, `combat-after.png`,
  `guardian-pair2.png`, `stats-buffed.png`, `worldport-after.png`, `logged-out.png`,
  and `reconnected.png` in their respective sessions.
- Authoritative reads and test/server logs are retained under
  `/tmp/thistle-guardian-*`. The combat sampler timed out; the kill result uses
  the separate victim snapshot, including the actual killer GUID and loot tap.

No owner, network, or AI crash was found in the acceptance runs. All temporary
servers, WoW clients, and private X servers were stopped afterward. Nothing was
pushed or deployed.
