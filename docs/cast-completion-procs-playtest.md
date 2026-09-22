# Cast-completion procs

Ordinary casts now emit one caster-owned proc reaction when casting completes,
before projectile impact. Cast-end proc rules no longer act as unconditional
hit rules. They are evaluated separately from later damage and healing
feedback, so area targets and channel ticks cannot repeat the cast-completion
reaction. Channels react when launched, not when the final tick finishes.

Preparation and cancellation leave these procs untouched. A completed cast
can trigger even if all its targets resist. Casts without a selected unit use
the caster as the proc target. Positive item casts are excluded. Existing
spell costs and consumable modifiers are resolved before the new proc can
grant a buff for a subsequent cast.

The shared eligibility checks retain school, family, chance, cooldown, and
charge rules. The loader now recognizes caster-proc suppression independently
of target-proc suppression. Normal-hit and always-trigger rules cannot leak
into the cast-end phase.

Cast classification distinguishes helpful abilities from healing spells and
harmful abilities without a magic damage class from harmful magic spells.
This matters for Darkmoon Card: Blue Dragon: its flags accept Healing Wave
and Lightning Bolt, but exclude Arcane Intellect. Hunter's Mark and Detect
Magic also carry explicit caster-proc suppression.

## References and automated acceptance

Compared against VMangos `8f4e60845`:

- `Spells/Spell.cpp`: `prepareDataForTriggerSystem` and the caster's
  `PROC_EX_CAST_END` reaction before delayed spell delivery.
- `Spells/SpellMgr.cpp`: matching cast-end phases before other proc rules.
- `Spells/SpellDefines.h`: ability/spell proc flags and caster suppression.
- `spell_proc_event`: Elemental Focus 16164 and Blue Dragon 23688 rules.

Default tests cover once-per-cast area delivery, later hit feedback,
preparation and cancellation, fully resisted casts, channel launch/ticks/end,
positive item casts, caster suppression without victim suppression,
targetless casts, and phase separation even with always-trigger flags.

Separate VMangos-tagged tests verify the actual proc restrictions. DBC-tagged
tests verify the real proc chances, trigger spells, Shaman family and school
matching, helpful/harmful classification, and suppression attributes. An
older test that explicitly expected cast-end procs during ordinary hit
feedback was corrected.

Final validation after the spell/ability classification correction:

- Focused checks including DBC data: 182 passed.
- VMangos proc-rule checks: 5 passed.
- `mix test.all`: 4,551 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.

## Native client acceptance

Fresh server on implementation commit `3a63c860`, build-5875 client, Debugmage
GUID 5 on Programmer Isle. Native developer commands raised the character to
60 and taught Lightning Bolt 403 and Elemental Focus 16164. Lightning Bolt
retained its real Shaman family 11, 1,500 ms cast time, and 15-mana base cost;
Elemental Focus retained its real 10% proc chance and school/family rule.
God mode protected the character during repeated casts, so this session does
not establish mana expenditure.

The character started at `{16283, 16343.1, 69.44}`, facing Skeletal Flayer
`17379390991937510292` about 25 yards away. A read-only owner sampler started
before native spell input. A client combat-message listener stopped further
casts after the first Clearcasting announcement; it did not alter server
state. The first Lightning Bolt did not proc. The second did:

| Elapsed ms | Target health | Clearcasting | Cast state |
| --- | --- | --- | --- |
| 5 | 2,980 | absent | idle |
| 2,653 | 2,980 | absent | first cast preparing |
| 4,211 | 2,980 | absent | first cast completed |
| 5,482 | 2,962 | absent | first projectile hit |
| 7,893 | 2,962 | absent | second cast preparing |
| 9,419 | 2,962 | present | second cast completed |
| 9,628 | 2,946 | present | second projectile hit |
| 24,446 | 2,946 | absent | buff expired without another cast |

The owner thus gained Clearcasting 209 ms before the second impact. The
client separately displayed `You gain Clearcasting.` at 158127.47 and the
16-damage Lightning Bolt hit at 158127.61. The buff survived the impact and
expired approximately 15 seconds after application.

An ordinary teleport and target clear returned the character to safety with
no active cast, target zero, the Elemental Focus passive retained, and no
Clearcasting holder. No server errors or spell-validation failures occurred;
only the existing account-data, raid-info, GM-ticket, and meeting-stone login
request warnings appeared. The helper-owned client, Xvfb, and server stopped.

The subsequent classification correction was validated by the final automated
suite. Lightning Bolt remains a harmful magic spell under both classifications.
Blue Dragon's random proc, area/channel behavior, cancellation, and item-cast
exclusion were not separately reproduced in this native session.

## Local evidence

- Session: `/home/pikdum/.cache/thistle-wow-playtest.6iThug`.
- Server log: `/tmp/thistle-cast-proc-server.log`.
- Owner probes: `/tmp/thistle-cast-proc-{ready,after-natural,cleanup}.txt`.
- Sampler: `/tmp/thistle-cast-proc-sample-1.txt`.
- Client evidence: session `screenshots/first-batch.png`.
- Gates: `/tmp/thistle-cast-proc-{focused,vmangos,all,compile,credo}.log`.
