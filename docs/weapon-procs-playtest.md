# Innate weapon procs

Implemented in `7a0148c4` and validated with the build-5875 client on
2026-09-26 (America/Chicago).

Reference: `refs/vmangos` at `8f4e608450460efe1e38743e4da74397d4773a3a`,
particularly `Player::CastItemCombatSpell`, `SpellEntry::CanTriggerWeaponProcs`,
the successful spell-hit path in `Spell.cpp`, and ordinary weapon-hit handling
in `Unit.cpp`.

## Behavior

Weapons now roll their innate chance-on-hit spells, in item-slot order, using
the item's PPM override or the spell's fixed chance. A DBC chance above 100 uses
the reference's default one PPM and the weapon's base delay. The proc carries
its item GUID and striking hand into the ordinary spell resolver, which handles
implicit targets, damage, auras, packets, and expiry.

The victim reports one eligible weapon hit to the attacker. The attacker checks
current equipment, weapon usability, durability, and both combatants' lifetimes,
then rolls innate procs and enchantments. Enchantment procs no longer also run
from generic attack feedback. Temporary enchantment charges still pass through
the existing item owner and depletion path.

Ordinary damaging hits and blocks qualify; avoided hits, fully absorbed normal
swings, lethal hits, and self-hits do not. Successful spells qualify when their
weapon requirements and melee range permit it, or when their explicit custom
flag does. This includes non-damaging weapon abilities and is independent of
aura-proc origin rules. Multi-effect abilities produce one request per recipient.
Extra-attack recursion and individual proc global cooldowns follow the reference.

## Automated validation

`mix test.all`: **6490 passed** in 55.2 seconds. Compilation with warnings as
errors passed. Strict Credo reported zero issues across 2374 files. Formatting
and commit hooks passed; the dependency allowlist was unchanged.

Tests cover hit qualification, full absorption, blocks, dead/self/NPC sources,
spell origin independence, multi-effect spells, five item spell slots, fixed
chance and PPM, GCD boundaries, extra attacks, current equipment, disarm, feral
forms, broken weapons, offhand selection, owner delivery, enchantment charge
depletion, and duplicate feedback suppression.

Separate DBC and VMangos tests verify real melee/ranged spell qualification,
Destiny's implicit self target, its 200 Strength aura and exact expiry, Nightblade
and Destiny item mappings, and Thunderfury's eight-PPM override. These database
tags remain mutually exclusive.

## Native acceptance

Two isolated hardware-rendered clients used level-60 Debugwarrior (GUID 1) and
Debugrival (GUID 12), on map 451 at `{16307, 16300, 69.44}` and
`{16309, 16300, 69.44}` respectively. Both were PvP flagged with godmode off.
Existing development commands prepared levels, weapon skills, and item 647.
The client correctly rejected equipping Destiny before the warrior learned
Two-Handed Swords (202); learning it and accepting the native binding dialog
equipped the weapon. No proc chance was overridden.

The first accepted melee hit dealt 136 damage and triggered Destiny. Read-only
owner sampling recorded Strength `191 -> 391` and attack power `542 -> 942`.
Exactly one aura, sourced from GUID 1, remained for ten seconds. Subsequent hits
dealt 152, 165, and 162 damage; expiry restored Strength 191 and attack power 542.
The first screenshot missed the active interval, so presentation was checked in
a separate sequence. A second bounded sequence produced no proc. The target's
health was restored through `.modify hp` between later sequences.

The third sequence captured the client displaying the Destiny proc name, buff
icon, Strength 391, attack power 942, and weapon damage 286–343. Stopping attacks
left the victim alive. After expiry the client and owner state both showed
Strength 191, attack power 542, damage 212–269, and no Destiny holder. Native
unequip cleared the mainhand and changed displayed damage to 78–80; re-equipping
restored the same item GUID without recreating the expired buff.

Both players reached character selection and had nil entity registration,
world position, and metadata. The warrior then reconnected at the same position
with the same Destiny item GUID, Strength 191, attack power 542, and no Destiny
holder. The client displayed the restored weapon and baseline stats.

## Evidence

- Attacker session: `/home/pikdum/.cache/thistle-wow-playtest.VN5MA1`.
- Target session: `/home/pikdum/.cache/thistle-wow-playtest.aKalFh`.
- Server: `/tmp/thistle-weapon-procs-server.log`.
- Baseline and first samples: `/tmp/thistle-weapon-procs-baseline.txt` and
  `/tmp/thistle-weapon-procs-first-samples.txt`.
- Visible-proc samples: `/tmp/thistle-weapon-procs-visible-samples.txt`.
- Lifecycle probes: `/tmp/thistle-weapon-procs-expired.txt`, `-unequipped.txt`,
  `-reequipped.txt`, `-logout.txt`, and `-reconnect.txt`.
- Attacker screenshots include `destiny-active.png`, `destiny-expired.png`,
  `destiny-unequipped.png`, `logged-out.png`, and `reconnected.png`; the target
  has `incoming-weapon-hits.png` and `logged-out.png`.
- Final gates: `/tmp/thistle-weapon-procs-final-all.log`, `-compile.log`, and
  `-credo.log`.

The first long Tidewave request exceeded the CLI HTTP timeout, but its read-only
sampler retained the completed state transitions in the local evidence file.
Subsequent samplers used shorter intervals. Native acceptance covers Destiny's
shared proc path; it does not establish every weapon-specific spell or full
vanilla parity.

WoW's own amdgpu graphics counter increased from 1,607,791,552 to
15,528,211,921 ns for PID 1516894, and from 1,028,229,498 to 18,186,806,162 ns
for PID 1517596. Duplicate file descriptors were not summed. The server log had
no gameplay validation failures or owner errors. Existing unsupported
account-data, GM-ticket, and meeting-stone login requests were present.

Final logout probes again showed both players absent from entity registration,
world position, and metadata. Both helper-owned services were verified inactive,
their WoW processes were gone, and the retained server exited. Artifacts were
retained. No push was performed.
