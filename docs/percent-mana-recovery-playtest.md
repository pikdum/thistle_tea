# Percentage mana recovery

Aura 21 (`obs_mod_mana`) now restores a percentage of maximum mana on each
periodic tick. This enables Harvest Nectar, Winter Veil Eggnog, holiday candy,
Graccu's Mince Meat Fruitcake, Festival Dumplings, Refreshing Red Apple,
Fel Energy, and Resurgence. Foods with both health and mana effects now
restore both resources.

The implementation uses the shared aura application, scheduling, transition,
resource, and effect projection paths. It preserves explicit amplitudes and
defaults missing mana-recovery amplitudes to one second. Each tick reads the
current maximum mana, accounts for stacks, clamps negative percentages, and
caps recovery at maximum mana. Underlying mana can recover while another
power type is active. Client logs use aura type 21 and mana power type 0.

The behavioral references are `Aura::HandleAuraModTotalManaPercentRegen`, the
`SPELL_AURA_OBS_MOD_MANA` periodic case in
`refs/vmangos/src/game/Spells/SpellAuras.cpp`, and `Unit::SendPeriodicAuraLog` in
`refs/vmangos/src/game/Objects/Unit.cpp`. Percentage recovery generates half
the actual mana gained as assistance threat, matching that periodic case.
Amounts use the project's deterministic integer truncation rather than
VMangos random dithering.

## Lifecycle fix

Testing exposed two shared periodic-processing bugs. Already-dead units
caused the scheduler to discard advanced deadlines, leaving retained passive
auras overdue. A healing effect later in the same holder could also run after
an earlier effect killed the target. Resource-changing periodic effects now
skip dead units while advancing their deadlines; the reducer distinguishes
an existing corpse from a death occurring during the current tick.

## Automated acceptance

Tests cover players and creatures, current maximum mana, stacks, missing and
explicit amplitudes, refresh cadence, clamping, resource switching, delayed
updates, expiry, cancellation, seated interruption, death, effective threat,
and the periodic-log packet. DBC-tagged tests exercise all seven spells that
use aura 21, including the four-second Fel Energy and three-second Resurgence
ticks. Regressions cover eight kinds of retained periodic resource effects
and a lethal damage/healing/recovery combination within one holder.

## Real-client acceptance

An isolated build-5875 client controlled level-50 Debugwarlock on Programmer
Isle, with 2,059 maximum health and 3,628 maximum mana. Existing `.additem`,
`.modify hp`, and `.modify mana` commands prepared the scenario. Item uses,
standing, movement, and `.die` all entered through the client. Tidewave
probes only read the player owner and inventory.

- Fruitcake use consumed one item, seated the player, and applied spell
  25990. Each full tick restored 102 health and 181 mana, alongside separately
  observable natural regeneration. The client displayed the buff and full
  resource bars. At 20 seconds the aura expired and its deadline became nil.
- A second fruitcake use consumed one item. Pressing X removed the aura and
  deadline immediately; later mana changes were only the ordinary 39-point
  regeneration ticks.
- Harvest Nectar consumed one item and applied spell 24355. It restored
  72 mana per second. Pressing W removed the aura and deadline, leaving
  ordinary regeneration.
- A final fruitcake use was interrupted by `.die`. Health became zero, mana
  remained at 2,303 for the rest of the sample, the recovery aura disappeared,
  and its deadline became nil. The client displayed the release-spirit prompt.

Stacking, changed maxima, refresh, explicit cancellation, non-mana active
resources, and the retained-passive regressions were verified by automated
tests. A second observer client was not used.

No owner errors or cast-validation failures occurred. Login emitted existing
account-data, raid-info, GM-ticket, time-query, and meeting-stone unsupported
message warnings. The helper-owned client and retained server were stopped.

## Evidence

- Runtime samples: `/tmp/thistle-percent-mana-client-{expiry,stand,drink,death}.txt`.
- Server log: `/tmp/thistle-percent-mana-server.log`.
- Screenshots: `/home/pikdum/.cache/thistle-wow-playtest.tXB3a2/screenshots/`.
- Final checks: `/tmp/thistle-percent-mana-final-{tests,compile,credo}.log`.

Final validation: `mix test.all` passed 3,228 tests,
`mix compile --warnings-as-errors` passed, and `mix credo --strict` found no
issues.
