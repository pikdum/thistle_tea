# Explicit spell group acceptance

Spell groups now enforce exclusive buffs and ordered upgrades beyond the
existing spell-family categories. Stronger scrolls and elixirs replace weaker
ones. A rejected downgrade preserves the existing holder and deadline, and
positive single-target casts fail before spending items, power, or cooldowns.
Named food bonuses such as Grilled Squid now conflict with Well Fed through
their explicit group membership.

`World.Loader.SpellGroup` preloads build-5875 membership and stacking rules
into ETS. `Spell.StackRules` compiles build ranges, nested groups, rank-root
membership, rule 1 exclusivity, and rule 3 ordered upgrades. The current
snapshot has 380 membership rows across 63 groups. Cast validation reads
existing aura-source projections; recipient application checks conflicts
before changing holders. Existing aura transitions own removal, derived
stats, client projection, expiry, and death. There are no gameplay database
queries, new protocol messages, or architecture allowlist entries.

Reference: VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Spells/SpellMgr.h` group comparisons, `SpellMgr.cpp` group and priority
loading, `Objects/Unit.cpp` aura replacement and stronger-spell checks, and
`Spells/Spell.cpp` preflight validation. Trigger parent/child relationships,
passive and hidden holders, same-chain handling, exact weaker spell IDs, and
the first common non-default group preserve the reference's distinctions.

## Native stacking acceptance

An isolated build-5875 GPU client ran against `8a88469e`. Debugbidder
(GUID 11, human mage) was raised to level 60 on Programmer Isle, map 451.
Baseline Strength, Agility, Stamina, and Spirit were 30, 35, 116, and 150.
Native developer commands granted items and spells; all gameplay mutations
used client input. Tidewave probes were read-only.

- Scroll of Strength (8118) raised Strength to 35. Scroll of Strength IV
  (12179) replaced it and raised Strength to 47. Retrying the lower scroll
  displayed “A more powerful spell is already active.” Its count stayed at
  two, and the stronger holder's application time, expiry, and cooldown
  stayed unchanged. See `scroll-rejected.png`.
- Arcane Elixir (11390) was replaced by Greater Arcane Elixir (17539).
  Retrying the weaker elixir produced the same native error, preserved both
  item counts at two, and left the stronger holder's deadline unchanged.
  The authoritative fire spell-power bonus was 47: 12 from equipment and
  35 from the replacement elixir. See `elixir-rejected.png`.
- Grilled Squid granted Increased Agility (18192) after ten seconds,
  raising Agility to 45. Tender Wolf Steak subsequently granted Well Fed
  (19710), removing Increased Agility: Agility returned to 35 while Stamina
  and Spirit became 128 and 162. The scroll and elixir remained active.
  Each food consumed one item. See `squid-buff.png` and `food-replaced.png`.
- Power Infusion (10060) increased the cast's combined damage multiplier
  to 1.2. Arcane Power (12042) replaced it with 1.3. Natural expiry restored
  1.0 without returning Power Infusion. The 100 ms sampler observed these
  transitions at 3,661, 7,109, and 22,038 ms. A subsequent Power Infusion
  attempt hit its client cooldown; it is not evidence of group rejection.
- Normal logout removed the owner, metadata, and world position. Reconnect
  created a new owner and retained the scroll, elixir, and Well Fed with
  exactly the same application and expiry timestamps, derived stats, and
  all six item counts. Native `.die` then removed all three buffs, restored
  baseline stats, and left item counts unchanged. No replaced buff returned.
  See `reconnected.png` and `death-cleanup.png`.

An initial setup attempt used Scroll IV at level 50, below its level-55
requirement. The accepted sequence began after raising the character to 60,
cancelling the preliminary lower scroll, and replenishing it to three.

## Damage-field follow-up

The elixir check exposed a projection bug: casts used 47 fire spell power
while the player field still contained the equipment-only value of 12.
Commit `2967a916` introduces pure `Logic.SpellPower` calculations shared by
cast snapshots and player fields. Aura transitions, equipment changes, and
level-stat application recompute flat bonuses, signed penalties, and school
percentages. Canonical equipment and aura inputs prevent accumulation.

The reference is `SpellAuras.cpp` `HandleModDamageDone` and
`Player.cpp` `UpdateDamageDonePercent`. Weapon restrictions exclude
weapon-specific magic bonuses from general spell fields; physical flat
display retains its separate reference behavior. Each negative school field
has its original private wire offset and signed value encoding.

A fresh isolated client ran against `2967a916`. Native elixir use produced
32 and then 47 in both the cast snapshot and player field. Retrying the
weaker elixir preserved its count, the stronger holder, and 47 spell power.
Build 5875 has no `GetSpellBonusDamage` Lua API, so those numeric flat-bonus
checks use owner state and automated packet-field assertions. Native buff
icons and rejection feedback were also checked.

Berserking (23505) supplied the native percentage check: `UnitDamage`
returned `1.2999999523163`, matching 1.3 in both physical and fire player
fields and the cast snapshot. Arcane Power uses spell-effect modifiers and
correctly leaves this general percentage field at 1.0.
Berserking's natural expiry removed its icon and restored the native
multiplier, both school fields, and cast multiplier to 1.0 while retaining
47 spell power. See `berserking.png` and `berserking-expired.png`. A longer
Tidewave sampler hit the CLI HTTP timeout; the retained before/after probes
and native screenshots establish expiry without claiming its exact tick.
Logout removed the owner and presence projections. Reconnect created a new
owner with the same elixir deadline, both item counts at two, and 47 in the
player field and cast snapshot. Native `.die` removed the elixir and restored
both values to the equipment baseline of 12. See `reconnected.png` and
`death.png` in the follow-up session.

## Automated checks

- `mix test.all`: 6,777 passed in 62.9 seconds on the final implementation.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2,453 source files.
- Focused damage-field checks: 42 passed; formatting and pre-commit checks passed.

Coverage includes cross-caster replacement, atomic rejection across multiple
groups, retained costs through `CMSG_USE_ITEM`, foreign-target preflight,
AoE and harmful recipient validation, cyclic subgroup expansion, rank-root
inheritance, build selection, and lifecycle cleanup. Separately tagged
VMangos and DBC tests verify actual food, scroll, elixir, blessing, shout,
and spell-power group data. Projection tests cover stacks, restrictions,
signed private fields, multiplicative percentages, equipment resync,
spirit-derived bonuses, expiry, and death. Native acceptance does not claim
multiple casters, every group member, or the synthetic subgroup cases.

Build and runtime used
`NAMIGATOR_SRC=/nix/store/3nds85i5fyjgpqcgjnk03fdfgs798vfn-namigator-with-wmo-metadata`.

## Retained evidence

Client sessions and their `screenshots/` directories:

- Stacking: `/home/pikdum/.cache/thistle-wow-playtest.JPAd7f`.
- Damage fields: `/home/pikdum/.cache/thistle-wow-playtest.5jPkul`.

Stacking evidence uses `/tmp/thistle-spell-groups-`: `server.log`,
`baseline.txt`, `scroll-low.txt`, `scroll-high.txt`, `scroll-rejected.txt`,
`elixir-low.txt`, `elixir-high.txt`, `elixir-rejected.txt`, `elixir-damage.txt`,
`squid.txt`, `steak.txt`, `power-trace.txt`, `before-logout.txt`,
`logout-presence.txt`, `reconnected.txt`, `death.txt`, and `cleanup.txt`.
GPU counters and gate logs use the same prefix.

Damage-field evidence uses `/tmp/thistle-spell-power-display-`:
`server.log`, `low.txt`, `high.txt`, `berserking.txt`, `expired.txt`,
`logged-out.txt`, `reconnected.txt`, `death.txt`, and `cleanup.txt`, plus GPU
counters and gate logs.

Stacking WoW PID 1860717 used AMD DRM client 5625; its graphics counter
advanced from 2,504,256,678 ns to 18,179,263,932 ns. Duplicate descriptors
were counted once. The stacking helper stopped its matching service
invocation `a9b82f17903741788fb2e4efbd12859a`; its unit became inactive with
an empty cgroup. Its server PTY exited, both owned PIDs were absent, and
ports 4000, 3724, and 8085 were free before the follow-up run.

Follow-up WoW PID 1871472 used AMD DRM client 5654, advancing from
1,070,060,893 ns to 15,500,205,191 ns. Duplicate descriptors were counted
once. Both server logs had no errors. Expected `aura_bounced` rejections
and existing unsupported account-data, ticket, and meeting-stone requests
were the only warnings.
The follow-up helper stopped matching invocation
`3060f03b321343f18f924cf4f3c71650`; the unit became inactive with an empty
cgroup. The player was absent from owner, metadata, and world projections.
Its server PTY exited, both owned PIDs were absent, and ports 4000, 3724,
and 8085 were free. All artifacts were retained.
