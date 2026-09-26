# Equipment Mana Drain acceptance

Validated with the build-5875 client on 2026-09-26 (America/Chicago).
Implementation: `5ff4b493`.
Reference: `refs/vmangos` at `8f4e608450460efe1e38743e4da74397d4773a3a`,
particularly `Unit::HandleProcTriggerSpellAuraProc`, `Spell::EffectPowerDrain`,
and the supported-build item and spell rows.

## Behavior

Black Grasp of the Destroyer (item 22194) equips Mana Drain aura 27522.
Its DBC trigger points to dummy spell 18350. Proc resolution now emits the
two spells used by VMangos: self energize 29471 and enemy power drain 27526.
Both use the existing triggered-spell delivery and living-recipient checks.
The aura transition still owns charge consumption and cooldown application,
once per proc even when resolution produces multiple spells.

Each eligible hit grants the wearer 8 mana directly. The second spell drains
up to 8 available mana from a living mana user and returns that actual amount
to the wearer. Consequently, a target with at least 8 mana yields 16 total;
a target with 3 yields 11; an empty or non-mana target yields 8. Recovery caps
at the wearer's maximum mana. Missing or dead victims do not suppress the
independent self energize, and dead wearers cannot receive it. Neither spell
scales with spell power or changes the normal mana-regeneration timer.

The actual item has no proc-rate override. Its DBC aura has a 100 percent
chance, no charges, and mask `0x154`, covering successful melee and ranged
attacks and abilities. Ordinary spell damage, healing, periodic damage, and
failed attacks do not trigger it.

## Native acceptance

Two isolated hardware-rendered clients used level-60 Debughunter (GUID 7)
and Debugbidder (mage, GUID 11), followed by Debugrival (warrior, GUID 12),
with godmode disabled. Testing took place near `{16303.2, 16218.1, 69.44}` on
map 451. Existing developer commands supplied the item, levels, position,
and mana setup. Equipping, dueling, attacking, casting, logout, and reconnect
used the native clients. Tidewave probes only read authoritative state.

| Scenario | Client and authoritative evidence |
| --- | --- |
| Equip | The native binding confirmation equipped item 22194 in the hands slot. Exactly one 27522 holder existed, sourced from item GUID `4611686018427388164`. |
| Melee | A main-hand hit reduced mage mana from 158 to 150 while hunter mana rose from 134 to 150. An off-hand hit reduced mage mana from 150 to 142 while hunter mana rose from 150 to 166. Both clients displayed Mana Drain combat feedback. Normal regeneration appeared separately in the sampler. |
| Ranged ability | Rank-1 Arcane Shot first spent 25 mana, reducing hunter mana from 134 to 109. Its 13-damage hit reduced mage mana from 2230 to 2222 and restored hunter mana to 125. |
| Ranged attack | The following 166-damage Auto Shot reduced mage mana from 2222 to 2214 and raised hunter mana from 125 to 141. Both clients displayed the ranged hits and drain; the hunter also displayed the separate energize. |
| Unequip | Removing the gloves left the hands slot empty and removed the holder. In a fresh duel, Arcane Shot and two Auto Shots dealt 13, 193, and 178 damage. Hunter mana remained 109 after the initial spell cost; mage mana remained 4368. No drain occurred. |
| Reequip | The same bound item restored exactly one holder with the same item source. |
| Logout | Both clients reached character selection. Entity registration, world position, and metadata were nil for GUIDs 7 and 11. |
| Reconnect | The hunter returned at the same position with the same gloves and exactly one item-sourced holder. Godmode remained disabled. |
| Non-mana victim | After reconnect, three weapon hits against the flagged warrior dealt 75, 25, and 25 damage. Hunter mana rose from 168 to 176, 184, and 192. The warrior's active resource was rage and its mana and maximum mana were zero. The hunter displayed three separate 8-mana gains. |

The samples distinguish attack recovery from normal regeneration: hunter
regeneration added 34 mana, whereas these procs added 16 or 8. Clearing a
target did not stop Auto Shot in the harness; cancellation used the native
`SpellStopCasting()` request and duel cleanup used forfeiture. The recorded
sequences include multiple hits rather than claiming isolated single shots.
The unequip proof uses the fresh duel with confirmed damage; an earlier
attempt that never landed a hit is excluded.

No gameplay validation failures or owner errors appeared in the server log.
WoW's own `amdgpu` graphics counters increased from 6,164,870,649 to
31,742,768,598 ns for PID 1465049, and from 5,037,901,111 to 28,211,424,636 ns
for PID 1465871. Duplicate file descriptors were not summed.

## Validation and retained evidence

`mix test.all`: **6442 passed**. `mix compile --warnings-as-errors` passed.
`mix credo --strict` reported zero issues across 2361 files. Formatting,
diff checks, and commit hooks passed. Automated coverage includes event
provenance, eligible outcomes, shared charge/cooldown transitions, actual DBC
resource effects, partial and empty pools, other active resources, dead and
missing recipients, maximum-mana clamping, and equipment removal/reapplication.
DBC and VMangos tests retain separate, mutually exclusive database tags.

- Hunter session: `/home/pikdum/.cache/thistle-wow-playtest.pEo2Gv`.
- Mage/warrior session: `/home/pikdum/.cache/thistle-wow-playtest.EOVk0l`.
- Screenshots: `equipped-confirmed.png`, `melee-mana.png`, `ranged-mana.png`,
  `unequipped-hit.png`, `logged-out.png`, `reconnected.png`, and
  `warrior-mana.png` in the corresponding session's `screenshots` directory.
- State logs share `/tmp/thistle-mana-drain`: `-ready.log`, `-melee-watch.log`,
  `-weapons.log`, `-ranged-watch.log`, `-unequipped.log`,
  `-unequipped-hit-watch.log`, `-reequipped.log`, `-logout.log`,
  `-reconnect.log`, `-warrior-resource.log`, and `-warrior-watch.log`.
- GPU counters: `/tmp/thistle-mana-drain-gpu-before.log` and `-gpu-after.log`.
- Server and gates: `/tmp/thistle-mana-drain-server.log`, `-focused.log`,
  `-all.log`, `-compile.log`, and `-credo.log`.

Both helper-owned client services and the retained server were stopped after
acceptance. No push was performed.
