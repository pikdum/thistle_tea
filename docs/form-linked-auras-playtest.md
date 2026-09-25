# Form-conditioned talent auras

Validated on 2026-09-25 with two native build-5875 clients and the local VMangos
reference at `8f4e60845`.

## Implementation

Talent holders can own linked auras whose stance masks select their active
forms. The boundary preloads the child spells; pure aura transitions activate,
retain, and remove them with their parent. Learning a talent while already
shifted, replacing its rank, changing forms, unlearning, and reconnecting use
the same ownership rules. Ordinary linked effects keep their existing lifetime
rules. The dependency-test allowlist is unchanged.

Heart of the Wild retains its intellect bonus in every form and supplies its
rank's percentage to the Cat strength or Bear stamina child. Leader of the Pack
owns a visible party-area source while in Cat, Bear, or Dire Bear. Its original
spell flags and party refresh behavior are preserved. A linked source replaces
an external copy on its owner, preventing duplicate critical-strike bonuses.

The reference rules are in `Aura::HandleShapeshiftBoosts`,
`Aura::HandleModTotalPercentStat`, `Aura::HandleAuraModIncreaseHealth`, and
`SpellAuraHolder::IsNeedVisibleSlot` in VMangos `SpellAuras.cpp`.

The health transition now distinguishes ordinary maximum-health buffs,
temporary health grants, and proportional form bonuses. Ordinary buffs raise
the ceiling without healing. Last Stand removes its temporary grant when it
ends, leaving an injured living player at least one health. Bear's flat health
bonus preserves the current fraction using ceiling division; ability-flagged
stamina percentages use floor division. Dead players remain at zero health.

Stat percentages use integer ratios through the final truncation, preserving
base/equipment, base-percent, flat-aura, and total-percent ordering. This fixes
the floating-point case where a 16% bonus to 100 intellect produced 115.

Implementation commits: `631b836a` and `6acea624`.

## Native acceptance

Sessions:

- Druid: `/home/pikdum/.cache/thistle-wow-playtest.vcJqER`.
- Party observer: `/home/pikdum/.cache/thistle-wow-playtest.iEshHE`.
- Server log: `/tmp/thistle-form-links-server.log`.

Both sessions used GPU rendering. The actual WoW process graphics counters
advanced from 2,067,137,275 to 6,192,935,293 ns for PID 1040946 and from
1,219,994,120 to 5,696,751,559 ns for PID 1041888.

Debugdruid, level 60, and Debugbidder, level 50, formed a party near Goldshire.
The Druid stood at map 0, `(-9464, 60, 56)` and the observer initially at
`(-9467, 60, 56)`. Native `.learn`, `.talents reset`, `.modify hp`, and `.die`
commands exercised the normal player boundaries. Forms, logout, login, and
movement were driven through the clients. Tidewave probes were read-only.

The Druid's canonical strength/stamina/intellect were `62/69/100`, with equipment
contributions of `26/38/0`. Other active equipment effects bring baseline
stamina to 123. The client character pane and authoritative owner agreed:

| State | Strength | Stamina | Intellect | Relevant talent holders |
| --- | ---: | ---: | ---: | --- |
| Before talents | 88 | 123 | 100 | None |
| Cat, Heart of the Wild rank 1 | 91 | 123 | 104 | Parent 17003, child 24900 at 4% |
| Cat, rank 4 | 102 | 123 | 116 | Parent 17006, child 24900 at 16% |
| Cat, rank 5 | 105 | 123 | 120 | Parent 24894, child 24900 at 20% |
| Dire Bear, rank 5 | 88 | 147 | 120 | Parent 24894, child 24899 at 20% |
| Unshifted, rank 5 | 88 | 123 | 120 | Parent retained; form child absent |
| Cat, talent reset | 88 | 123 | 100 | Parents and children absent |

Ranks were learned while Cat Form was already active. Each replacement left
one current parent and one child, with no previous rank holders. Leader of the
Pack also activated immediately when learned in Cat Form. Its visible buff
appeared on both clients. The observer's critical-strike field rose from
4.902434625789% to 7.902434625789%, with exactly one three-point aura. It stayed
active while the Druid was in Dire Bear and expired after form exit.

Read-only 50 ms samples captured partial-health transitions before regeneration
could obscure them:

| Transition | Before | First transformed state |
| --- | --- | --- |
| Enter Dire Bear with rank 5 | 1,156 / 2,533 health, 123 stamina | 1,831 / 4,013 health, 147 stamina |
| Leave Dire Bear | 2,284 / 4,013 health, 147 stamina | 1,442 / 2,533 health, 123 stamina |

Entry first scales to 1,722 / 3,773 for Bear's flat bonus, then to
1,831 / 4,013 for Heart of the Wild. Exit applies the inverse maximum-health
changes with the reference rounding rules. The client displayed the new
maximum health and stamina without filling the health bar.

Logging out in Cat Form removed the observer's buff. Login restored one Cat
strength child and one Leader source, with stats `105/123/120`, and refreshed
the observer's buff. Walking the observer to
`(-9415.637, 55.489, 59.419)` placed it beyond the 45-yard radius on actual
terrain; the buff disappeared and critical strike returned to baseline.
Returning to the starting position restored it.

Talent reset left Cat Form active but removed both talent parents, their
children, and the observer's buff. Relearning rank 5 and Leader followed by
death removed the form, strength child, and Leader source at health zero.
The intellect and dummy talent parents remained; the observer again returned
to baseline critical strike.

Screenshots include `cat-rank-one.png`, `cat-rank-four.png`,
`cat-rank-five.png`, `bear-heart.png`, `reconnected.png`,
`cat-talent-reset.png`, and `talent-death.png` in the Druid session;
`party-leader-buff.png`, `party-form-exit.png`, `party-logout.png`,
`party-walked-away.png`, `party-range-return.png`, and `party-owner-death.png`
in the observer session. Authoritative probes and health samples are retained
under `/tmp/thistle-form-links-*.log`.

There were no owner crashes, spell-validation failures, or network errors.
Warnings were limited to the existing account-data, GM-ticket, meeting-stone,
and cancel-growth messages. VMangos handles cancel-growth as an empty operation.
Both owned client services and the retained server were stopped after acceptance;
their logs and screenshots remain available.

## Automated checks

- `mix test.all`: 6,211 passed; `/tmp/thistle-form-links-final-tests-2.log`.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Formatting and `git diff --check`: passed.

Regressions cover every Heart of the Wild rank against actual DBC rows, all
three feral forms, rank replacement, parent removal, party-source visibility,
recipient expiry, source deduplication, death/resurrection, shared-mask form
changes, buff capacity, exact stat arithmetic, ordinary health buffs, Last Stand
cleanup, and repeated partial-health transformations. DBC tests have their own
exclusive tag. The final suite ran before native acceptance; only this record
was added afterward.
