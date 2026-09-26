# Aura proc chance and permanent trigger lifetime

Implemented in `c6af8a41` and `4d2b8405`. Reference: local VMangos revision
`8f4e608450460efe1e38743e4da74397d4773a3a`, particularly
`UnitAuraProcHandler.cpp`, `Unit::GetPPMProcChance`, and
`SpellAuraHolder::CleanupTriggeredSpells`.

## Behavior

Outgoing aura procs now calculate PPM from the bearer's current main-hand,
off-hand, ranged, or feral base attack period. Spell feedback previously supplied
no period, preventing ranged PPM auras such as Dragonstalker's Expose Weakness
and Badge of the Swarmguard from triggering. Incoming reactions use the fixed
DBC or custom chance, as in VMangos. Haste changes attack frequency without
changing the chance per hit.

Chance modifiers now apply at reaction time, after custom or PPM rates, using
the bearer's current modifiers and inherited pet or totem owner modifiers.
Applying an aura no longer permanently changes its base proc chance. This
avoids stale talent snapshots and duplicate modifiers, and allows modifiers
to affect custom and PPM chances. PPM is not capped before modifiers.
Equipment eligibility, charges, and cooldowns retain their existing funnels.

Removing an aura also removes its permanent triggered buffs on the same
bearer, including dependent trigger and linked-aura chains. Finite buffs retain
their own deadlines, ordinary source refresh preserves existing stacks, and
the reference's one-tick periodic exception remains supported. Permanent
self-targeted triggered deliveries carry the source holder identity and
application time; delivery after source removal, expiry, or replacement cannot
restore an orphaned buff.

This fixes Swarmguard's otherwise permanent Insight of the Qiraji stacks.
The implementation is pure aura logic plus typed cast context at the existing
resolver boundary, with no new gameplay database queries, process access,
persistent store, or architecture allowlist entry.

## Automated validation

- `mix test.all`: **6531 passed**, 66.3 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2387 files.
- Formatting and commit hooks passed.

Tests cover attack-hand selection, feral periods, incoming versus outgoing
PPM, flat/percent modifier order, uncapped PPM before negative modifiers,
current talent changes, inherited pet modifiers, foreign caster snapshots,
charge/cooldown preservation, kills, ranged spell feedback, permanent trigger
chains, linked descendants, source refresh, finite lifetimes, the one-tick
exception, and delayed delivery rejection.

Separate DBC and VMangos tests verify real Hawk and Nature's Grasp talents,
Expose Weakness and Swarmguard rules, Swarmguard's six stacks, 200 armor
penetration per stack, client aura application bytes, implicit self-targeting,
cancellation, expiry, and death. Database tags remain mutually exclusive.

## Native acceptance

On 2026-09-26, build-5875 clients used level-60 Debughunter (GUID 7) and Debugrival (GUID 12)
on map 451 at `{16307, 16300, 69.44}` and `{16319, 16300, 69.44}`. Both were
PvP flagged with godmode off. The hunter's pet was set passive and following.
All mutations used native input and existing development commands; Tidewave
was read-only.

The hunter equipped item 21670, Badge of the Swarmguard, in inventory slot 13
(item GUID `4611686018427388164`) and activated it through native inventory use.
The ordinary VMangos rule was 10 PPM. Bow of Searing Arrows (2825) supplied a
2700 ms base period and a 45% proc chance. Quiver haste gave a 2454 ms attack
period; native Rapid Fire temporarily reduced it to 1753 ms.

Native Auto Shot dealt damage to the opposing player and triggered Insight of
the Qiraji (26481) on the hunter. Owner samples observed stacks one through six
and armor penetration from 200 through 1200. The client showed the proc buff
and ranged damage. After the 30-second source expired, the hunter had neither
holder nor armor penetration. The original long sample was truncated by the
diagnostic tool after the six-stack observation; the separate expiry probe
confirmed cleanup.

A second native use after the normal three-minute cooldown retained complete
timed evidence. The client displayed three Insight stacks with one second left
on the source buff, then both icons disappeared. Owner sampling recorded
200, 400, and 600 armor penetration, followed by zero when the source ended.
The source appeared at sample time 3892 ms and was absent at 33816 ms, within
the 100 ms sampling resolution of its 30-second duration. Subsequent Auto Shots
continued to deal damage without creating more stacks. `SpellStopCasting()`
cancelled repeat fire, and the owner confirmed `auto_shot: nil`.

Both players reached character selection and were absent from entity
registration, world position, and metadata. The hunter reconnected at the same
position with the same trinket GUID, 2700 ms base bow period, 2454 ms hasted
period, and remaining item cooldown. Expired Swarmguard, Insight, and Rapid
Fire holders were absent; armor penetration was empty and Auto Shot was off.
The character panel showed the equipped trinket and bow after reconnect.

WoW's own amdgpu graphics counters increased from 2,230,925,267 to
18,526,069,385 ns for PID 1558437 and from 1,907,006,290 to 16,847,879,600 ns
for PID 1559157. Duplicate file descriptors were not summed. The server log
contained no owner errors or spell-validation failures. Existing unsupported
account-data, GM-ticket, and meeting-stone login requests remained.

Final logout again removed both player GUIDs from registration, position, and
metadata. Both helper-owned services were verified inactive, their WoW
processes were gone, and the retained server exited. Evidence was retained.
Nothing was pushed.

## Evidence

- Hunter: `/home/pikdum/.cache/thistle-wow-playtest.uu8LTA`.
- Defender: `/home/pikdum/.cache/thistle-wow-playtest.Q9Kfz3`.
- Server: `/tmp/thistle-proc-chance-server.log`.
- Baseline and expiry: `/tmp/thistle-proc-chance-baseline.txt` and
  `/tmp/thistle-proc-chance-expired.txt`.
- Initial samples: `/tmp/thistle-proc-chance-shot-samples.txt`.
- Logout and reconnect: `/tmp/thistle-proc-chance-logout.txt` and
  `/tmp/thistle-proc-chance-reconnect.txt`.
- Final cleanup: `/tmp/thistle-proc-chance-cleanup.txt`.
- Complete samples: `/tmp/thistle-proc-chance-timed-samples.txt`, with tuples
  `{elapsed_ms, {source_present, stacks, penetration, attack_period, target_health}}`.
- Screenshots: `swarmguard-procs.png`, `ranged-damage.png`,
  `timed-procs-5.png`, and `timed-stopped.png` in the corresponding sessions.
- Reconnect screenshot: `reconnected.png` in the hunter session.
- Hardware counters: `/tmp/thistle-proc-chance-gpu-{before,after}.txt`.
- Gates: `/tmp/thistle-proc-chance-final-{all,compile,credo}.log`.

Full vanilla parity is not established by this change.
