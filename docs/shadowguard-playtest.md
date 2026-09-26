# Shadowguard and absorbed-hit proc acceptance

Validated with the build-5875 client on 2026-09-26 (America/Chicago).
Implementation: `0588b065`; shared absorbed-hit fixes: `ece148e0`.
Reference: `refs/vmangos` at `8f4e608450460efe1e38743e4da74397d4773a3a`,
particularly `Unit::HandleProcTriggerSpellAuraProc`, `CreateProcExtendMask`,
and the supported-build `spell_proc_event`, `spell_chain`, and `spell_threat` rows.

## Behavior

Shadowguard previously consumed charges while casting dummy spell 28376.
All six ranks now resolve to their damage spells, 28377 through 28382, before
normal triggered-spell delivery. The existing aura transition owns charge
consumption, the shared 3500 ms cooldown, expiry, and death removal. Existing
threat data gives all six damage spells a zero multiplier.

Incoming spell damage and weapon abilities previously skipped proc reactions
when absorption prevented all health loss. They now retain the combined hit
and absorb result while passing actual health damage to amount-based procs.
Incoming spell eligibility consumes that complete result. This permits
absorb-only proc rules and Shadowguard under Power Word: Shield without
granting damage-based recovery from prevented damage.

The investigation also found that ordinary damage shields subtracted
absorption a second time when deciding whether to retaliate. They now check
the already-resolved health damage. Partially absorbed hits still retaliate;
fully absorbed hits retain the existing damage-shield exclusion. Explicit
block and absorb proc restrictions still use their configured outcome masks.

## Native acceptance

Two isolated hardware-rendered clients used level-60 Debugpriest (GUID 4) and
Debugbidder (mage, GUID 11), with godmode disabled during acceptance. The human
debug priest learned racial spell 19312 through the existing `.learn` command.
The clients requested and accepted a duel near `{16309.2, 16218.1, 69.44}` on
map 451. Spells, attacks, logout, and reconnect used the native client;
Tidewave probes only read state.

| Scenario | Client and authoritative evidence |
| --- | --- |
| Initial aura | Rank-6 Shadowguard displayed three charges and a ten-minute duration. The owner held spell 19312, three charges, and proc amount 116. |
| Fully absorbed spell | The first rank-1 Frostbolt reduced Power Word: Shield from 942 to 921. Priest health stayed 2087. Shadowguard fell to two charges and the mage lost exactly 116 health. Its client displayed both the absorbed Frostbolt and Shadowguard damage. |
| Cooldown | Five Frostbolts landed approximately 3.3 seconds apart. The first, third, and fifth triggered Shadowguard; the second and fourth retained their current charge count. The shield expired naturally between the first and second hits. |
| Charge exhaustion | Mage health changed from 2350 to 2234, 2118, and 2002. The third retaliation removed the holder. Both clients displayed 116 Shadow damage and the priest displayed the Shadowguard fade message. |
| Fully absorbed melee | After recasting both buffs, an observed melee sequence reduced the shield from 942 to 690 while priest health stayed 2087. Shadowguard fell from three to two charges and mage health from 2350 to 2234. |
| Logout | Both clients reached character selection. Entity registration, world position, and metadata were nil for GUIDs 4 and 11. |
| Reconnect | The priest reconnected at the same position, outside combat, without the exhausted Shadowguard or expired shield. The learned spell remained usable. |
| Death | After reconnect, a fresh three-charge Shadowguard was cast. The existing `.die` command reduced health to zero and removed the holder. The client displayed the death dialog with no Shadowguard buff. |

The melee harness attempted `StopAttack()`, which does not exist in this
vanilla client. That client Lua error allowed further attacks after the
recorded two-charge snapshot. The duel was then forfeited; reconnect evidence
verifies cleanup of an exhausted aura, not preservation of a partially spent
one. The spell sequence provides the clean three-charge and cooldown proof.

Native testing exercised rank 6. All six ranks, exact cooldown boundaries,
multiple attackers sharing the cooldown, expiry, no proc on lethal damage,
zero damage threat, and absorbed melee/ranged abilities have automated coverage.
No gameplay validation failures or owner errors appeared in the server log.
Existing unsupported account-data, GM-ticket, and meeting-stone requests
appeared during login.

WoW's own `amdgpu` graphics counters increased from 3,835,978,696 to
12,292,330,803 ns for PID 1456091, and from 3,295,337,636 to 10,909,095,225 ns
for PID 1456989. Duplicate file descriptors were not summed.

## Validation and retained evidence

`mix test.all`: **6434 passed**. `mix compile --warnings-as-errors` passed.
`mix credo --strict` reported zero issues across 2359 files. Formatting and
commit hooks passed. The absorbed-proc regression was observed failing before
the shared fix and passing afterward. DBC and VMangos tests retain separate,
mutually exclusive database tags.

- Priest session: `/home/pikdum/.cache/thistle-wow-playtest.m0WZKU`.
- Mage session: `/home/pikdum/.cache/thistle-wow-playtest.cGwZbo`.
- Screenshots: `shield-ready.png`, both `frost-retaliation.png` captures,
  `absorbed-melee.png`, `logged-out.png`, `reconnected.png`, and `death-cleanup.png`
  within the corresponding session's `screenshots` directory.
- State: `/tmp/thistle-shadowguard-ready.log`, `-frost-watch.log`,
  `-exhausted.log`, `-melee-before.log`, `-melee-after.log`, `-logout.log`,
  `-reconnect.log`, `-death-before.log`, and `-death-after.log`, all sharing the
  `/tmp/thistle-shadowguard` prefix.
- GPU counters: `/tmp/thistle-shadowguard-gpu-before.log` and `-gpu-after.log`.
- Server and gates: `/tmp/thistle-shadowguard-server.log`, `-all.log`,
  `-compile.log`, and `-credo.log`.

Both helper-owned client services and the retained server were stopped after
acceptance. No push was performed.
