# Combat-depleting trinket buffs

Implementation commits: `c55daae2`, `893f07fd`, and `85196198`.
Reference: local VMangos revision `8f4e608450460efe1e38743e4da74397d4773a3a`,
including `UnitAuraProcHandler.cpp`, `Spells/SpellAuras.cpp`,
`Spells/SpellEffects.cpp`, `scripts/spells/spell_item.cpp`, and `StatSystem.cpp`.

## Behavior

| Item | Initial bonus | Consumption | Duration |
| --- | --- | --- | --- |
| Zandalarian Hero Medallion (19949) | Restless Strength: 20 stacks, +40 physical damage | One stack per qualifying outgoing melee/ranged hit | 20 seconds |
| Zandalarian Hero Badge (19948) | Brittle Armor: 10 stacks, +2000 armor and +30 defense | One stack per qualifying incoming melee/ranged hit | 20 seconds |
| Petrified Scarab (21685) | Mercurial Shield: 10 stacks, +100 fire, nature, frost, shadow, and arcane resistance | One stack per qualifying incoming harmful spell hit | 60 seconds |

The shared aura transition owns depletion, derived stats, client stack fields,
and removal. The DBC proc flags and cached VMangos dummy scripts select the
appropriate triggers. Source replacement replenishes the bonus; source expiry,
cancellation, and death clean dependent holders. A late bonus delivery requires
a live matching source. Exhaustion removes the bonus without recreating it on
subsequent hits.

Two shared bugs were fixed during this work. Skill bonuses now multiply by
holder stacks, including both temporary and permanent modifiers. Physical flat
damage bonuses now appear in canonical player weapon ranges and are counted
once by melee combat. Spell snapshots retain their canonical base damage;
empty offhand/ranged slots remain empty, and creatures retain attack-school
resolution.

## Automated validation

- `mix test.all`: **6544 passed**, 57.7 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2389 files.
- Formatting and commit hooks passed.

Tests cover initial stacks, melee/ranged feedback, avoided attacks, full blocks,
partial blocks, harmful spell versus periodic feedback, zero-damage debuffs,
exhaustion, replenishment, original deadlines, death, removal causes, late
delivery, signed skill encoding, displayed damage, idempotent recomputation,
empty weapon slots, and unchanged Deep Wounds damage. Separate DBC and VMangos
tests verify the real spell chains, self-targeted removal, and script mappings.
Database tags remain mutually exclusive.

## Native acceptance

Build-5875 GPU clients used level-60 Debugbidder (GUID 11, mage) and Debugrival
(GUID 12, warrior) on map 451 at `{16307, 16300, 69.44}` and
`{16309, 16300, 69.44}`. Both were PvP flagged with godmode off. Item acquisition,
equipment, activation, attacks, and logout used native input and existing
development commands. Tidewave expressions only inspected gameplay state.

The initial melee run showed Restless Strength at 20 stacks and +40 damage,
then 19/+38, 18/+36, and 17/+34 on landed attacks. Brittle Armor began at 7113
armor and 280 learned defense, then fell to 6913/277, 6713/274, and 6513/271.
Its baseline was 5113 armor and 250 learned defense; PvP defense uses the
level-based maximum of 300 before bonuses. Both bonuses expired and baseline
stats returned. The character panel exposed the missing physical damage
projection, which was fixed before the final native run.

The final run on `85196198` displayed **150–205** damage at twenty stacks,
compared with **110–165** before activation. Complete owner sampling recorded
20 through 13 Restless Strength stacks, with both displayed and combat minimum
damage falling from 150.14 to 136.14. Brittle Armor fell from ten stacks to
three, with armor from 7113 to 5713 and PvP defense from 330 to 309. Both
bonuses disappeared after 20 seconds: minimum damage returned to 110.14,
armor to 5113, and PvP defense to 300. A later attack did not recreate them.
`ClearTarget()` stopped melee combat.

Three native rank-one Fireballs reduced Mercurial Shield from ten stacks to
seven and fire resistance from 100 to 70. Periodic Fireball ticks dealt damage
without consuming further stacks. The client displayed 80 resistance at the
intermediate eight-stack state. Holy resistance remained zero. After expiry,
the source, bonus, and extra resistances were absent. Logout removed both
players from entity registration, world position, and metadata.

The final Mercurial Shield run also showed the client at seven stacks and 70
resistance. The owner retained stack counts 10, 9, 8, and 7 with application
bytes 9, 8, 7, and 6. Right-click cancellation removed the bonus and returned
resistance to zero while the hidden source remained active. A fourth native
Fireball did not restore the cancelled bonus. The source subsequently expired.

Both players reconnected with the same equipped item GUIDs and no expired
bonuses. A further Scarab use followed by immediate cancellation and native
logout tested a live source across reconnect. After login, the source had
28.32 seconds remaining and the item cooldown had 148.32 seconds remaining.
The cancelled child remained absent and resistance stayed zero. The source
then expired on its original deadline without restoring the bonus. Item GUID
`4611686018427388166` remained equipped throughout.

WoW's own amdgpu graphics counters increased from 4,290,546,695 to
37,435,972,652 ns for PID 1570834 and from 3,844,326,220 to 37,222,479,610 ns
for PID 1571610. Duplicate descriptors were not summed. The initial server
logged one rescued mob AI tick error while Tidewave recompiled the edited
Combat module. Final acceptance used a fresh server after compilation and
reported no owner errors or spell-validation failures. Existing unsupported
account-data, GM-ticket, and meeting-stone login requests remained.

Final logout removed both players from entity registration, world position,
and metadata. Both helper-owned services were verified inactive, both WoW
processes were gone, and the retained server exited. Logs and screenshots were
retained. Nothing was pushed.

## Evidence

- Mage session: `/home/pikdum/.cache/thistle-wow-playtest.GDCdVZ`.
- Warrior session: `/home/pikdum/.cache/thistle-wow-playtest.FSq35Q`.
- Initial server: `/tmp/thistle-depleting-server.log`.
- Final server: `/tmp/thistle-depleting-final-server.log`.
- Initial melee samples: `/tmp/thistle-depleting-melee-samples.txt` (the diagnostic
  tool truncated this first result; subsequent probes verified expiry).
- Fireball samples: `/tmp/thistle-depleting-shield-samples.txt`.
- Final spell and cancellation samples:
  `/tmp/thistle-depleting-final-shield-samples.txt`.
- Reconnect and source deadline: `/tmp/thistle-depleting-reconnect-samples.txt`,
  `/tmp/thistle-depleting-reconnect.txt`, and
  `/tmp/thistle-depleting-cooldown-reconnect.txt`.
- Saved equipment and absent owners: `/tmp/thistle-depleting-final-logout.txt`.
- GPU counters: `/tmp/thistle-depleting-gpu-{before,after}.txt`.
- Final player cleanup: `/tmp/thistle-depleting-cleanup.txt`.
- Complete final melee samples: `/tmp/thistle-depleting-final-melee-samples.txt`,
  with `{elapsed_ms, {strength_stacks, displayed_min, combat_min, armor_stacks,
  armor, pvp_defense, target_health}}`.
- Final screenshots include `final-strength-full.png`,
  `final-strength-spent.png`, `final-strength-expired.png`,
  `final-armor-full.png`, `final-armor-spent.png`, and `final-armor-expired.png`.
- Initial expiry and logout: `/tmp/thistle-depleting-expired.txt` and
  `/tmp/thistle-depleting-logout.txt`.
- Final gates: `/tmp/thistle-depleting-final-{all,compile,credo}.log`.

Full vanilla parity is not established by this change.
