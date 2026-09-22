# Extra attacks

Vanilla spell effect 19 now grants a pending batch of main-hand attacks. The
loader previously assigned this behavior to effect 78, which vanilla leaves
unused. The corrected mapping enables the shared effect behind Thrash, Hand
of Justice, Ironfoe, Sword Specialization, Windfury, and Reckoning.

The typed combat blackboard owns the batch. It waits for melee combat with a
live, detectable victim in range and within the vanilla facing arc. Stun,
fear, confusion, and pacification prevent execution. A second grant cannot
overwrite or stack a pending batch. Idle banking survives passive combat
synchronization, but explicit attack stop clears it.

Extra swings use the normal white-attack resolution and client damage
feedback. They can execute during casting, preserve an on-next-swing ability,
and reset the main-hand timer after the batch. They leave the off-hand timer
alone. Later deliveries in a lethal batch cannot damage or proc on a corpse.

An origin flag follows the attack through asynchronous defender feedback,
outgoing aura reactions, triggered spell resolution, and the receiving spell
context. Extra swings can trigger ordinary weapon effects, but cannot create
another extra-attack batch or proc Flurry. Mixed Windfury spells are rejected
before their attack-power aura applies. Weapon restrictions inspect the hand
that hit; off-hand PPM uses that hand's attack time. Creature swings now return
owner feedback, and glancing/crushing outcomes participate in melee procs.

Death, spirit release, combat reset, attack stop, ordinary teleport, logout,
mounting, and starting a taxi flight clear the pending batch through their
existing lifecycle transitions. Ghosts and dead entities cannot receive it.
The new `SMSG_SPELLLOGEXECUTE` encoder reports accepted grants to the owner and
nearby clients with vanilla's extra-attack text.

## References and automated checks

Compared against VMangos `8f4e60845`:

- `SpellEffects.cpp`: effect 19, `EffectAddExtraAttacks`, and execute-log data.
- `Unit.cpp`: update-time batches, attack readiness, casting exception,
  main-hand timer reset, and preservation of queued melee spells.
- `UnitAuraProcHandler.cpp`: extra-attack and Flurry proc restrictions.
- `CombatHandler.cpp` and `Player.cpp`: cancellation and lifecycle cleanup.
- `Server/Packets/Spell.cpp` and `wow_messages`' build-5875
  `smsg_spelllogexecute.wowm`: packed caster GUID, full target GUID, count.

DBC-tagged tests load the actual vanilla extra-attack spells and exercise
recursive rejection in the spell resolver. Default tests cover grant rules,
attack readiness, timer/cast/queue preservation, exact packet bytes, resolved
creature feedback and damage, corpse suppression, weapon restrictions,
Windfury/Flurry suppression, ghosts, death, mounting, taxi, and teleport.

On implementation commit `6430918b`:

- `mix test.all`: 4,520 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.

## Native client acceptance

Fresh server on `6430918b`, build-5875 client, Debugwarrior GUID 1 on Programmer
Isle. The character was raised to 60 through `.character level 60`; `.learn
3391` exposed the real Thrash spell for deterministic banking. Actions went
through native chat/spell/attack input. Tidewave probes only read owner state.

The client displayed `You gain 2 extra attacks through Thrash.` With no victim,
the owner retained two pending attacks and did not send swings. Starting
auto-attack roughly 51 yards from Skeletal Flayer
`17379390991937510292` retained both attacks and left the victim at 2,980 health.

For the measured melee batch, the character stood at
`{16256.2, 16343.1, 69.44}` facing the Flayer at
`{16258.2, 16343.1, 69.4444}`. With auto-attack off, the owner retained two
attacks while the target stayed at 2,059 health. Native `AttackTarget()` then
consumed the batch: the 50 ms sampler observed health drop to 1,857 in one
transition. Subsequent main-hand deadlines and hits were about 2.1 seconds
apart. The client displayed the hit messages and damage numbers.

At safe range, the native Attack spell was toggled on and off with
`CastSpellByName("Attack")`. The server received `CMSG_ATTACKSTOP` and pending
attacks went from two to zero. Banking again and using an ordinary `.go`
teleport also cleared them. Banking two before a full logout, reaching the
character selection screen, and entering again left both the owner and
`CharacterStore` with zero pending attacks.

After reconnecting, `.learn 12787` applied the real 35% Thrash passive and
`.debug skills` maximized the weapon skills. No manual Thrash casts were used
during this phase. Against the restored 2,980-health Flayer, the sampler
recorded ordinary hits, two proc grants, and their consumed batches:

| Elapsed ms | Target health | Pending attacks | Observation |
| --- | --- | --- | --- |
| 0 | 2,980 | 0 | Auto-attack off |
| 1,899 | 2,872 | 0 | First ordinary hit |
| 3,982 | 2,784 | 2 | Next hit procs Thrash |
| 4,171 | 2,584 | 0 | Batch deals 200 damage |
| 18,362 | 1,883 | 2 | Another ordinary hit procs Thrash |
| 18,445 | 1,575 | 0 | Batch deals 308 damage |
| 20,565 | 1,486 | 0 | Next ordinary swing |

The client showed the second proc announcement followed by a 106 hit and a
202 crit, 0.04 seconds apart. Later normal swings resumed on the reset timer;
the batches did not recursively announce further grants. The deterministic
tests separately force rejection of recursive triggers.

No server errors or spell-validation failures appeared. The only warning
types were the existing account-data, raid-info, GM-ticket, and meeting-stone
requests during login. The helper-owned client, Xvfb, and server were stopped
after acceptance.

Vanilla has no `StopAttack()` Lua function. Use the native Attack spell toggle;
the failed initial macro only produced a client Lua error. To select the
nearest Flayer consistently, use `ClearTarget(); TargetNearestEnemy()` while
near it; repeated `/target Skeletal Flayer` can select the other spawn.

## Local evidence

- Session: `/home/pikdum/.cache/thistle-wow-playtest.MWN7Sf`.
- Server log: `/tmp/thistle-extra-server.log`.
- Owner probes: `/tmp/thistle-extra-*.txt`.
- Melee sampler: `/tmp/thistle-extra-melee-sample.txt`.
- Passive-proc sampler: `/tmp/thistle-extra-proc-sample.txt`.
- Screenshots: session `screenshots/banked.png`, `melee-burst.png`,
  `logout.png`, `character-select.png`, and `passive-procs.png`.
- Final gates: `/tmp/thistle-extra-final-{all,compile,credo}.log`.
