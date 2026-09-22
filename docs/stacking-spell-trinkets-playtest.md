# Stacking spell trinkets

Implemented and tested on 2026-09-21. The native build-5875 client ran against
`dd80db66`, including the temporary spell-power fix in `8e435eee`.

## Behavior and reference

Temporary `mod_damage_done` and `mod_healing_done` auras now contribute to the
caster's spell-power snapshot, including their stack counts and school masks.
Damage auras restricted to weapons or inventory types do not become general
spell power. Direct and periodic effects apply the existing spell coefficients;
already-created snapshots retain their bonus after a buff changes or ends.

Zandalarian Hero Charm, item 19950, applies Unstable Power 24658 and initializes
its bonus aura 24659 at twelve stacks: 204 damage and 408 healing. Each eligible
cast consumes one stack after the initial spell effects have captured their
bonus. The supported damage, healing, periodic, area, and totem casts follow the
reference's filters. Impact feedback does not consume another stack.

Talisman of Ascendance, item 22678, initializes aura 28200 with six charges even
though its DBC charge count is zero. The first five eligible casts apply or
increase aura 28204, adding 40 damage and 75 healing per stack. The sixth cast
uses the five-stack bonus, then removes both holders. Area spells and spells
whose first effect is a script effect are excluded, as in the reference.

The shared aura transition removes linked bonuses when their parent ends,
including expiry, cancellation, consumption, removal, and death. Refreshing a
parent resets its bonus, and a delayed child application cannot recreate the
bonus when its parent is absent. Ascendance's otherwise permanent bonus cannot
outlive the parent's 20-second window.

Reference checkout: `refs/vmangos` at `8f4e60845`:

- `Spells/SpellAuras.cpp`: Unstable Power application/removal, initial maximum
  stacks, Ascendance's six scripted charges, and triggered-aura cleanup.
- `UnitAuraProcHandler.cpp`: Unstable Power's qualifying spell filters and
  Ascendance's area/script exclusions.
- `Objects/SpellCaster.cpp`: flat spell damage and healing aura contributions.
- Supported-build `spell_proc_event` rows: cast-completion proc mask `0x80000`.

## Automated acceptance

`mix test.all` passed all **4,566 tests**. Compilation with warnings as errors
passed, and strict Credo reported zero issues across 1,791 source files.

New coverage includes school and weapon restrictions, coefficient-scaled direct
damage/healing, periodic snapshots, all twelve Unstable Power reductions,
Ascendance's six casts, packed client counts, refresh and removal behavior,
late child delivery, and area recipients capturing the bonus before its one
reduction. DBC tests use the actual trinket and triggering spells; separately
tagged VMangos tests verify their proc rules. An older shield-block fixture now
supplies a valid source spell for its aura holders.

## Native client acceptance

A fresh server and isolated client used Debugmage, GUID 5, at level 60 on
Programmer Isle. The character learned Flash Heal 2061 through `.learn`, obtained
both real items through `.additem`, and equipped them through client inventory
actions. `.modify hp 200` prepared healing tests. God mode was not enabled.
Tidewave probes only read state.

Existing equipment supplied 12 spell damage and 12 healing. Flash Heal's initial
native combat message reported 210 healing. Activating inventory slot 13 sent
`CMSG_USE_ITEM` for Zandalarian Hero Charm. The owner sampler observed:

| Event | Bonus stacks | Total spell damage | Total healing |
| --- | ---: | ---: | ---: |
| Activation | 12 | 216 | 420 |
| First Flash Heal | 11 | 199 | 386 |
| Second Flash Heal | 10 | 182 | 352 |
| Original 20-second expiry | none | 12 | 12 |

The first two heals displayed **415** and **403**. Authoritative health increased
by those amounts at cast completion. Both holders disappeared about 19,957 ms
after the first sample showing activation; neither cast extended the deadline.

Activating inventory slot 14 sent `CMSG_USE_ITEM` for Talisman of Ascendance.
Six action-bar keypresses, spaced 2.2 seconds apart, cast Flash Heal. The sampler
observed charges `6 -> 5 -> 4 -> 3 -> 2 -> 1 -> removed`, with bonus stacks
`0 -> 1 -> 2 -> 3 -> 4 -> 5 -> removed`. Total damage/healing reached **212/387**
before the sixth cast. The native log showed successive Ascendance stack gains,
and the last cast displayed **387 healing** before the bonus disappeared.
The caster reached maximum health on that cast, so its effective health gain
was capped below the displayed heal amount.

The first five heals increased authoritative health by 209, 254, 306, 341, and
340 respectively. Healing rolls and ordinary regeneration mean these values
are not a fixed arithmetic progression. After all six casts, a fresh Flash Heal
displayed **222 healing**, with a new snapshot back at the baseline **12/12**.
The final probe had no active cast or trinket aura; both items remained equipped.

The live run proves item activation, healing, stack growth/reduction, exhaustion,
expiry, and restored spell power. Direct damage, periodic spells, area behavior,
death, and cancellation were covered by automated tests rather than repeated
in this native session. The scope is ordinary cast completion; this change does
not add a separate completion phase to the triggered-spell resolver.

There were no server errors or spell-validation failures. Only the existing
account-data, raid-info, GM-ticket, and meeting-stone login warnings appeared.
The helper-owned client, Xvfb, and server stopped, with evidence retained.

## Local evidence

- Session: `/home/pikdum/.cache/thistle-wow-playtest.q2kNe3`.
- Screenshots: `baseline.png`, `unstable-heals.png`,
  `ascendance-keypress-heals.png`, and `restored-heal.png` in its `screenshots/`.
- Server log: `/tmp/thistle-stacking-server.log`.
- Successful samplers: `/tmp/thistle-stacking-unstable-sample.txt` and
  `/tmp/thistle-stacking-ascendance-keys.txt`.
- Owner probes: `/tmp/thistle-stacking-baseline.txt`,
  `/tmp/thistle-stacking-unstable-expired.txt`, and
  `/tmp/thistle-stacking-cleanup.txt`.
- Gates: `/tmp/thistle-stacking-{dbc,vmangos,all,compile,credo}.log`.
