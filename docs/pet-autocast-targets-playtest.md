# Pet autocast recipients

Pet autocast now selects useful recipients from the pet, owner, and the owner's
current party or raid subgroup. The boundary captures that roster and its
observations once per tick. Target choice stays in the behavior tree over the
immutable snapshot. A later subgroup change affects the next snapshot without
changing an already captured one.

Spell target definitions restrict those candidates: caster-only and
caster-master spells keep their designated recipient, party spells use the
captured allies, and area spells require a candidate within the actual effect
radius. Candidates must be alive in the same world and pass ordinary target,
range, line-of-sight, and dispel-polarity validation. Helpful spells that can
also affect enemies try the pet's victim, the owner's victim, and observed
attackers before allies. Harmful autocasts keep the pet's victim.

The target-validation snapshot now retains aura sources, dispel options,
health percentage, power type, and level. The observation radius includes the
pet's spell ranges, so a 30-yard dispel can see an attacker beyond 20 yards.

The source is `PetAI::UpdateAI`, `PetAI::UpdateAllies`, and `Spell::CanAutoCast`
at VMangos revision `8f4e608450460efe1e38743e4da74397d4773a3a`. The existing
spell-list ordering remains deterministic. DBC coverage verifies all Fire
Shield and Devour Magic ranks and their party-member/any-unit targets.

## Bug found during native acceptance

Devour Magic's enemy candidate passed target validation but disappeared in
`SpellTargetResolver`: the spell is not globally classified as harmful, so
its duel opponent was incorrectly filtered as outside assistance. The pet
spent 170 mana repeatedly without removing Arcane Intellect. A read-only
probe confirmed `hostile: true`, `assist: false`, and `resolved: []`.

The shared resolver now also accepts an attackable enemy when a spell's
implicit target is any unit. Tests cover player and pet casters through both
resolution entry points, self/owner assistance, rejected third-party duel
assistance, friendly-only spells, and immunity-to-player flags.

## Native acceptance

Two isolated GPU-rendered build-5875 clients used level-50 Debugwarlock and
Debugbuyer on Programmer Isle. All setup, invitations, casts, pet commands,
and aura cancellations came from the clients. Runtime probes were read-only.
The source did not change during either server run.

- With the imp in passive follow and only Fire Shield rank four enabled,
  an unrelated warrior receiving melee attacks stayed unbuffed. The owner
  was not attacked, and the imp retained its full 1,450 mana.
- After accepting the party invitation, the same warrior received spell
  11770 from imp GUID 17383894568633630805. The first-change sampler recorded
  1,310 mana, follow mode, and no pet victim. The warrior's client displayed
  the Fire Shield icon.
- The warrior left the party and cancelled the buff. Despite retaining an
  attacker, the warrior remained unbuffed. The owner remained unbuffed too.

After the resolver fix, a fresh server and two fresh clients used
Debugwarlock and the mage Debugbidder (GUID 11) in a normal duel. God mode
protected player health. The felhunter remained passive in reaction stance;
a native attack command supplied its combat victim.

- With enemy Arcane Intellect active, enabling Devour Magic rank three
  removed spell 1459 at the sampler's 2,439-ms observation. Pet mana fell
  from 1,391 to 1,221 and the category cooldown lasted 8,000 ms. The mage's
  client lost the buff icon. The rest of the 25-second trace retained that
  same cooldown and recorded regeneration without further casts.
- Teleport restoration replaced felhunter GUID 17383894568650408026 with
  17383894568650408063, retaining autocast 19734 and follow mode. The previous
  process, metadata, and spatial entry were absent.
- In the next duel, Shadow Word: Pain appeared on the owner at 2,325 ms.
  Enabling Devour Magic removed it at 4,572 ms, over 15 seconds before its
  natural expiry. Mana again changed from 1,391 to 1,221 with one eight-second
  cooldown. Before/after screenshots show the debuff disappearing. No enemy
  buff was available, so this exercised the allied fallback.

Devour Magic's zero duration and eight-second recovery make its autocast
combat-only under the shared reference rules. An earlier passive-follow
sample retained the owner's debuff until natural expiry without spending
mana. A separate early attempt used a warrior with a learned mana spell;
the vanilla client rejected it before packet transmission. One later
Shadow Word: Pain attempt resisted normally. The final landed trace above is
the acceptance evidence. Early verbose cooldown probes and a late-started
owner sampler are not used to establish successful removal.

Logout removed the owner and both prior felhunter GUIDs from process lookup,
metadata, and spatial lookup. Reconnect restored follow mode, no victim,
full mana, and autocast 19734 under GUID 17383894568650408092. Final disconnect
removed that pet and both players. All four owned client services ended
inactive/dead, all four WoW processes exited, and both retained server
sessions exited. Ports 4000, 3724, and 8085 were empty. Neither server logged
errors or cast-validation failures; warnings were the existing account-data,
GM-ticket, and meeting-stone opcodes.

GPU evidence used unique DRM client IDs without summing duplicate descriptors:

| WoW PID | DRM client | Graphics counter before | Graphics counter after |
| --- | --- | --- | --- |
| 1657767 | 4767 | 3,645,053,817 ns | 35,621,345,041 ns |
| 1658494 | 4795 | 3,031,550,640 ns | 30,553,363,746 ns |
| 1671059 | 4850 | 2,071,464,010 ns | 19,082,318,309 ns |
| 1671060 | 4851 | 2,141,244,989 ns | 19,930,651,991 ns |

## Validation and evidence

- `mix test.all`: 6,635 passed in 59.2 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Focused resolver and pet target tests: 42 passed.
- `git diff --check` and commit hooks: passed.

One earlier full run overlapped Credo and timed out in the existing concurrent
metadata counter test. The final full run above ran by itself with no source
changes and passed. The architecture dependency allowlist was not expanded.
Automated coverage also checks raid subgroup changes, immutable observations,
line of sight, range, death, other worlds, existing aura effects, both dispel
polarities, manual commands, and area radii.

First-run screenshots are retained in
`/home/pikdum/.cache/thistle-wow-playtest.louzQn/` and
`/home/pikdum/.cache/thistle-wow-playtest.KlebwH/`. Final-run screenshots are in
`/home/pikdum/.cache/thistle-wow-playtest.YWvRzM/` and
`/home/pikdum/.cache/thistle-wow-playtest.JvsAsz/`.

Runtime evidence uses `/tmp/thistle-pet-targets-*`: `ungrouped.txt`,
`party-first.txt`, `party-stable.txt`, `left-party.txt`,
`devour-filter-bug.txt`, `final-devour-enemy.txt`, `final-owner-landed.txt`,
`final-replaced-cleanup.txt`, `final-logout.txt`, `final-reconnected.txt`,
`first-cleanup.txt`, and `final-disconnected.txt`. Final test and check logs
use `/tmp/thistle-pet-targets-filter-*`; server logs are `server.log` and
`final-server.log` under the first prefix.
