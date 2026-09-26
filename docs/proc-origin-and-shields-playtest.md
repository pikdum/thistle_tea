# Proc origins and retaliatory shields

Validated with the build-5875 client on 2026-09-26 (America/Chicago).

- `d7d60184`: preserve spell origins through proc feedback and report eligible triggered cast completion.
- `56658f00`: resolve all seven Lightning Shield ranks to their damage spells.
- `bb300e6c`: prevent direct damage shields from chaining procs, preserve their school, and credit their bearer.

Reference: `refs/vmangos` at `8f4e608450460efe1e38743e4da74397d4773a3a`:
`Spell::prepareDataForTriggerSystem`, `ProcSystemArguments`, aura eligibility in
`UnitAuraProcHandler.cpp`, its Lightning Shield rank mapping, and
`Unit::TriggerDamageShields`.

## Behavior

Proc feedback distinguishes ordinary casts, permitted aura/item triggers, and
spells that cannot start proc chains. Eligibility honors `NOT_A_PROC`,
`CAN_PROC_FROM_PROCS`, caster/target suppression, positive item casts, game-object
sources, and the reference's channel, trap, and class exceptions. Existing
school, family, outcome, charge, chance, and cooldown checks still apply.
Ordinary periodic ticks retain their own eligibility instead of inheriting the
applying cast's restrictions.

Typed damage, healing, weapon outcome, and cast-completion effects carry the
origin to the owning process. Weapon feedback also retains the actual spell,
including triggered spells absent from the spellbook. Weapon enchant procs
retain the casting item's GUID. Area triggers report completion once; eligible
channel child spells report their own completion after damage snapshots.

Native testing exposed Lightning Shield spending charges on its DBC placeholder
without dealing damage. The shared proc resolver now substitutes each rank's
damage spell. The same audit found direct damage shields hardcoded to Holy,
credited to the original aura caster, and able to start proc chains. They now
retain the shield's school, credit its bearer, and suppress further procs.

## Native acceptance

Two isolated hardware-rendered clients used level-60 Debugshaman (GUID 8) and
Debugbidder (mage, GUID 11) on map 451, near `{16307, 16300, 69.44}`. Both were
PvP flagged, with godmode disabled. Existing `.learn` commands supplied rank-7
Lightning Shield and the mage's test-only Shadowguard/Thorns. The real trinket
19950 was added and equipped through client inventory actions. Tidewave probes
only read owner state and wrote diagnostic samples.

| Scenario | Evidence |
| --- | --- |
| Lightning Shield before repair | Three charges disappeared while attacker health remained unchanged. This run was rejected as proc-origin acceptance and prompted the rank-mapping fix. |
| Lightning Shield after repair | The first two retaliations dealt 201 damage each: mage health `2460 -> 2259 -> 2058`. Shield charges fell `3 -> 2 -> 1`; intervening melee hits retained the charge count during cooldown. Shadowguard remained at three charges with no proc cooldown. Further attacks exhausted Lightning Shield while Shadowguard still held three charges. |
| Ordinary spell | A native rank-1 Earth Shock changed Shadowguard from three charges to two and started its proc cooldown. |
| Channel exception | Zandalarian Hero Charm initialized 12 Unstable Power stacks. Rank-1 Arcane Missiles produced three child hits, reducing stacks `12 -> 11 -> 10 -> 9` and dealing `53, 51, 49` damage. The client displayed nine stacks and the final hit. Both trinket holders expired approximately 20 seconds after activation. |
| Direct shield | After cancelling Shadowguard, the mage cast Thorns. Four shaman melee hits returned 18 damage each: shaman health `3330 -> 3312 -> 3294 -> 3276 -> 3258`. Lightning Shield retained three charges throughout. The client displayed the returned damage and unchanged charge count. |
| Logout and reconnect | Both clients reached character selection; entity registration, world position, and metadata were nil for GUIDs 8 and 11. The shaman reconnected at the same position with exactly one Lightning Shield holder, three charges, and its original expiry deadline. |

An initial melee attempt faced the wrong way and caused no state changes.
An overlapping input batch later caused a client Lua error during diagnostic
printing and trinket preparation. It was dismissed, equipment was verified, and
the successful channel sequence used sequential input. Neither failed harness
attempt is used as gameplay evidence.

Automated tests cover all Lightning Shield ranks and damage amounts, cooldown
boundaries, exhaustion, expiry, death, source credit, damage school, both proc
directions, resisted casts, item healing, periodic ticks, class exceptions,
owner-context delivery, and area/triggered cast completion. Native acceptance
does not establish every class exception or full vanilla parity.

## Validation and evidence

`mix test.all`: **6475 passed** in 73 seconds. Compilation with warnings as errors
passed. Strict Credo reported zero issues across 2368 files. Formatting and
commit hooks passed; database tags remain mutually exclusive.

- Shaman session: `/home/pikdum/.cache/thistle-wow-playtest.5nGL31`.
- Mage session: `/home/pikdum/.cache/thistle-wow-playtest.irbIb2`.
- Screenshots in those sessions include `shield-retaliation.png`,
  `shield-exhaustion.png`, `channel-stacks.png`, `thorns-retaliation.png`,
  `logged-out.png`, and `reconnected.png`.
- Samples: `/tmp/thistle-proc-origin-melee-samples.txt`,
  `-channel-samples.txt`, `-thorns-samples.txt`, `-fixed-baseline.txt`,
  `-exhausted.txt`, `-earth-shock.txt`, `-logout.txt`, and `-reconnect.txt`,
  sharing the same prefix.
- Server: `/tmp/thistle-proc-origin-fixed-server.log`; the pre-repair log is
  `/tmp/thistle-proc-origin-server.log`.
- Final gates: `/tmp/thistle-proc-shields-final-all.log`, `-compile.log`, and
  `-credo.log`.

WoW's own amdgpu counters increased from 1,741,596,551 to 33,810,589,635 ns for
PID 1499237 and from 1,430,252,602 to 32,224,231,782 ns for PID 1500214.
Duplicate file descriptors were not summed. No gameplay validation failures
or owner errors appeared in the final server log. Existing unsupported
account-data, GM-ticket, and meeting-stone login requests were present.

Both helper-owned client services and the retained server were stopped after
acceptance. Final probes confirmed both players absent from entity registration,
world position, and metadata. No push was performed.
