# Avoided ability power refunds

Avoided abilities now refund the power cost captured when the cast actually
pays. Normal casts and queued melee attacks carry the same typed `PowerCost`
through delivery and defender feedback to the caster's owner. Consuming a
charged cost modifier before that feedback arrives cannot change the refund.

Spells with `discount_power_on_miss` return 82% of that cost, rounded to the
nearest internal power unit:

| Power | Refunded outcomes |
| --- | --- |
| Energy | Miss, dodge, parry, immunity |
| Rage | Dodge, parry |

Free and triggered casts cannot generate power. Mana abilities receive no
refund from this flag. Multi-effect melee abilities produce one attack
outcome. Initial channel delivery carries its paid cost; later ticks do not
reuse it. Ordinary casts now recheck affordability at launch, preventing a
power drain during windup from producing an unpaid, refundable hit.

The previous blanket 80% finisher refund was removed. Vanilla Eviscerate and
Ferocious Bite lack the discount flag; avoided finishers keep their combo
points and spend their full cost. Successful finisher consumption is unchanged.

Reference: VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`src/game/Spells/Spell.cpp`, the refund switch after target hit resolution and
`Spell::TakePower`. DBC tests check builder, rage ability, and finisher flags.

## Native acceptance

Two isolated build-5875 GPU clients ran the implementation committed as
`56f93511`. Debugrogue (GUID 3) and Debugpaladin (GUID 2) dueled on Programmer
Isle at `{16300, 16300, 69.44}` and `{16302, 16300, 69.44}`. All gameplay
actions used native input; Tidewave only sampled existing owner state.

- Sinister Strike 11293 into Divine Shield 1020 changed energy from 100 to
  92, matching a 45-energy payment and a rounded 37-energy refund. The
  paladin retained 2,596 health. The client displayed `Immune` and zero
  combo points.
- A successful Sinister Strike established one combo point. After waiting
  for Divine Shield's normal cooldown, Eviscerate 11299 into immunity changed
  energy from 100 to 65 and retained that point. The client printed
  `Energy=65 Combo=1`. The 20 ms owner sampler independently recorded those
  values while shield 1020 was active and the paladin retained 2,596 health.
  Subsequent samples showed ordinary regeneration to 85 and 100, without
  an intermediate refund.
- After the shield expired, another builder raised the total to two points.
  A successful Eviscerate spent 35 energy, damaged the paladin, and consumed
  both points through the returning owner feedback. The sampler captured
  energy 65 before ordinary regeneration and points changing from two to
  zero. The client also reported zero points.

An earlier finisher attempt was invalidated by overlapping helper input
while entering a client diagnostic. It opened UI panels and cast Kick.
`immune-finisher.png` and `finisher-sample.txt` record that discarded attempt;
the `immune-finisher-confirmed.png` screenshot and `finisher-confirmed.txt`
probe record the valid repeat. The initial builder screenshot's chat value
was printed after regeneration; its refund amount comes from the owner
sampler, not that delayed diagnostic.

## Automated acceptance

- `mix test.all`: 6,835 passed in 76.7 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues; formatting and pre-commit checks passed.

Coverage includes flat and percentage charged discounts, Clearcasting,
triggered casts, full immunity, multi-effect misses, finisher point retention,
unaffordable launches, eligible and ineligible outcomes, and queued Heroic
Strike payment. Integration tests follow cast launch, defender resolution,
the event sink, and the actual player-owner feedback callback.

Runtime and checks used
`NAMIGATOR_SRC=/nix/store/3nds85i5fyjgpqcgjnk03fdfgs798vfn-namigator-with-wmo-metadata`.

## Retained evidence

Client directories use `/home/pikdum/.cache/thistle-wow-playtest.` plus the
session suffix below; screenshots are in `screenshots/`. Both WoW processes
had increasing `amdgpu` graphics counters in their own `/proc/PID/fdinfo`.

| Session | Character | WoW PID | Graphics start (ns) | Graphics end (ns) |
| --- | --- | --- | --- | --- |
| `ZfUzd9` | Rogue | 1955418 | 10,820,473,236 | 22,319,180,481 |
| `c4ytrE` | Paladin | 1956413 | 10,112,299,184 | 21,924,891,492 |

Successful screenshots are `immune-builder.png`,
`immune-finisher-confirmed.png`, and `successful-finisher.png` in the rogue
session. Probe and log paths start with `/tmp/thistle-ability-refunds-`:
`builder-sample.txt`, `finisher-confirmed.txt`, `hit-finisher.txt`,
`server.log`, `all.log`, `compile.log`, and `credo.log`.

The server log contains no errors or gameplay warnings. Existing unsupported
account-data and GM-ticket requests were the only warnings. Automated tests
cover charged discounts, triggered casts, and rage refunds; those cases
were not repeated through native clients.

The rogue forfeited and both characters logged out. Both GUIDs then had no
registered owner, position, or metadata. The helper stopped the recorded
service invocations `a45c39f99a60413c99c6ec40fb4a9e47` and
`bef571120c99406f9a5b5fcaf9cdf322`; both units became inactive with empty
cgroups and both WoW PIDs were absent. The retained server PTY exited, and
ports 4000, 3724, and 8085 were free. All evidence was retained.
