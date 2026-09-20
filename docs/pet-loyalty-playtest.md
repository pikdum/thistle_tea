# Hunter pet loyalty

Hunter pets now gain and lose loyalty according to their current happiness.
Every 12 seconds, a happy pet gains 20 points, a content pet gains 10, and an
unhappy pet loses 20. Crossing a rank's upper threshold promotes the pet;
falling below zero demotes it. Rank six rejects gains above its maximum.
Rank changes reset points to the reference core's starting value for that
rank. Newly tamed pets start at rank one with 1,000 points.

Promotions award the pet's current level in training points; demotions remove
the same amount and can create training debt. Each pet level gained awards
another `loyalty rank - 1` points. Eligible XP rewards also award the reference
kill loyalty bonus after leveling. Pets already at their owner-level cap gain
loyalty through time, without a kill bonus. Higher ranks automatically reduce
happiness decay through the existing happiness system.

A rank-one pet whose loyalty falls below zero breaks its bond. The typed
`PetBroke` effect asks the player owner to clear the companion relationship,
send `SMSG_PET_BROKEN`, remove client controls, and stop the pet. Suspension
atomically rejects an already-broken bond, preventing logout or dismissal
from restoring it. Stale notifications cannot remove a replacement pet.

The behavior follows `Pet::ModifyLoyalty`, `TickLoyaltyChange`,
`KillLoyaltyBonus`, `GivePetXP`, `GivePetLevel`, and `GetDispTP` in
`refs/vmangos/src/game/Objects/Pet.cpp`. Packet layout comes from
`refs/wow_messages/wow_message_parser/wowm/world/pet/smsg_pet_broken.wowm`.

`Logic.PetLoyalty` owns the pure transitions. The existing behavior maintenance
step and tick plan schedule loyalty independently from happiness and resource
regeneration. `PetProgress` retains rank, points, and training balance through
dismissal, death, teleport, and reconnect. Death pauses the deadline; restoring
the pet starts a full interval without offline gains or losses. Runtime state
still resets on server restart. Learning and spending points on trained pet
abilities remains a separate system.

## Packet correction and diagnostics

Packed `:two_short` update fields previously occupied only 16 bits despite
consuming a 32-bit update-mask slot. The shared encoder now retains both
halves and the alignment of subsequent fields. Training points use the vanilla
signed display encoding, which the client interprets as total and spent shorts.
A packet regression checks both halves and the following floating-point field.

Developer commands operate on the player's active hunter pet through its owner
process and the normal loyalty or happiness transition:

```text
.debug pet
.debug pet loyalty <delta>
.debug pet happiness <delta>
```

## Real-client acceptance

An isolated build-5875 client controlled Debughunter on Programmer Isle. The
server ran the feature and diagnostic commits. Client commands performed setup,
casts, dismissal, teleport, and logout. Runtime probes only read owner state.

- A happy level-49 wolf retained rank one at exactly 5,500 points. Its next
  timed tick promoted it to rank two, reset points to 4,500, and awarded 49
  training points. The pet panel displayed "Unruly" and "Training Points: 49".
  Happiness decay fell from 8,750 to 4,375 per tick.
- Dismiss Pet stopped GUID 17383894611314868242 and retained rank two,
  4,580 loyalty points, 49 training points, 34,800 XP, and passive stance.
  Call Pet restored those values under GUID 17383894611314868249.
- Two client Death Touch casts on seeded Skeletal Flayers raised the pet
  from level 49 to 50. Training points increased from 49 to 50. Teleport
  retained this progress. The kill sampler crossed a teleport and lost its
  old process; the completed level transition was checked separately.
- Logout retained rank two, 4,738 loyalty points, 50 training points, level
  50, and zero XP. Login restored those exact values under a new GUID,
  preserving passive stance and learned abilities. The client pet panel
  displayed the retained rank and 50 training points.
- The diagnostics made the pet unhappy and lowered loyalty below zero.
  Demotion reset rank one to 2,000 points and removed 50 training points.
  The client showed "Rebellious" and zero training points. Subsequent real
  ticks continued subtracting 20 loyalty points.
- With rank-one loyalty adjusted to exactly zero, the pet remained until
  the next unhappy tick. That tick cleared the companion, stopped GUID
  17383894611314868264, and removed the portrait and action bar. Call Pet
  could not restore it. Logout stored an empty companion relationship.

Automated tests additionally cover every rank threshold, all happiness tier
boundaries, delayed and duplicate tick callbacks, training debt, multi-level
growth, the maximum rank, dead and non-hunter pets, death/revival scheduling,
private field projection, missing owners, stale messages, and suspension
racing a broken bond. Death/revival loyalty retention was tested automatically,
not exercised in this client run.

The server emitted no error-level logs. The client and server were stopped.
The final shared packed-field correction has packet regression coverage; the
pet's 32-bit training payload is identical to the live build's payload.

Evidence is retained in `/tmp/thistle-loyalty-server.log`,
`/tmp/thistle-loyalty-{promotion,dismissed,recalled,logged-out,reconnected,demotion,runaway,runaway-cleanup,broken-stored}.txt`,
and `/home/pikdum/.cache/thistle-wow-playtest.SHPpHu/screenshots/`.

## Final validation

- `mix test.all`: 3,601 passed, including DBC, VMangos, and map integration.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Logs: `/tmp/thistle-loyalty-final-{tests,compile,credo}.log`.
