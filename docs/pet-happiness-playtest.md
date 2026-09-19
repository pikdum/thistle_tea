# Hunter pet happiness

Hunter pets now deal 75%, 100%, or 125% damage according to their happiness.
The thresholds are 333,000 and 666,000, with a capacity of 1,050,000 and
166,500 initial happiness. Feeding, dismissal drains, timed decay, and death
all use the same pure resource transition and recompute damage from canonical
weapon inputs. The multiplier applies to ordinary attacks, physical and magic
abilities, and periodic damage; feeding and healing are not multiplied.

Happiness decays every 7.5 seconds, using the VMangos loyalty-dependent amount
and 1.5 combat multiplier. Newly created pets start at Rebellious loyalty.
Loyalty progression and automatic desertion are not implemented by this change.
Death removes 333,000 happiness outside battlegrounds, once through the mob
death funnel. A corpse does not continue ticking happiness.

The player's companion relationship retains happiness and death state in the
existing runtime store. Dismissal and logout atomically stop and snapshot the
pet owner, preventing a queued final update from being lost. Notifications
from replaced pets or completed player sessions are ignored. Call Pet cannot
resurrect a dead pet, login leaves it dead, and Revive Pet restores the spell's
health percentage. Server restart still resets all runtime characters.

## Bugs fixed during implementation

- The generated CreatureFamily database named a skill-line column
  `pet_food_mask`. The schema now maps the actual family diet column; wolves
  accept meat, and representative other family diets have DBC coverage.
- Feeding retained the DBC base die when overriding the happiness amount,
  granting 35,001 instead of 35,000 per tick. The override now sets an exact
  amount.
- Pet owners were filtered out of their own pet's private damage fields, so
  `UnitDamage("pet")` read zero. Recipient projection now includes those fields
  for the summoner while preserving other recipients' filtering.
- Pet-name responses used the current time instead of the published name
  timestamp. They now return the matching timestamp and validate pet numbers.
- Hunter pet base damage included attack power twice after recomputation.
  Canonical weapon inputs now exclude that contribution before recompute.
- Call Pet, Revive Pet, and login previously recreated dead pets at full
  health. Death is retained, casting validates it, and revival uses the DBC
  amount. Fresh mob regeneration deadlines prevent an immediate heal on the
  first AI tick.

## Client acceptance

An isolated World of Warcraft 1.12.1 build-5875 client controlled level-50
Debughunter and its Prairie Wolf Alpha on Programmer Isle. DevSeed now gives
the hunter 20 Roasted Quail. Gameplay actions used ordinary client spell casts,
food selection, combat, dismissal, logout, and login. Tidewave probes were
read-only; developer teleport and god mode positioned the character for the
lethal combat check.

- Feeding consumed one quail per cast, displayed the feeding aura, and crossed
  the unhappy, content, and happy tiers. Client diagnostics displayed 75%,
  100%, and 125%, with minimum damage 31.696875, 42.2625, and 52.828125,
  respectively. Authoritative maximum damage was 39.965625, 53.2875, and
  66.609375. The feeding aura expired normally.
- Dismiss Pet preserved 921,530 happiness after its 50,000 penalty and one
  8,750 decay tick from a 980,280 snapshot. Call Pet restored the relationship
  and damage tier under a new entity GUID. Disconnect also retained the final
  happiness, with no offline decay.
- In the death sampler, the Devilsaur reduced health from 2,215 to 1,017 to
  9 to zero. Happiness changed exactly once from 717,750 to 384,750. The pet
  owner stopped, its world position disappeared, and the companion became
  suspended with `dead?: true`.
- Call Pet displayed "Your target is dead". Logout/login preserved 384,750
  happiness and the dead state without creating another pet. Revive Pet then
  cleared the dead state and retained happiness. Casting it on a living pet
  was rejected.
- After fixing regeneration initialization, a final fresh-server combat death
  and revival returned the pet at 332 of 2,215 health, the spell's rounded-down
  15%. The client showed the low health bar and resurrection visual; the
  100-ms sampler recorded 332 before any regeneration heal.

The default automation client and, later, the separate durability client copy
stopped responding after a server restart, showing an unknown pet name and
repeated pet-name requests. Investigation exposed the timestamp mismatch
above. The earlier feeding, death, and reconnect sequence completed normally
in the durability copy. With the timestamp fix, that same copy loaded the pet
name immediately after a fresh server restart and remained responsive for the
final combat, revival, and logout sequence.

No gameplay owner or network errors occurred in the final acceptance server
log. Ordinary UI requests for existing unimplemented account-data, raid-info,
GM-ticket, time-query, meeting-stone, and cancel-trade features remain outside
this change.

Battleground exemptions, loyalty-dependent and combat decay, exact threshold
boundaries, clamping, periodic and direct spell multipliers, stale messages,
and recipient filtering have automated coverage. A second observer client
was not used.

## Evidence

- Tier and dismissal screenshots: `/home/pikdum/.cache/thistle-wow-playtest.XhHGGb/screenshots/`.
- Death and reconnect screenshots: `/home/pikdum/.cache/thistle-wow-playtest.0dOWaG/screenshots/`.
- Final name and revival screenshots: `/home/pikdum/.cache/thistle-wow-playtest.jZW4jV/screenshots/`.
- Client copy: `/storage/games/Thistle-durability-playtest.IkYoZm`.
- Tier/dismissal probes: `/tmp/thistle-happiness-{first-food,happy,before-dismiss,dismissed,recalled}.txt`.
- Death/reconnect probes: `/tmp/thistle-happiness-final-{death-samples,dead,cleanup,dead-logout,dead-reconnected,revive-samples}.txt`.
- Server logs: `/tmp/thistle-happiness-{acceptance,final,verified}-server.log`.
- Final server log: `/tmp/thistle-happiness-complete-server.log`.
- Final revival and logout probes: `/tmp/thistle-happiness-complete-{revive-samples,logout}.txt`.
- Final checks: `/tmp/thistle-happiness-final-{tests,compile,credo}.log`.

`mix test.all` passed all 3,430 tests, `mix compile --warnings-as-errors`
passed, and `mix credo --strict` reported no issues. All helper-owned clients
and retained local servers were stopped; logs and screenshots remain.
