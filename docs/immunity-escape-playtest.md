# Immunity escapes and debuff purging

Immunity spells can now escape matching existing controls at cast admission
and launch. School immunity removes matching harmful auras through the normal
aura transition, including root/fear cleanup and periodic tick cancellation.
Helpful auras, other schools, and spells marked `no_immunities` survive school
purges. The immunity unit flag is derived from active eligible holders, so
overlapping protection, expiry, cancellation, and death use the same owner.

`Spell.Immunity` describes purging school, mechanic, dispel, and state grants.
`Spell.CasterState` owns caster-control validation for both admission and
launch. Triggered casts and explicit restriction bypasses remain supported.
`Logic.EffectImmunity` uses the same grants against actual holder effects.
No new boundary dependencies, database queries, or timers were introduced.

The change also fixes Blink under simultaneous stun and silence, and prevents
Ice Block's self-stun from interrupting its own already-launched impact. Other
casters' control and control during preparation or channeling still use the
normal interruption path.

## Reference and scope

Compared against local VMangos revision
`8f4e608450460efe1e38743e4da74397d4773a3a`:

- `src/game/Spells/Spell.cpp`, `CheckCasterAuras`: initial control checks,
  immunity rescan, and the Blink exception for stun plus silence.
- `src/game/Spells/SpellAuras.cpp`, immunity handlers: active aura purging,
  school polarity, `NO_IMMUNITIES`, self-preservation, and `UNIT_FLAG_IMMUNE`.
- `src/game/Objects/Unit.cpp`, `ApplySpellDispelImmunity`: matching dispel types.

This covers immunity escapes and purging. Mechanic-immunity-mask aura 147 and
invulnerability-triggered battleground flag dropping are outside this change.

## Automated validation

Coverage includes matching and mixed controls; school, dispel, mechanic, and
state grants; active effect indices; timed stun interruption; fear suppression;
silence/pacification; triggered casts; launch-time school lockouts without
costs or spell execution; purge polarity and exclusions; periodic cleanup;
overlapping immunity flags; expiry and death; and Ice Block self-interruption.
Tagged DBC tests use Divine Shield, Ice Block, Blessing of Protection, Blink,
Hammer of Justice, Kidney Shot, Fear, and Silence.

- `mix test.all`: 7,340 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.

## Native client acceptance

Used two isolated build-5875 clients on Programmer Isle: Debugmage (GUID 5)
and Debugshaman (GUID 8). Both WoW processes used AMD GPU rendering, verified
with their own DRM counters and separate helper-owned systemd cgroups.
All gameplay actions originated in the clients. Read-only Tidewave samplers
recorded owner state every 100 ms; they did not alter entities or timing.

Setup: teach the mage spells 11958, 642, 1022, and 1953; teach the shaman 56,
10308, 15487, 172, and 5782. Target the mage, request a duel, accept it from
the mage client, and wait for the countdown. Allow diminishing returns and
spell cooldowns to recover between cases. Ice Block and Divine Shield share
category 37 and its five-minute cooldown in the vanilla DBC; an early Shield
attempt was correctly rejected by the client while that category was cooling
down. Blessing of Protection applies the ordinary one-minute Forbearance.

### Ice Block

The shaman cast Hammer of Justice rank 4, followed by the mage casting Ice
Block while stunned. The client displayed the hostile stun fading and Ice
Block applying. At monotonic time `-576460609312`, the owner was rooted with
holder 10308. At `-576460607542`, only Ice Block remained among timed effects,
with rooting retained and the immunity flag set. At `-576460597600`, Ice
Block expired, rooting cleared, and flags returned to 36872. There was no
false interrupted-cast failure. A preliminary Corruption attempt did not
apply a holder and is not evidence of periodic-effect purging.

### Blink

Hammer of Justice and Silence were simultaneously present at
`-576460467078`. Blink at `-576460465397` removed Hammer of Justice, cleared
rooting, spent mana, and moved the mage from `(16303.20, 16318.10)` to
`(16291.07, 16334.00)`, approximately 20 yards. Silence remained until its own
expiry. Screenshots show both initial debuffs and the Blink result with
Silence still active.
With Silence alone, the client rejected Blink with "Can't do that while
silenced" and the mage stayed in place.

### Blessing of Protection

The shaman's physical Stun (56) rooted the mage at `-576460398863`.
Blessing of Protection at `-576460397035` removed it before natural expiry,
cleared rooting, and applied protection plus Forbearance. Protection expired
at `-576460391101`, clearing the immunity/pacification flags while retaining
Forbearance. The mage displayed the protection buff and the stun fading.
Selective retention of magic damage is covered by the automated
school-purge tests; this native case proves the physical-stun escape.

### Divine Shield

After the shared category cooldown and Forbearance expired, the shaman cast
Corruption rank 1 and Fear rank 1. The mage took two 11-point periodic ticks
and began fleeing. Divine Shield at `-576460252173` removed both holders,
stopped forced movement, set the immunity flag, and applied Forbearance.
The client displayed both debuffs fading and the Shield buff; the opponent's
target frame also lost both hostile debuffs. Health stopped falling at 1973
and subsequently regenerated, with no remaining Corruption ticks. Shield expired at
`-576460242214`, flags returned to 36872, and the mage could walk normally.

### Logout and reconnect

After ordinary walking and duel forfeiture, both clients logged out. Their
entity PIDs, world positions, and metadata entries were absent. Stored
characters had no cast, duel, root, or immunity flag; expired protection and
purged control/damage holders were absent. The mage retained only the still
active Forbearance among these effects. Its stored position confirmed the
normal walk after Shield expiry.

The mage reconnected after Forbearance expired and successfully cast Blink
again, spending mana and moving another 20 yards. No expired immunity,
rooting, or hostile holder returned. Gameplay logs showed no owner crashes
or movement/projection failures. Baseline unimplemented account-data and
GM-ticket messages appeared during login; temporary probe syntax errors were
diagnostic-only and did not affect entity state.

The second logout also left both characters clean and unpublished. Both
helper-owned client services were stopped and verified inactive, their WoW
processes exited, and the retained game-server PTY exited successfully.

## Local evidence

- Mage: `/home/pikdum/.cache/thistle-wow-playtest.mcmeDj/screenshots/`
- Shaman: `/home/pikdum/.cache/thistle-wow-playtest.5soWO1/screenshots/`
- `/tmp/thistle-immunity-iceblock.log`
- `/tmp/thistle-immunity-blink.log`
- `/tmp/thistle-immunity-protection.log`
- `/tmp/thistle-immunity-divine-shield-accepted.log`
- `/tmp/thistle-immunity-logout.log`
- `/tmp/thistle-immunity-reconnect.log`
- `/tmp/thistle-immunity-final-logout.log`
- `/tmp/thistle-immunity-server.log`
