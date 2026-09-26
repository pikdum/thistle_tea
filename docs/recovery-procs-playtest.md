# Recovery and healing proc acceptance

Validated with the build-5875 client on 2026-09-26 (America/Chicago).
Implementation: `e4c28387`.
Reference: `refs/vmangos` at `8f4e608450460efe1e38743e4da74397d4773a3a`,
particularly `UnitAuraProcHandler.cpp` for Blessed Recovery and Persistent
Shield, `Spell.cpp` for healing feedback, and `Unit.cpp` for damage feedback.

## Behavior

Blessed Recovery now triggers the correct healing spell for each talent rank.
Critical melee or ranged weapon damage produces three healing ticks over six
seconds, totaling the rank's 8%, 16%, or 25% damage recovery with unbiased
rounding per tick amount. The amount comes from damage after absorption.
Normal attacks, magic damage, and lethal hits do not trigger recovery.

Scarab Brooch's Persistent Shield now shields the recipient of a direct heal
for 15% of the resolved heal, including overhealing. The shield absorbs all
schools and expires after eight seconds. Another heal replaces its remaining
strength through the shared aura transition; it does not accumulate shields.

The pure `Aura.ProcSpell` resolver translates the DBC placeholder spells into
typed trigger effects carrying the real spell, recipient, and amount. Existing
proc rules, charges, cooldowns, spell delivery, and aura lifecycles remain the
owners of their respective behavior. Incoming melee-ability feedback now
includes resolved damage, and ordinary melee feedback excludes absorption.
No boundary dependencies or architecture allowlist entries were added.

## Native acceptance

A fresh server ran the implementation. Two isolated hardware-rendered clients
used existing developer setup commands and ordinary combat, item use, casts,
logout, and login. Both level-60 characters had godmode disabled. All Tidewave
inspection was read-only.

| Scenario | Client and authoritative evidence |
| --- | --- |
| Blessed Recovery | Debugpriest learned rank 3 (27816). Debugrival used Recklessness and landed a 320-point critical attack. The priest's health fell from 2307 to 1987, and recovery spell 27818 appeared with a 27-point tick. |
| Recovery ticks and expiry | Health advanced to 2014, 2041, and 2068 at approximately two-second intervals. The client displayed three 27-point recovery messages. The aura disappeared at the final tick; normal regeneration subsequently restored full health. |
| Brooch activation | The priest equipped item 21625 in the first trinket slot and used it through the client. The server recorded `CMSG_USE_ITEM` and spell 26467, establishing the 30-second proc window. |
| Full overheal | A 913-point Flash Heal left the priest at full 2307 health and created shield 26470 with 136 absorption, matching `floor(913 * 15 / 100)`. The client displayed the heal and both the item buff and shield buff. |
| Shield consumption | The rival's next attack dealt 148 damage before absorption. The client displayed “12 (136 absorbed)”; owner health fell to 2295 and the exhausted shield disappeared. The item proc buff remained. |
| Timed expiry | A second Flash Heal displayed 841 healing and a new shield. The client subsequently displayed the shield fading while the item proc buff remained. A later owner read found both timed buffs expired. The second shield's creation and expiry were not captured by the amount sampler. |
| End of proc window | Another Flash Heal after the item buff expired produced no shield. Owner state retained only passive and equipment auras. |
| Logout and reconnect | Logout removed both characters from entity registration, metadata, and world presence. Reconnecting the priest restored passive talent 27816 and equipped item 21625, retained cooldown 26467, and left recovery 27818 and buffs 26467/26470 absent. Health was full and no cast remained. |

WoW's own `amdgpu` graphics counters increased from 2,389,533,218 to
17,112,236,352 ns for PID 1424642, and from 1,714,011,966 to 16,006,939,509 ns
for PID 1425570. Duplicate file descriptors were not summed.

## Automated validation

`mix test.all`: **6,420 passed**. `mix compile --warnings-as-errors` and
`mix credo --strict` passed; Credo reported zero issues across 2,357 files.
Formatting and commit hooks passed.

Regressions cover all three talent ranks, critical-only eligibility for all
four weapon attack proc types, fractional rounding, missing amounts, shared
charges and cooldowns, damage after absorption, melee-ability feedback, lethal
hits, three periodic ticks, refresh, and death cleanup. DBC tests follow a
fully overhealing cast through owner feedback and triggered delivery to a
different recipient, then exercise absorption across schools, replacement,
expiry, and dead-target rejection. VMangos tests verify talent-rank proc-rule
inheritance and the triggered spells' zero healing coefficients.

Native acceptance exercised rank-3 recovery from a melee swing and Brooch
self-healing. Other ranks, ranged attacks, melee abilities, healing another
recipient, and shield replacement are covered by automated tests.

## Retained evidence

- Priest client: `/home/pikdum/.cache/thistle-wow-playtest.YJJXvG`.
  Screenshots include `blessed-recovery-active.png`,
  `blessed-recovery-expired.png`, `scarab-shield-active.png`,
  `scarab-shield-absorbed.png`, `scarab-shield-expired.png`,
  `scarab-window-ended.png`, `recovery-logged-out.png`, and
  `recovery-reconnected.png`.
- Rival client: `/home/pikdum/.cache/thistle-wow-playtest.DJP2CS`.
- Timed state: `/tmp/thistle-recovery-native-hot.log` and
  `/tmp/thistle-recovery-native-shield.log`.
- Lifecycle state: `/tmp/thistle-recovery-expired.log`,
  `/tmp/thistle-recovery-after-window.log`, `/tmp/thistle-recovery-logout.log`,
  and `/tmp/thistle-recovery-reconnect.log`.
- GPU evidence: `/tmp/thistle-recovery-gpu-before.log` and
  `/tmp/thistle-recovery-gpu-after.log`.
- Server and checks: `/tmp/thistle-recovery-server.log`,
  `/tmp/thistle-recovery-all.log`, `/tmp/thistle-recovery-compile.log`,
  and `/tmp/thistle-recovery-credo.log`.

The server recorded no owner crashes or unsupported aura/effect errors.
Existing account-data, GM-ticket, and meeting-stone message warnings remain
outside this gameplay path.

Both helper-owned client services and the retained acceptance server were
stopped. Logs and screenshots remain available locally. No push or deployment
was performed.
