# Creature spell power rules and cost scaling

Implemented in `059eca5e` and tested on 2026-09-27 with the native build-5875
client and a fresh local server.

## Shared behavior

Admission and launch now share power validation. Ordinary creatures can launch
abilities whose resource pools they do not have: rage, focus, energy, happiness,
and mana when their template has no base mana. Charmed ordinary creatures keep
that behavior; pets and players still require the appropriate resource.
Previously, admission allowed these creature casts but launch rejected them.
Health costs must leave the caster alive and return the vanilla
`CASTER_AURASTATE` failure, encoded as `0x12`.

Spell loading now preserves per-level costs, associated skill metadata, and the
creature-level multiplier attribute. Pure cost calculation applies these in
vanilla order: base/per-level cost, percentage resource cost, school flat
adjustment, spell-family modifiers, creature-level multiplier, and school
percentage adjustment. Item and triggered casts bypass the initial power cost;
recurring channel payments retain their existing resource checks. Launch
recalculates cost from current owner state and pays once.

Compared against VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`:
`Spell::CalculatePowerCost`, `Spell::CheckPower`, `Spell::TakePower`,
`Unit::GetSpellRank`, and `Player::GetSpellRank`. The failure code was checked
against the vanilla `smsg_cast_result.wowm` specification.

## Automated acceptance

All **7,299 tests** passed, including database/map integration tests and the
architecture dependency ratchet. Compilation with warnings as errors passed;
strict Credo reported zero issues across 2,572 source files. Commit hooks also
passed formatting and strict lint.

Coverage includes creature and charm exemptions, player/pet refusal, mana lost
during preparation, late cost auras, item casts, health failures and their wire
encoding, skill-rank caps, modifier ordering, truncation, and negative-cost
clamping. Real DBC checks cover Frost Armor (12544), Fireball (9053), and
Jumping Lightning (9654).

## Native acceptance

Debugmage (GUID 5, godmode disabled) used the existing seeded creatures on
Programmer Isle. Read-only 25-ms samples observed owner state while the native
client initiated combat. A client event observer displayed creature spell
damage in the chat frame.

| Case | Authoritative and client result |
| --- | --- |
| Blackrock Warlock, level 57, GUID `17379391079934011414` | Fireball (9053) has base cost 90 and spell level 20. The formula `trunc(90 / (1.117 * 20 / 57 - 0.1327))` gives 347. Samples recorded mana `5340 → 4993 → 4646 → 4299 → 3952 → 3605`, with payment after each three-second preparation. |
| Fireball impact | The level-50 mage's health fell `1875 → 1806 → 1742 → 1666`, matching client messages for 69, 64, and 76 fire damage. The screenshot also captured an arriving projectile. |
| Defias Cutpurse, level 6, GUID `17379390963600795669` | Backstab (53), normally costing 60 energy, launched with mana 0 and energy absent. Turning the level-10 mage away enabled repeated hits; the client displayed three 16-damage Backstabs. Samples included isolated `851 → 835` and `813 → 797` health changes and advancing AI spell timers. No resource pool was invented. |

The mage's rank-one Fireball pulled the Cutpurse for 17 damage. A nearby Defias
Thug also joined combat, so ordinary melee losses are distinct from the isolated
16-point Backstab changes. An initial Warlock teleport placed the mage below
terrain; teleporting above the surface corrected the setup before the sampled
cast. That preliminary placement is not counted as acceptance.

Retreat through the normal client command returned both creatures home with
full health, no cast, empty threat, no combat, and cleared AI spell timers.
The Warlock restored 5,340 mana; the Cutpurse retained no energy pool. The mage
was restored to level 50, full health/mana, no cast, and no combat.

## Retained evidence

Normal logout returned to character selection and removed the player's owner,
position, and metadata. Stored state retained level 50, full health/mana, no
cast, and no combat. The helper-owned client and local server were stopped.
The server logged no errors; warnings were limited to the existing account-data
and GM-ticket requests.

- Session: `/home/pikdum/.cache/thistle-wow-playtest.vJ8PBN`.
- Client screenshots: `screenshots/warlock-first-cast.png`,
  `screenshots/cutpurse-backstab.png`, and `screenshots/logged-out.png`.
- Initial facts: `/tmp/thistle-creature-cost-before.log` and
  `/tmp/thistle-creature-cost-cutpurse-before.log`.
- Samples: `/tmp/thistle-creature-cost-warlock-sample.log` and
  `/tmp/thistle-creature-cost-cutpurse-sample.log`.
- Reset/logout: `/tmp/thistle-creature-cost-after.log` and
  `/tmp/thistle-creature-cost-logout.log`.
- Server, gates, and GPU counters:
  `/tmp/thistle-creature-cost-{server,all,compile,credo,gpu-before,gpu-after}.log`.

WoW PID 2556453 belonged to the helper's service. Its own amdgpu graphics
counter advanced from 892,444,737 to 9,433,780,959 ns during acceptance.
