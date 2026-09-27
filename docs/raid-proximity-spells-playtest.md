# Raid proximity spell targeting

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Spell.cpp` target 56 and `FillRaidOrPartyTargets`, and
`SpellAuras.cpp` periodic trigger casting.

Target 56 now resolves living raid members and their pets around the casting
actor, across subgroups, excluding that actor. It uses the current controller's
group, exact spatial distance and world identity, the modified effect radius,
and the reference's owner-level and hostility checks. An ungrouped player and
pet can affect one another. Pet range is independent of owner range.

The existing periodic trigger boundary supplies the afflicted actor as the
spatial origin while retaining the original caster in damage context. Plague
22997 triggers 19594 and Plague 26556 triggers 26557: both search five yards
every three seconds for 40 seconds. These parent spells are not dispellable.

Implementation commit: `70650057`.

## Native acceptance

Two isolated build-5875 GPU clients ran against a fresh server:

- Debugpriest, GUID 4, session `/home/pikdum/.cache/thistle-wow-playtest.qNLUEi`.
- Debugbuyer, GUID 10, session `/home/pikdum/.cache/thistle-wow-playtest.yP9COk`.

Native invite, accept, convert-to-raid, and subgroup commands produced a raid
with the priest in subgroup 1 and the warrior in subgroup 0. GM relocation
prepared positions; a native Flash Heal restored preparation fall damage.
God mode protected the priest from the NPC's melee attacks. The warrior had
god mode disabled throughout. Tidewave probes were read-only.

The seeded level-18 Defias Evoker, GUID `17379390991031543628`, casts Plague
through its ordinary combat spell list. Its actual ground position on map 451
is `{15983.2, 16088.1, 20.25605}`. Use that height when preparing this case;
the plateau's usual 69.44 elevation causes a fall here.

The first preparation run teleported the carrier back to camp and allowed
NPC target changes. The accepted repeat kept the priest beside the Evoker at
`{15983.20020, 16090.09961, 19.79970}`. The warrior stood at
`{15983.20020, 16093.09961, 19.10000}`, approximately 3.08 yards away.

The carrier received aura 22997 from the Evoker. During the nearby sample,
the warrior's health changed from 2829 to 2321, 1809, 1257, and 655.
The native combat log attributed the corresponding 508, 512, 552, and 602
Nature damage hits to **Defias Evoker's Plague Effect**. Intervening resisted
ticks appeared in the same log. The warrior did not acquire the parent aura
during this repeat. Carrier exclusion is asserted by automated recipient tests;
the priest's native health alone is not evidence because god mode was active.

Moving the warrior to Y `16100.09961`, more than ten yards from the carrier,
stopped the splash. A subsequent sample covered the NPC's next Plague cast
while the warrior remained outside its radius: health regenerated without
further damage. The native target frame showed the priest's active debuff.

The warrior then left the raid and returned to the earlier nearby position.
With the priest still afflicted, the now-unrelated warrior regenerated to
2829 and remained there. At 9.055 seconds into this sample, the priest's
40-second aura expired and disappeared from owner state. The NPC's later
60-second recast was a new holder, as expected.

Evidence:

- `/tmp/thistle-raid-target-prepared.log`: raid membership and subgroup IDs.
- `/tmp/thistle-raid-target-near-far.log`: parent identity, positions, and health drops.
- `/tmp/thistle-raid-target-expiry.log`: outside-radius regeneration during a fresh parent cast.
- `/tmp/thistle-raid-target-unrelated.log`: nearby outsider exclusion and parent expiry.
- Warrior screenshots `raid-splash-active.png`, `raid-splash-combat-log.png`,
  `raid-splash-range.png`, and `nearby-outside-raid.png`.
- Priest screenshot `plague-acquired.png`.

Both renderers used the AMD RX 7900 XT. WoW's own DRM graphics counters grew
from 1,185,331,225 to 13,653,702,046 ns for PID 2175099, and from 580,669,856
to 14,196,649,275 ns for PID 2176136.

The server log `/tmp/thistle-raid-target-server.log` contained no gameplay
errors or cast validation failures. Only the existing account-data and ticket
query opcode warnings appeared at login.

## Automated checks and cleanup

`mix test.all` passed all 6,971 tests; compilation with warnings as errors
and strict Credo passed. Focused targeting and trigger coverage passed 85 tests.
Logs: `/tmp/thistle-raid-target-all.log`,
`/tmp/thistle-raid-target-compile.log`, `/tmp/thistle-raid-target-focused.log`,
and `/tmp/thistle-raid-target-commit.log`.

Coverage includes both actual Plague chains, damage and launch attribution,
subgroups, unrelated allies, pets and current controllers, independent pet
range, owner level and duel eligibility, dead recipients, other world copies,
radius modifier removal, target caps, expiry, explicit removal, and death.
No architecture allowlist changes were needed. Pet variations were tested
automatically; native acceptance used two players.

Both helper-owned services were stopped and their cgroups were empty. Both
WoW PIDs disappeared, the retained server PTY exited, and ports 4000, 3724,
and 8085 were free. Artifacts were retained. Nothing was pushed.
