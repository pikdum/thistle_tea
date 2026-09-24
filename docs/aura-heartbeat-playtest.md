# Aura heartbeat resistance

Long negative auras now support vanilla's early resistance checks. The spell
loader retains `SPELL_ATTR_HEARTBEAT_RESIST`; Gnomish Mind Control Cap and
Reckless Charge also receive their explicit player-break behavior.

Player recipients and player-controlled creatures sample a logistic break
time, with a median of 12 seconds and the 99th percentile at 15 seconds.
Diminishing returns scale that time. Eligible creature recipients instead
check every five seconds using the caster's snapshotted spell hit chance,
including binary resistance, spell hit modifiers, and penetration. Pets can
receive both checks. Fear, roots, pacify-silence, and confusion exclude the
creature check, matching VMangos. Positive, permanent, and at-most-ten-second
applications before diminishing returns are exempt.

The calculations are pure. Spell reception supplies the initial random
quantile and each due creature roll, including for eligible self-casts.
Refreshes retain the quantile, creature timer, and snapshotted hit chance;
the player deadline restarts with the refreshed duration and current
diminishing-return rate. Channel pushback advances player elapsed time.
The shared aura scheduler and transition funnel handle breaks before
periodic effects, release control, retire caster-limited claims, and start
diminishing-return recovery. Heartbeat removal does not count as expiry.

## References and automated validation

- `refs/vmangos/src/game/Spells/SpellAuras.cpp`: `CalculateHeartBeat`,
  `SpellAuraHolder::Update`, and holder refresh behavior.
- `refs/vmangos/src/game/Spells/SpellMgr.cpp`: `IsPvEHeartBeat` exclusions.
- `refs/vmangos/src/game/Objects/SpellCaster.cpp`: `MagicSpellHitChance`.
- Local DBC flags and effects for Polymorph, Mind Control, Banish, Enslave
  Demon, Hibernate, Fear, Sap, and the two engineering exceptions.

Implementation commit `b49b8376` passed `mix test.all` (5,613 tests),
`mix compile --warnings-as-errors`, `mix credo --strict` (zero issues),
formatting, and whitespace checks. Seventeen added tests cover eligibility,
distribution quantiles, pet ownership, resistance snapshots, refresh and
diminishing returns, scheduling, pushback, control release, claims, death,
dispel, boundary rolls, self-cast delivery, and DBC loading.

## Native client acceptance

A fresh server on the implementation commit served two isolated build-5875
GPU clients. Setup and gameplay used native client input; Tidewave only
read existing state. WoW processes 171786 and 173309 each had their own
amdgpu rendering counters.

Debugmage (GUID 5, level 60) challenged Debugbuyer (GUID 10, level 50) to a
duel on Programmer Isle. Both had god mode off. Polymorph rank 4 (12826)
applied with a 50-second duration and a sampled break delay of 11,380.8 ms.
The 20 ms sampler observed application at 3,785 ms and removal at 15,160 ms.
The owner executed removal approximately three milliseconds after the
stored deadline. Debugbuyer retained 2,819 health throughout, changed from
display 50 to sheep 856 and back, lost the control holder, and started the
15-second diminishing-return recovery clock. Both clients showed the
Polymorph; the recipient returned to the normal model and action bar.

Scaling and refresh behavior have deterministic automated coverage; the
native duel established an undiminished break. Debugbuyer forfeited before
the creature trial.

For Hibernate rank 1 (2637), Debugmage learned the spell and lowered to
level 1, with god mode enabled to survive nearby attacks. The target was
the level-11 Mottled Worg, entry 1766 and low GUID 990900. Its hit snapshot
was 2,300 basis points: the level-difference floor plus the caster's one
percent spell-hit bonus. Impact resists were common, as expected. No hit
or heartbeat rolls were forced.

The final trace recorded two complete applications of the 20-second aura.
The first appeared at 27,076 ms and cleared at 32,078 ms; the second
appeared at 38,820 ms and cleared at 43,822 ms. Both broke on their first
five-second check. Health stayed at 222, and both the aura holder and root
state cleared. Screenshots `hibernate-worg-13.png` and
`hibernate-worg-14.png` show the debuff and sleep effect;
`hibernate-final-break.png` shows the cleared debuff.

Debugmage then returned to level 60, disabled god mode, and transferred to
Northshire. The final owner read found neither player controlled, the Worg
at full health with no aura or root, and no remaining caster-limited claims
for Debugmage. No server errors or spell-validation failures occurred.
Unsupported requests were limited to the existing account-data, GM-ticket,
and meeting-stone login messages.

Both helper-owned client cgroups and the server were stopped, with logs
and screenshots retained. A final read after client shutdown found neither
player owner registered.

## Retained evidence

- Caster session: `/home/pikdum/.cache/thistle-wow-playtest.solcp2/`.
- Recipient session: `/home/pikdum/.cache/thistle-wow-playtest.Y1yMiP/`.
- Player timing: `/tmp/thistle-heartbeat-pvp.txt`.
- Creature timing: `/tmp/thistle-heartbeat-pve-final.txt`.
- Final owner and claim state: `/tmp/thistle-heartbeat-final-state.txt`.
- Logout cleanup: `/tmp/thistle-heartbeat-stopped-owners.txt`.
- Server log: `/tmp/thistle-heartbeat-server.log`.
- GPU evidence: `/tmp/thistle-heartbeat-gpu-{main,peer}.txt`.
- Gates: `/tmp/thistle-heartbeat-{tests,compile,credo}.log`.
