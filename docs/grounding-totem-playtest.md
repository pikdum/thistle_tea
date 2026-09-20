# Grounding Totem and spell magnets

Aura 96 now redirects eligible hostile spells to its source. Grounding Totem
uses this shared system: its passive spell 8179 immediately triggers the
20-yard protection aura 8178, then refreshes it every ten seconds. One source
charge protects all recipients, so simultaneous attacks against different
party members cannot each spend the same charge.

Eligibility follows `SpellCaster::SelectMagnetTarget` in
`refs/vmangos/src/game/Objects/SpellCaster.cpp`: magic damage class or visual
7250, excluding poisons, abilities, `NO_REDIRECTION`, and
`SUPPRESS_TARGET_PROCS`. Area spells, beneficial spells, and passive spells
do not redirect. An intercepted chain stops at the magnet. Grounding's
passive bypasses creature-type restrictions, allowing it to catch Polymorph.
Totem debuff and regeneration immunity follows `Totem::IsImmuneToSpellEffect`
in `refs/vmangos/src/game/Objects/Totem.cpp`; harmful direct damage still lands.

Pure aura transitions publish typed effects through the owning event context.
`World.SpellMagnets` serializes charge claims using registered aura snapshots,
world positions, and metadata, without calling entity processes or querying
the database. Process monitors retire departed owners. Source death, expiry,
removal, distance, and instance boundaries invalidate protection. Replaying
an existing source snapshot cannot refill a spent charge; a new periodic
application can. Launch target descriptors, hit GUIDs, and effect delivery
all use the redirected target, while caster-local effects remain local.

## Bugs fixed during acceptance

- Passive totems no longer repeatedly recast a consumed or dispelled aura.
  VMangos's immediate first pulse is retained for the supported passive
  periodic totems; subsequent pulses retain their configured interval.
- A departed magnet source now fails eligibility normally instead of logging
  an error from a boolean expression receiving `nil`.
- Destroyed totems stop without normal creature loot, corpse, or respawn
  handling, and notify the owner to clear only the matching slot.
- Totems use temporary supervisor children. Live testing exposed the previous
  default restart policy resurrecting a killed totem from its original state.
  A supervised-process regression now covers normal termination.

## Real-client acceptance

Two isolated build-5875 clients controlled level-50 Debugshaman (GUID 8) and
Debugmage (GUID 5) on Programmer Isle, with god mode disabled. Client commands
performed setup, duels, casts, replacement, and death. Read-only owner samples
and event tracing recorded launch targets, damage, auras, health, and cleanup.
The accepted server included the supervisor fix.

- Fireball 10149 launched at Grounding Totem GUID 17379391061431943199 and
  dealt 511 damage to it. The Shaman remained at 2,415 health. Protection
  disappeared, the totem went offline, and the owner's slot became empty.
  It remained offline through the sample. A second Fireball targeted GUID 8,
  dealt 411 direct damage, and applied its periodic damage normally.
- Polymorph 12825 launched at replacement totem 17379391061431943203.
  Neither the Shaman nor the totem acquired Polymorph; the totem retained
  70 health. Protection was consumed, then returned on the next ten-second
  pulse. The Shaman remained visibly in normal form.
- Rank-one Frost Nova 122 bypassed protection. It dealt 23 damage to both
  the Shaman and totem, and rooted the Shaman. The totem retained 47 health,
  rejected the root, and both recipients retained aura 8178.
- Windfury Totem replaced Grounding in air slot four. The old source went
  offline, the new GUID remained in the slot, and the old protection faded
  on the existing area-aura reconciliation tick. The source monitor already
  prevented interception during that brief visual fade interval.
- With a fresh Grounding Totem, `.die` set the Shaman's health to zero,
  cleared the slot and protection, and stopped the totem. The client showed
  the death prompt; later samples showed no restart or restored protection.

Automated coverage additionally verifies concurrent recipients, stale snapshot
publication, source-process exit, radius and instance isolation, expiry,
removal, mixed caster/target effects, bypass attributes, chain stopping,
totem regeneration exceptions, and logout cleanup. Multi-client party
interception is covered by deterministic concurrent tests, not this duel run.

The accepted server logged no errors. Login retained the existing unsupported
account-data, raid-info, GM-ticket, time-query, and meeting-stone warnings.
Exploratory runs before the fixes are not acceptance evidence. Both clients
and the server were stopped before final validation.

## Evidence

- Server: `/tmp/thistle-grounding-accepted-server.log`.
- Read-only traces: `/tmp/thistle-grounding-accepted-fireball.txt`,
  `-polymorph.txt`, `-area.txt`, `-replacement.txt`, and `-death.txt`, each
  using the same `/tmp/thistle-grounding-accepted` prefix.
- Shaman screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.RvY0du/screenshots/`, including
  `grounded-polymorph.png`, `replacement-windfury.png`, and `owner-death.png`.
- Mage screenshot:
  `/home/pikdum/.cache/thistle-wow-playtest.0KVe7E/screenshots/interception.png`.

## Final validation

- `mix test.all`: 3,556 passed, including DBC, VMangos, and map integration.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Logs: `/tmp/thistle-grounding-final-{tests,compile,credo}.log`.
