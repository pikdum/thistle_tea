# Feign Death resistance and lifecycle

Feign Death now checks current hostile creature references within each creature's
level-adjusted detection distance. A spell miss from any eligible creature
resists the entire attempt. Player-controlled opponents, stale incarnations,
dead creatures, and opponents outside the current world or detection distance
are excluded. Improved Feign Death uses the existing spell-hit modifier rules.

The aura retains its result. Both outcomes stop the hunter's attacks and show
the death pose. Success clears threat and combat, interrupts incoming casts,
and prevents direct NPC targeting for the aura's lifetime. Player-controlled
attacks, helpful spells, and area damage remain possible. Failure sends
`SMSG_FEIGN_DEATH_RESISTED` and retains combat and threat. Neither outcome
changes the authoritative alive state or borrows Vanish's temporary immunity.
A fighting pet with a victim retains the hunter's combat flag for six seconds.

The implementation follows `Aura::HandleFeignDeath` in
`refs/vmangos/src/game/Spells/SpellAuras.cpp`, `Unit::SetFeignDeath` and
`Unit::IsTargetableBy` in `refs/vmangos/src/game/Objects/Unit.cpp`, and
`Creature::GetAttackDistance` in `refs/vmangos/src/game/Objects/Creature.cpp`.
The packet has an empty payload and opcode `0x2B4`.

## Automated verification

After the final code change, all 5,691 tests passed with `mix test.all`.
Compilation with warnings as errors, strict Credo, formatting, and whitespace
checks also passed.

Deterministic tests cover resistance thresholds and real DBC talent ranks,
reference eligibility, self-cast routing through recipient preparation,
retained aura context, pet combat expiry, incoming-cast interruption, direct
versus area targeting, refresh, movement, expiry, death, and owner-local packet
delivery. Player metadata is published through `World.Presence`; the dependency
allowlist was not expanded.

## Native acceptance

All setup and gameplay used an isolated build-5875 client and native client
commands. Tidewave read existing owner state and sampled transitions. God mode
was off. The client used hardware OpenGL; WoW PID 241676 had its own amdgpu
graphics counter, increasing from 1,753,780,299 to 7,579,575,418 ns.

On open map 451, level-50 Debughunter (GUID 7) stood 4.5 yards from the seeded
Defias Thug at `{16328.2, 16298.1, 69.4444}`. This spawn rolled level 3 and
71 maximum health. With the pet dismissed, the hunter began in combat at
2,328 health and held the thug's hostile reference. Casting Feign Death
produced the visible death pose and the client combat-exit message. The
hunter's references emptied, the thug's victim and threat cleared, and both
left combat. Metadata continued to report the hunter alive. The pose and
protection remained through the final sample, 13.38 seconds after application,
while the hunter regenerated to 2,352 health. The adjacent thug did not
reacquire the hunter.

A native movement key removed the pose and protection. The thug reacquired
the hunter 678 ms after the sampled aura removal and resumed dealing damage.

At level 40, the hunter approached a level-50 Skeletal Flayer. Feign Death
naturally resisted: the client displayed red "Resisted" feedback and incoming
87-point damage. Owner inspection retained the resisted aura, dynamic death
flag, and combat, with health eventually down to 106. The flayer subsequently
killed the hunter before the attempted retreat completed. Actual death removed
the aura and Feign Death protection. After logout, the owner and metadata were
absent and the stored character had no feign aura or dynamic death flag.

A fresh server repeated the resisted trial without a pet. The complete trace
recorded the resisted holder at 1,505 health with one hostile reference, combat
active, and no NPC-targeting protection. After 1.19 seconds, health fell to
1,393 with the same holder, pose, victim, and reference. Movement removed the
aura 4.57 seconds after its application. Following retreat, the flayer reset
and the hunter's reference and combat flag cleared. The hunter survived.
Health was restored with the native developer command before this attempt;
the spell outcome was not forced.

A final fresh-server trial kept the pet fighting a Skeletal Flayer. The first
attempt exposed a missing live victim field in pet metadata; the owning mob
boundary now publishes it, with a regression test. After that fix, Feign Death
succeeded and retained the hunter's combat flag while the pet fought. The
sampled combat flag cleared 6.85 seconds after application, when a player tick
processed the six-second deadline; the client displayed "Leaving Combat".
The hunter stayed
at 2,352 health throughout the feign, retaining the death pose and NPC protection
until movement removed them. Logout removed the owner and metadata; the stored
character had no feign aura, death pose, combat flag, or active summon.

The initial server logged a module-unavailable error during live recompilation
of the companion changes. Neither fresh-server follow-up logged an error.
Existing unimplemented account-data, ticket, and meeting-stone packet warnings
remain. Native checks covered the scenarios above; incoming-cast interruption,
player-controlled attacks, and area targeting were covered by automated tests.

## Dismissal follow-up

Native testing exposed a separate pet lifecycle bug: teleporting restored an
explicitly dismissed hunter pet. The retained companion now records whether
automatic restoration is intended. Dismiss Pet disables it; temporary travel
suspension preserves it; Call Pet enables it again. Identity and progression
remain retained. VMangos distinguishes explicit dismissal with
`PET_SAVE_NOT_IN_SLOT` in `Spell::EffectDismissPet`.

On the fresh server, Dismiss Pet removed the pet process and bar. Teleporting
left summon GUID zero, the retained pet number `4194354`, and automatic
restoration disabled. Logout removed the player owner; reconnect retained the
same dismissed pet and showed no pet bar. Call Pet then restored the pet with
the same identity and enabled automatic restoration again.

## Artifacts

- Initial client: `/home/pikdum/.cache/thistle-wow-playtest.bvEcah`.
- Follow-up client: `/home/pikdum/.cache/thistle-wow-playtest.boI2ES`.
- Follow-up server log: `/tmp/thistle-feign-followup-server.log`.
- Final pet-combat server log: `/tmp/thistle-feign-pet-server.log`.
- Complete follow-up traces: `resist-complete-trace.txt` and
  `pet-combat-corrected-trace.txt` in the follow-up client directory.
- Follow-up WoW PID 249360 also used amdgpu; its graphics counter increased
  from 6,395,682,038 to 16,835,674,519 ns.
- Initial server log: `/tmp/thistle-feign-server.log`.
- All playtest clients and servers were stopped; artifacts were retained.
