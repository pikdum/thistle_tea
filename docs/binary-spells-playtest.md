# Binary spell resistance

Magical spells with control effects now use school resistance in their
all-or-nothing hit roll. Frostbolt, Frost Nova, Earth Shock, Counterspell, and
Mind Flay follow the VMangos binary classification. Ordinary damage spells
such as Fireball and Shadow Bolt retain partial damage resistance.

The shared calculation combines level-based hit chance, hit bonuses, mechanic
resistance, and the target's school resistance after caster penetration. School
resistance contributes at most 75%, without adding innate creature level
resistance to this binary roll. Final hit chance remains between 1% and 99%,
except for explicit always-hit and no-spell-defense rules. Successful binary
hits skip partial resistance, including periodic damage, while shields still
absorb normally. Triggered binary spells use the same calculation.

Classification is compiled at spell loading and retained when individual
effects are filtered. Players and creatures publish current resistance through
their existing owner boundaries, including initial entry, updates, and respawn.

Local references:

- `SpellInternal::IsBinary` in `refs/vmangos/src/game/Spells/SpellMgr.cpp`.
- `MagicSpellHitChance` and `GetSpellResistChance` in
  `refs/vmangos/src/game/Objects/SpellCaster.cpp`.
- `CalculateDamageAbsorbAndResist` in `refs/vmangos/src/game/Objects/Unit.cpp`.

## Native acceptance

Two isolated GPU-rendered build-5875 clients controlled level-50 Debugbidder
(mage, GUID 11) and Debugwarrior (GUID 1) on Programmer Isle. All spells and duel
actions came through the clients. The warrior learned and cast Unholy Shield
(8909), a resistance buff supplying 10,000 resistance to each magical school.
Owner stats and published metadata both showed these values.

A read-only receive trace on the mage's player process captured outbound combat
messages. In the recorded 16-cast rank-1 Frostbolt sample, 12 casts fully resisted
and four hit for 23, 21, 23, and 23 damage. Every successful hit reported zero
partial resistance. The native combat log showed full hits, the Frostbolt
debuff, and resisted casts. This small sample verifies behavior; it is not an
estimate of the long-run hit rate.

An owner-state sampler observed landed Frostbolts lower health and reduce run
speed from 7.0 to 4.2. Aura expiry restored 7.0. Against the same resistance buff,
three rank-1 Fireballs dealt 5 damage each, with 15, 14, and 13 damage resisted;
the client displayed those partial-resistance amounts.

The warrior then used `.die`. Health became zero, the duel ended, the resistance
buff and slow disappeared, and both owner stats and published school resistance
returned to zero. No error-level server messages occurred. Both helper-owned
clients, the diagnostic tracer, and the acceptance server were stopped.

Automated tests additionally cover spell classification, final cap ordering,
school-specific penetration, target level differences, always-hit bypasses,
triggered casts, shield absorption, periodic damage and cancellation, and
resistance removal between casts.

## Screenshot follow-up

The playtest exposed stale screenshots from X11 window capture under Gamescope:
the game kept processing and rendering while `import -window` returned an old
frame. Acceptance screenshots below use Gamescope's compositor capture. The
helper now records its Gamescope socket and requests screenshots there, waiting
for the completed image before publishing it. See the
[GPU acceptance notes](gpu-playtest-acceptance.md).

## Evidence

- Mage session: `/home/pikdum/.cache/thistle-wow-playtest.UDvSv0`.
- Warrior session: `/home/pikdum/.cache/thistle-wow-playtest.aJVl6K`.
- Compositor screenshots: mage `screenshots/binary-combat-log.png` and
  `screenshots/resistance-combat-log.png`; warrior `screenshots/death-cleanup.png`.
- Server log: `/tmp/thistle-binary-server.log`.
- Packet trace: `/tmp/thistle-binary-final-packets.txt`.
- Packet summary: `/tmp/thistle-binary-packet-summary.txt`.
- Aura and movement samples: `/tmp/thistle-binary-slow-samples.txt`.
- Resistance publication: `/tmp/thistle-binary-initial-state.txt` and
  `/tmp/thistle-binary-death-state.txt`.

## Final validation

- `mix test.all`: 4,850 tests passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: no issues.
- Formatting and `git diff --check`: passed.
- Logs: `/tmp/thistle-binary-final-{tests,compile,credo}.log`.
