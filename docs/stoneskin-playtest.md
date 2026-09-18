# Stoneskin and attack damage received

Stoneskin Totem now reduces incoming melee damage. The spell loader recognizes
its aura 125, and a shared pure calculation handles flat and percentage
melee/ranged damage-received auras (113, 114, 125, and 126). The same calculation
serves ordinary attacks, weapon abilities, and damage-class-specific periodic
abilities. Magic damage does not inherit these attack-type modifiers.

Flat amounts add, including holder stacks; independent percentage holders
multiply after the flat adjustment. Non-weapon spell effects scale flat amounts
with their effect coefficient. The receiving entity's current auras are read
when damage lands, so refreshing, removing, or expiring a buff does not alter
an attack or periodic effect's saved caster snapshot. Armor, attack outcomes,
and absorption follow the adjustment.

A related fix preserves zero damage through armor and glancing-hit calculations.
Previously, armor's minimum-one rule could turn a completely suppressed hit
back into one point of damage.

## References

- `Unit::MeleeDamageBonusTaken` and `Unit::CalculateMeleeDamage` in
  `refs/vmangos/src/game/Objects/Unit.cpp`.
- Periodic damage-class dispatch and aura handler mappings in
  `refs/vmangos/src/game/Spells/SpellAuras.cpp`.
- Player totem dismissal in `Unit::SetDeathState`, in
  `refs/vmangos/src/game/Objects/Unit.cpp`.

## Automated acceptance

The tests cover attack-type separation, stacked flat amounts, independent
percentages, coefficient scaling, magic exclusion, reduction before armor and
critical hits, matching damage feedback, absorption, zero-damage attacks,
periodic snapshots, refresh, removal, expiry, and death.

DBC-tagged tests load all six Stoneskin aura ranks: 8072, 8156, 8157, 10403,
10404, and 10405, reducing melee damage by 4, 7, 11, 16, 22, and 30 respectively.
They also exercise the percentage modifiers in creature Shadowform spells
16592 and 22917.

## Real-client acceptance

An isolated build-5875 client used level-50 Debugshaman on Programmer Isle.
Casts and movement came from the client; Tidewave inspected owner state and
traced incoming attacks without mutating gameplay state.

- `/cast Stoneskin Totem` summoned the rank-5 totem and gave the player aura
  10404 with `mod_melee_damage_taken: -22`. The client displayed the buff.
- Moving from the initial totem to the Skeletal Flayers removed protection
  outside its radius. With 5,085 armor, an incoming 40-point swing from a
  level-51 Flayer caused 20 health loss without Stoneskin.
- Recasting Stoneskin in combat reduced the same 40-point swing to 9 health
  loss: subtract 22 first, then apply armor. Screenshots show the reduced
  incoming numbers, and owner samples match the resulting health deltas.
- Casting Strength of Earth Totem replaced the earth-slot summon. The old
  Stoneskin owner stopped at 2,297 ms in the sampler; its aura disappeared at
  4,711 ms, within the existing 2.5-second area-aura grace period. Incoming
  40-point swings again caused 20 health loss.
- Against the level-4 Defias Thug, Stoneskin completely suppressed six traced
  swings with raw damage 4 or 5. Health remained at 2,413 throughout the
  sample, verifying that armor did not reintroduce damage.

The death check exposed an existing totem lifecycle bug: the player lost the
buff, but the totem owner and slot survived. The follow-up introduces a shared
player-totem ownership transition, clears and despawns all totems on death and
logout, and immediately despawns late start results delivered to a dead or
ghost owner. Tests verify actual boundary despawning and cleared saved slots.

A fresh server/client session verified the follow-up:

- Logout stopped the totem and saved an empty slot map; the owner and totem
  were both offline at the first post-logout sample (2,808 ms).
- After logging back in and summoning another Stoneskin Totem, `.die` left
  health zero, an empty slot map, and no live totem at 1,888 ms. Stoneskin's
  DBC aura is marked passive, so it followed the normal area-aura expiry and
  disappeared by 3,831 ms, within 2.5 seconds of the source stopping.

No owner crashes, unsupported-command errors, or cast-validation failures
appeared in either server log. A second observer client was not used.
Both helper-owned clients and local servers were stopped after acceptance.

## Evidence

- First client screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.z4d15t/screenshots/`, especially
  `stoneskin-active.png`, `combat-before.png`, `combat-active.png`,
  `combat-replaced.png`, and `zero-damage-log.png`.
- Fresh-session screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.81euCs/screenshots/`.
- Incoming attack samples:
  `/tmp/thistle-stoneskin-combat-{before,active,replaced}.txt` and
  `/tmp/thistle-stoneskin-zero-damage.txt`.
- Replacement and initial death samples:
  `/tmp/thistle-stoneskin-replacement.txt` and `/tmp/thistle-stoneskin-death.txt`.
- Fixed lifecycle samples:
  `/tmp/thistle-stoneskin-fixed-{logout,death}.txt`.
- Server logs: `/tmp/thistle-stoneskin-server.log` and
  `/tmp/thistle-stoneskin-fixed-server.log`.
- Final gates: `/tmp/thistle-stoneskin-final-{tests,compile,credo}.log`.

Final validation passed: 3,260 tests with `mix test.all`,
`mix compile --warnings-as-errors`, and zero issues from `mix credo --strict`.
