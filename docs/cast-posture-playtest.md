# Spell posture and seated consumption

Implemented in `594ddf06` and tested on 2026-09-27 with a fresh local server
and the native build-5875 client.

## Shared rules

Cast admission and launch now enforce standing requirements through the pure
`Spell.Posture` rules. Player and creature sitting, chair, sleeping, and kneeling
poses reject ordinary casts unless the spell carries `ALLOW_WHILE_SITTING`.
Triggered casts bypass this posture requirement. Item use does not grant a
posture exemption by itself. Game-object casters have no unit posture check.

Player spells carrying the standing-cancels aura flag, including food and drink,
also require stationary movement state. Translation, jumping, falling, and
pitch movement reject them; turning, passive swimming, and transport attachment
alone do not. This check uses the existing movement flags and retains the
existing aura-removal behavior when a consumer stands or moves.

Launch rejection happens before ammunition resolution, power payment, recovery
cooldowns, and spell effects. The existing cast cancellation path handles
cleanup. The vanilla errors are `NOT_STANDING` (`0x3E`) and `MOVING` (`0x2E`).

Reference: VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Spell::CheckCast`, `Unit::IsStandingUp`, and the movement flags in
`MovementInfo.h`; packet codes match the vanilla `smsg_cast_result.wowm`.

## Automated acceptance

All **7,308 tests** passed, including database/map integration tests and the
architecture dependency ratchet. Compilation with warnings as errors passed;
strict Credo found zero issues across 2,575 source files. Commit hooks passed.

Nine new tests cover all posture categories, player/creature/object casters,
item and triggered behavior, relevant movement flags, current-state checks at
launch, cancellation without mana or recovery-cooldown loss, standing back up
before completion, native failure encoding, and player-boundary dispatch.
DBC coverage verifies Food (433), Drink (430), Fireball (133), Pyroblast (11366),
and First Aid (1159).

## Native acceptance

Debugmage (GUID 5, level 50, godmode disabled) used native client input on
Programmer Isle. Tidewave only sampled existing owner and inventory state.

- While seated, the existing `.start` recovery command attempted Stuck (7355).
  The server rejected admission with `not_standing`; the client displayed
  **You must be standing to do that** and `SPELLCAST_FAILED`. Mana stayed at
  3,963, health at 1,875, posture at 1, with no cast, cooldown, or combat.
- Refreshing Spring Water and Tough Jerky worked while already seated.
  The sampled uses changed water count `4 → 3` and food count `3 → 2`,
  retaining posture 1. Auras 430 and 433 coexisted. Recovery samples with both
  active included health `1336 → 1364 → 1393 → 1422` and mana
  `1831 → 1900 → 1969 → 2038`. The client displayed both recovery icons.
- After reapplying both consumables, a brief forward movement changed posture
  to 0 and removed both recovery auras. Item counts remained food 1 and water 2;
  the previously consumed items were not consumed again during cleanup.

Two preliminary Pyroblast attempts tried `/sit` and the sit key during casting.
The client did not change authoritative posture; both casts completed normally
and spent 125 mana, hitting the seeded Thug for 166 and 175 damage. Those runs
are not evidence for posture rejection. Mid-cast posture changes and moving
consumable rejection are verified by automated tests; native rejection above
is specifically an admission check.

## Retained evidence

Normal logout returned to character selection and removed the player's owner,
position, and metadata. Stored state retained full health/mana, no cast or
combat, no recovery auras, and the final item counts. The helper-owned client
and local server were stopped. The server logged no errors; warnings were the
intentional seated rejection and existing account-data and GM-ticket requests.

- Session: `/home/pikdum/.cache/thistle-wow-playtest.EX16sO`.
- Screenshots: `screenshots/recovery-cast.png`,
  `screenshots/food-and-drink.png`, `screenshots/consumption-cleared.png`, and
  `screenshots/logged-out.png`.
- Seated rejection: `/tmp/thistle-cast-posture-recovery-rejected.log`.
- Consumable samples: `/tmp/thistle-cast-posture-consumables.log` and
  `/tmp/thistle-cast-posture-consumables-cleanup.log`.
- Logout state: `/tmp/thistle-cast-posture-logout.log`.
- Preliminary successful Pyroblasts, despite the filenames:
  `/tmp/thistle-cast-posture-rejected.log` and
  `/tmp/thistle-cast-posture-key-rejection.log`.
- Server, gates, and GPU evidence:
  `/tmp/thistle-cast-posture-{server,all,compile,credo,gpu-before,gpu-after}.log`.

WoW PID 2563171 belonged to the helper's service. Its own amdgpu graphics
counter advanced from 1,458,326,121 to 17,286,654,772 ns during acceptance.
