# Blocked-hit procs

Melee resolution now preserves combined proc results through defender reactions
and asynchronous attacker feedback. A partial block carries both normal-hit
and block flags. A full block carries only block. Absorption adds its own flag
without discarding the original hit result, including when it absorbs all of
the damage remaining after a partial block.

Ordinary aura procs, Retaliation, and Sweeping Strikes can consequently trigger
from partial blocks. Full blocks still activate explicitly block-triggered
abilities without activating ordinary hit procs. Outgoing avoided outcomes
reach proc evaluation so explicit matching rules can act on them; default
hit-only rules continue to reject them.

Damage shields use their separate contact rules: ordinary shields react to
partial and full blocks, but skip fully absorbed ordinary hits. Explicit
block-only rules remain block-only. Incoming generic procs now use the shared
cooldown and charge transition, fixing the path that previously ignored
cooldowns while spending charges.

## References and automated acceptance

Compared against VMangos `8f4e60845`:

- `Objects/Unit.cpp`: partial-block normal-hit flags, full blocks, absorb
  flags, `SetDamageDependentHitInfoFlags`, and `TriggerDamageShields`.
- `Spells/SpellMgr.cpp`: normal/critical defaults and proc-extra matching.
- `Spells/SpellDefines.h`: proc-extra flag values.
- `UnitAuraProcHandler.cpp`: Retaliation and Sweeping Strikes.

Regression tests resolve real attack-table outcomes, deliver typed feedback
through the entity boundary, and evaluate the receiving attacker. They cover
partial blocks with no, partial, and complete absorption; full blocks; normal
hits that are fully absorbed; normal/block/absorb-specific proc rules; avoided
outgoing attacks; Retaliation; Sweeping Strikes; and cooldown, charge retention,
and final-charge removal on incoming procs. An earlier test that treated all
blocks as avoided damage-shield contacts was corrected.

Implementation commit `ac93fa2b` passed:

- Focused checks: 222 passed.
- `mix test.all`: 4,540 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.

The first full run had one unrelated connection-loss test exceed its default
100 ms process-exit wait. Separate commit `07a60e60` gives that asynchronous
cleanup the existing 1.5-second logout allowance. The focused logout check and
full suite with the original failing seed then passed.

## Native client acceptance

Fresh server on `ac93fa2b`, build-5875 client, Debugwarrior GUID 1 on Programmer
Isle. Native developer commands raised the character to 60, maximized weapon
skills, and learned the DBC `100% Block` test aura, spell 10021. Retaliation
20230 was already known. God mode was not enabled. All equipment, casting,
movement, and target changes used native input; Tidewave probes only read state.

Worn Large Shield 2213 plus Glyph of Deflection 23040 gave block value 30.
Crusader's Shield 10195 with the same trinket gave 58. Weapons were drawn with
the native sheath key, since a sheathed warrior cannot block. The character
stood at `{16256.2, 16343.1, 69.44}`, facing Skeletal Flayer
`17379390991937510292` two yards away. Auto-attack stayed off throughout.

A sampler started before the native Retaliation cast. The player first took
partial blocks with the weak shield, then equipped Crusader's Shield during
the same 15-second Retaliation buff:

| Elapsed ms | Target health | Retaliation charges | Block value | Observation |
| --- | --- | --- | --- | --- |
| 1 | 2,880 | absent | 30 | Before the cast |
| 2,242 | 2,880 | 30 | 30 | Buff active |
| 4,814 | 2,775 | 29 | 30 | First partial block triggers 105 damage |
| 6,121 | 2,683 | 28 | 30 | Next strike deals 92 |
| 7,421 | 2,593 | 27 | 30 | Next strike deals 90 |
| 8,717 | 2,485 | 26 | 30 | Next strike deals 108 |
| 10,027 | 2,277 | 25 | 30 | Next strike critically hits for 208 |
| 10,124 | 2,277 | 25 | 58 | Stronger shield equipped |
| 16,612 | 2,277 | 25 | 58 | Full blocks have not spent further charges |
| 17,285 | 2,277 | absent | 58 | Buff expires |

The client showed each partial block, its following Retaliation damage, and
the decreasing buff charge count. After the shield switch it showed
`Skeletal Flayer attacks. You block.` and the buff retained 25 charges. A
second Flayer attacking from behind continued to damage the player but did
not activate Retaliation. No ordinary player swings occurred.

An ordinary teleport back to the safe area left target zero, auto-attack off,
and no Retaliation holder. No server errors or spell-validation failures
appeared. Only the existing account-data, raid-info, GM-ticket, and
meeting-stone login request warnings occurred. The helper-owned client, Xvfb,
and fresh server were stopped after acceptance.

Absorption, damage shields, attacker-side proc delivery, and incoming proc
cooldowns were verified by automated tests; this native session focused on
Retaliation's partial/full-block behavior, client feedback, and expiry.

## Local evidence

- Session: `/home/pikdum/.cache/thistle-wow-playtest.pn8rFL`.
- Server log: `/tmp/thistle-block-proc-server.log`.
- Owner probes: `/tmp/thistle-block-proc-{equipped,pre-retaliation,after}.txt`.
- Sampler: `/tmp/thistle-block-proc-retaliation-sample.txt`.
- Screenshots: session `screenshots/weapons-drawn.png`,
  `retaliation-partial.png`, and `retaliation-full.png`.
- Gates: `/tmp/thistle-block-proc-{focused,all,compile,credo}.log`.
