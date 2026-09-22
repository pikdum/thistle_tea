# Wounded creature movement

Ordinary creatures now run at 70% speed below 16% health, 60% below 11%, and
50% below 6%. These are the strict thresholds used by VMangos's creature
health states. The penalty multiplies aura speed modifiers and affects only
forward running. Canonical base speeds remain unchanged.

Hunter and summoned pets, guardians, companions, world bosses, and templates
with `CREATURE_STATIC_FLAG_2_NO_WOUNDED_SLOWDOWN` are exempt. Ordinary charmed
or possessed creatures retain the penalty. The second static flag word is
loaded into the creature's runtime configuration; gameplay makes no database
queries. Creature health-state bits follow damage, healing, death, and reset.

Speed changes also retime an active run from its interpolated position,
preserving remaining corners and final facing. The new spline reaches both
observers and spatial projections. Walking, explicitly specified velocities,
and timed movement retain their timing. The same path handles aura snares.
Possessed creatures send speed changes to their controller, with acknowledgements
matched to the recorded mover, movement mode, counter, and speed.

Local references:

- `Creature::Update` and `DoFlee` in
  `refs/vmangos/src/game/Objects/Creature.cpp`.
- `Unit::UpdateSpeed` in `refs/vmangos/src/game/Objects/Unit.cpp`.
- Speed constants and secondary static flags in
  `refs/vmangos/src/game/Objects/CreatureDefines.h`.

## Native acceptance

An isolated GPU-rendered build-5875 client controlled level-50 Debugbidder on
Programmer Isle. Native Fireball and Corruption casts damaged a level-51
Skeletal Flayer with 2,980 maximum health. A read-only owner sampler and a
receive trace on the player's entity process recorded state and outbound
movement messages. WoW's own DRM graphics counters increased on the RX 7900 XT.

| Health | Run speed | Wounded multiplier |
| --- | --- | --- |
| 2,980 | 8.00002 | 1.0 |
| 470 | 5.600014 | 0.7 |
| 325 | 4.800012 | 0.6 |
| 174 | 4.00001 | 0.5 |

During a chase, a Corruption tick changed health from 335 to 325. Spline 6 had
a duration of 1,126 ms. About 192 ms into it, spline 7 continued from the
interpolated position to the same endpoint with a remaining duration of
1,089 ms. The client received the new spline and retained its target-facing
mode. The later 184-to-174 transition similarly replaced spline 16 with
spline 17 at the lower speed, preserving its endpoint.

Rank-1 Frostbolt then reduced health to 132 and combined its 40% snare with
the wounded penalty: speed became 2.400006. The client showed the Frostbolt
debuff; expiry restored 4.00001. Moving out of leash range triggered evade,
restoring health to 2,980, speed to 8.00002, and wound state to zero before
the creature returned home. A subsequent native kill left zero health,
cleared wound state, and restored the canonical run speed on the corpse.

The death check exposed a playground respawn bug: setting the virtual
`spawntimesecs` field left the source row's randomized minimum and maximum
intact. The development seed now sets all three fields to its requested
interval.

On a fresh server with the fix, the live seed reported 5,000 ms for the loot
piñatas, 30,000 ms for the hostiles, and 180,000 ms for the skinning boar.
A second native Fireball kill and owner sampler measured exactly 30,000 ms
from the first dead sample to the first respawned sample. The same creature
returned with 2,980 health, 8.00002 run speed, no wound bits, and a normal-speed
chase. The client showed the corpse and then the living target at full health.

Both helper-owned clients, diagnostic probes, and acceptance servers were
stopped. Neither server log contained error-level messages.

## Automated coverage

Tests cover exact health boundaries, speed composition and idempotence,
player/pet/boss/template exemptions, damage and healing transitions,
regeneration, evade, death, respawn, interpolated path continuity, unchanged
movement modes, client packets, spatial projections, controlled mover
acknowledgements, and the real database flag on Darkmaster Gandling.

The possession-specific speed packet and acknowledgement checks are automated;
the native acceptance above exercises an ordinary creature.

## Evidence

- Main session: `/home/pikdum/.cache/thistle-wow-playtest.hOgcXS`.
- Screenshots: `wounded-running.png`, `weakest-chase.png`,
  `wounded-with-snare.png`, `evade-recovery.png`, and `death.png` under that
  session's `screenshots/` directory.
- Server log: `/tmp/thistle-wounded-server.log`.
- State and packet trace: `/tmp/thistle-wounded-evidence.txt`.
- Movement packets: `/tmp/thistle-wounded-movement-packets.txt`.
- Chase transition: `/tmp/thistle-wounded-retime-window.txt`.
- Speed and aura transitions: `/tmp/thistle-wounded-transitions.txt`.
- GPU counters: `/tmp/thistle-wounded-gpu.txt`.
- Respawn session: `/home/pikdum/.cache/thistle-wow-playtest.usRxYf`, with
  `death-before-respawn.png` and `respawned.png` screenshots.
- Fresh server: `/tmp/thistle-wounded-respawn-server.log`.
- Corrected seed intervals: `/tmp/thistle-wounded-seed-intervals.txt`.
- Respawn timing: `/tmp/thistle-wounded-respawn-timing.txt`.
- Fresh-server trace: `/tmp/thistle-wounded-respawn-evidence.txt`.

## Final validation

- `mix test.all`: 4,861 tests passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: no issues.
- Formatting and `git diff --check`: passed.
- Gate logs: `/tmp/thistle-wounded-final-{tests,compile,credo}.log`.
