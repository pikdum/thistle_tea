# Aura proc equipment requirements

Implemented in `bc0641c3`, with hand selection completed in `a3d8cecd`, and
validated with the build-5875 client on 2026-09-26 (America/Chicago).
Reference: `refs/vmangos` revision
`8f4e608450460efe1e38743e4da74397d4773a3a`, the current-equipment checks in
`UnitAuraProcHandler.cpp` and `SPELL_ATTR_EX3_NO_PROC_EQUIP_REQUIREMENT` in
`Spells/SpellDefines.h`.

## Change

Outgoing spell procs previously skipped the aura's equipment requirement.
Melee procs checked a supplied weapon snapshot and allowed missing snapshots.
All outgoing aura reaction paths now share a pure check of the owner's current
usable equipment, before rolling or spending charges and cooldowns.

Weapon requirements select the triggering main hand, off hand, or ranged slot,
including explicit off-hand melee spells and auto-repeat spells, then check
item class and subclass. Broken gear, disarmed main hands, and feral
natural attacks cannot satisfy weapon requirements. Armor requirements use the
current unbroken shield. As in the reference, proc eligibility does not use the
spell's cast-time inventory-type mask. Creature owners and the explicit DBC
equipment-exemption flag bypass these player restrictions. Incoming reactions
remain unrestricted by the defender's equipment.

The implementation reuses canonical weapon inputs, broken-equipment state, and
the existing equipment shield projection. It adds no gameplay database queries,
process access, new equipment cache, or architecture allowlist entry.

## Automated validation

- `mix test.all`: **6512 passed**, 65.9 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2381 files.
- Formatting and commit hooks passed.

Tests cover current hand selection, spell and auto-repeat ranged selection,
empty and broken slots, stale supplied weapon data, disarm, feral forms, shield
subclasses, cast-time mask independence, exempt spells, creature owners,
incoming reactions, cast completion, kills, and unchanged charges/cooldowns on
rejection. DBC tests verify real exemption flags and critical-spell eligibility
for all three Deep Wounds ranks. Database tags remain mutually exclusive.

## Native acceptance

Two hardware-rendered clients used level-60 Debugbidder (mage, GUID 11) and
Debugrival (warrior, GUID 12), at `{16307, 16300, 69.44}` and
`{16309, 16300, 69.44}` on map 451. Both were PvP flagged with godmode off.
The mage learned Deep Wounds rank 3 through the existing development command
as a cross-class fixture for this shared proc path. Combustion supplied normal
increasing critical chance; neither proc chances nor live entity state were
overridden. All mutations used native client actions and existing commands.

Native acceptance ran on `bc0641c3`. The subsequent hand-selection correction
matches `SpellEntry::GetWeaponAttackType` and has automated coverage. The current
DBC has no explicit off-hand spell rows or auto-repeat rows lacking the ranged
slot flag, so that correction does not change these native spell paths.

With staff 19567 equipped, item GUID `4611686018427388140`, the mage's damage
range was 110.14–164.14. The first rank-1 Fireball critically hit for 30 and
applied Deep Wounds 12721 from GUID 11, with 20-damage ticks for twelve seconds.
Both clients displayed the bleed icon; the attacker displayed the critical-hit
combat message. Owner sampling recorded the ticks and removal at expiry.

Native unequip cleared the main-hand GUID and canonical weapon input, while
retaining the talent. A subsequent critical Fireball dealt 25 without applying
a bleed. This first negative check alone was insufficient: the mage's unarmed
damage would round the bleed to zero even without the equipment check.

The mage therefore drank item 9206, Elixir of Giants, through native inventory
use. Its 25 Strength raised unarmed damage to 7.43–8.43. A read-only call to the
normal Deep Wounds amount function now returned a positive one-damage tick.
Another critical Fireball dealt 25, exhausted Combustion's final charge, and
still produced no Deep Wounds holder or ticks. The client showed the critical
message, empty weapon slot, Strength 55, and damage 7–9; the defender showed
only Fireball's own periodic effect. The passive talent remained present.

Re-equipping the staff restored its exact item GUID and a 115.32–169.32 damage
range with the elixir active. Both players reached character selection and
were absent from entity registration, world position, and metadata. The mage
then reconnected at the same position with the same staff, damage inputs,
one Deep Wounds passive, and the elixir. Spent Combustion and expired bleeds did
not return. The character panel displayed the restored staff and damage range.

Ordinary PvP health regeneration resumed between later bleed ticks in the armed
run. This was checked against the reference: non-channeled periodic damage does
not refresh its PvP combat timer (`Unit.cpp`, `ShouldEnterCombat`).

## Evidence

- Mage: `/home/pikdum/.cache/thistle-wow-playtest.5sUVSh`.
- Defender: `/home/pikdum/.cache/thistle-wow-playtest.QRbvHZ`.
- Server: `/tmp/thistle-proc-equipment-server.log`.
- Samples: `/tmp/thistle-proc-equipment-armed-samples.txt`,
  `-unarmed-samples.txt`, and `-strength-samples.txt`.
- Baseline: `/tmp/thistle-proc-equipment-baseline.txt`,
  `-strength-baseline.txt`, and `-unarmed-potential-tick.txt`.
- Lifecycle: `/tmp/thistle-proc-equipment-reequipped.txt`, `-logout.txt`,
  and `-reconnect.txt`.
- Screenshots: `armed-critical.png`, `armed-bleed.png`,
  `unarmed-critical.png`, `unarmed-no-bleed.png`,
  `strong-unarmed-critical.png`, and `strong-unarmed-no-bleed.png`.
- Gates: `/tmp/thistle-proc-equipment-final-all.log`, `-compile.log`, and
  `-credo.log`.

Native acceptance exercises spell-proc eligibility with current equipment.
Broken gear, disarm, feral forms, other hands, exemptions, and rejection without
charge/cooldown consumption have automated coverage. Full vanilla parity is
not established by this change.

WoW's own amdgpu graphics counter increased from 4,811,619,977 to
18,813,996,750 ns for PID 1543636, and from 4,383,240,153 to 17,923,768,135 ns
for PID 1544505. Duplicate file descriptors were not summed. The server log had
no owner errors or failed gameplay validation. Existing unsupported account-data,
GM-ticket, and meeting-stone login requests were present.

Final logout again left both player GUIDs absent from entity registration,
world position, and metadata. Both helper-owned services were verified inactive,
their WoW processes were gone, and the retained server exited. Artifacts were
retained. Nothing was pushed.
