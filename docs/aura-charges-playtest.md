# Aura charges and Improved Shield Block

Aura creation now applies spell-family charge modifiers (operation 4) from
the caster's cast snapshot. Flat modifiers precede percentages, fractional
charges truncate, and nonpositive counts retain the existing unlimited-charge
representation. Refresh replaces spent charges with the new cast's count.
Self-owned linked auras use the owner's modifiers. Charged modifiers are
consumed through the existing cast-completion path after their benefit is
captured.

Shield Block also now spends a charge through incoming-attack reactions.
Its cached block-only proc rule admits full and partial blocks, preserves
charges on other outcomes, and removes the holder after the last block.
The existing aura transition updates the buff applications field, displayed
block chance, and expiry schedule together.

## References and automated validation

- `refs/vmangos/src/game/Spells/SpellAuras.cpp`: the `SpellAuraHolder`
  constructor applies `SPELLMOD_CHARGES` when creating the holder.
- `refs/vmangos/src/game/UnitAuraProcHandler.cpp`: aura 51 uses the ordinary
  charge-spending proc path without a triggered spell.
- VMangos `spell_proc_event` entry 2565: `procEx = 0x40` (block).
- Vanilla DBC: Shield Block 2565 has one charge; Improved Shield Block
  12945, 12307, and 12944 add one charge and 500, 1,000, or 2,000 ms.

Fourteen added regression tests cover caster versus recipient modifiers,
family/mask filtering, percentage composition, fractional and nonpositive
counts, charge replenishment, linked holders, modifier consumption, full
and partial blocks, non-block outcomes, packed buff counts, expiry, death,
real DBC talent ranks, and the VMangos proc restriction. Database tests use
separate DBC and VMangos tags.

Implementation commit `438de45b` passed `mix test.all` (5,545 tests),
`mix compile --warnings-as-errors`, `mix credo --strict` (zero issues),
formatting, and whitespace checks.

## Native client acceptance

A fresh server on `438de45b` served the isolated build-5875 GPU client.
Debugwarrior (GUID 1) used level 60, Defensive Stance, a one-handed sword,
and Aegis of Stormwind (1203). God mode remained off. All learning, equipping,
casting, and positioning used native client commands. Tidewave only read
state. A temporary read-only client callback reported `UnitBuff` charges
and `GetBlockChance`; combat-event callbacks echoed actual block messages.

At `{16256.2, 16343.1, 69.44}` on Programmer Isle, two seeded Skeletal
Flayers attacked from opposite sides. The frontal attacker could be
blocked; rear attacks continued to damage the warrior.

| Case | Client and authoritative result |
| --- | --- |
| Baseline, no attacker | One charge and 80% block; expiry returned to no buff and 5% after 5,000 ms. |
| Baseline, drawn shield | The first full block removed the one-charge holder about 1,028 ms after application, before expiry. Health did not change on that block. |
| Improved Shield Block rank 1 | The buff icon displayed `2`. Sampled charges changed `2 → 1 → absent`; client block messages and diagnostics agreed. |
| First talented block | At sample time 4,169 ms, charges fell from two to one, the packed application byte fell from one to zero, and block chance remained 80%. Health stayed 3,349. |
| Second talented block | At 5,483 ms, the holder disappeared and block chance returned to 5%. Health stayed 3,322. The holder had been applied at sample time 2,162 ms and had a 5,500 ms lifetime. |
| Talented expiry, no attacker | Both unused charges persisted until 5,501 ms after the first application sample, then the buff disappeared and chance returned to 5%. |

An initial combat cast was rejected by the client after rage had decayed;
rage was replenished before measured casts. A later attempt with sheathed
weapons correctly preserved the charge until expiry. Drawing the shield
enabled the successful combat checks above, matching VMangos's vanilla
sheath restriction. Full/partial blocks and death cleanup are deterministic
test coverage; the native charged blocks in this run were full blocks.
No second observer client was used.

Final owner state had no Shield Block holder, no active cast, no combat,
5% block chance, and god mode off. There were no server errors or server
cast-validation failures. The log contained only the known account-data,
GM-ticket, and meeting-stone unsupported login requests. WoW process 129516
had amdgpu rendering counters. The owned client cgroup and server were
stopped after acceptance.

## Retained evidence

- Client session: `/home/pikdum/.cache/thistle-wow-playtest.i7ris7/`.
- Screenshots: `baseline-active.png`, `improved-active.png`,
  `improved-spent.png`, and `improved-expired.png` in its `screenshots/`.
- Owner samples: `/tmp/thistle-aura-charges-baseline-expiry.txt`,
  `/tmp/thistle-aura-charges-baseline-drawn.txt`,
  `/tmp/thistle-aura-charges-improved-combat.txt`, and
  `/tmp/thistle-aura-charges-improved-expiry.txt`.
- Final owner state: `/tmp/thistle-aura-charges-final-state.txt`.
- Server and rendering evidence: `/tmp/thistle-aura-charges-server.log`
  and `/tmp/thistle-aura-charges-gpu.txt`.
- Gates: `/tmp/thistle-aura-charges-{tests,compile,credo}.log`.
