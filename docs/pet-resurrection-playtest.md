# Pet resurrection acceptance

Validated with native WoW 1.12.1 build-5875 clients on September 28, 2026.

Implementation commits: `196cfcf0` (pet resurrection and name projection)
and `c0e66b67` (player selection broadcasts).

## Reference and behavior

VMangos reference: `8f4e608450460efe1e38743e4da74397d4773a3a`,
`src/game/Spells/SpellEffects.cpp` (`EffectResurrectNew`,
`EffectSummonDeadPet`) and `src/game/Objects/Pet.cpp` (`SetDeathState`).

Class resurrection spells can revive a friendly pet immediately, retaining
its GUID and moving it to the caster. They restore their flat health amount,
clamped to the pet's maximum, and do not restore pet mana. Percent-based
player resurrection, including Defibrillate, does not accept pets.

Hunter corpses remain for one hour; summoned pet corpses remain for 15
seconds, with existing guardian-specific lifetime overrides preserved.
Corpse generations reject stale expiration messages after revival or a
later death. Hunter Revive Pet keeps its separate replacement behavior.

Resurrection resets death finalization and combat, restores passive
abilities, starts a fresh regeneration interval, and retains learned
abilities, action bars, pet number, name, happiness, loyalty, and training.
The owner's retained death and health state updates through a typed effect.
Resurrecting an owned pet or guardian removes Demonic Sacrifice bonuses.

## Native acceptance

Debughunter (GUID 7) and Debugpaladin (GUID 2) used isolated hardware-rendered
clients on Programmer Isle. The hunter's level-49 Prairie Wolf Alpha died
in combat with the seeded level-55 Devilsaur. Existing god-mode, learning,
teleport, and pet-happiness commands prepared the scenario. Learned Death
Touch removed the nearby Devilsaur before the paladin's ten-second cast.
All casts, pet commands, renaming, grouping, and movement came from native
client input. Tidewave inspected state and sampled resurrection without
mutating gameplay.

| Action | Observed result |
| --- | --- |
| Pet dies to the Devilsaur | Visible corpse and disabled pet actions; authoritative health 0, retained owner `dead?: true`, and finalized corpse generation 1. |
| Paladin casts Redemption rank 1 (7328) | Native cast bar and spell delivery; the same pet process and GUID revive, and the owner records health 65 and `dead?: false`. |
| Repeat death and resurrection | The same GUID reaches corpse generation 2 and revives again. The final sampler captures exactly 65 health before regeneration. |
| First sample after the fixed resurrection | Pet position is within 0.5 yards of the paladin's casting position as Follow starts; the next health regeneration deadline is 4,975 ms away. |
| Stay, move, Follow | Stay retains the pet's position. Follow moves it about 7.2 yards to the hunter's new position; its command state returns to `:follow`. |
| Rename to Briar | Both clients display the new name. |
| Disconnect and reconnect the hunter | The old pet process disappears. The new process restores Briar alive at 2,138 health with pet number 4,194,406, level 49, XP 34,800, training points 0, the same learned abilities, and the same action bar. |
| Clear the paladin's target, then assist the hunter | Both player owners report the restored pet GUID as their selected target. The observer displays Briar. |

The revived GUID was `17383894611314868394`; the reconnect replacement was
`17383894611314868543`. The retained learned ability IDs were 14919, 17260,
and 24603; family and passive abilities also remained in the runtime
spellbook. Happiness and loyalty continued their ordinary live timers.

## Regressions fixed during acceptance

- Reinitializing the pet's behavior tree initially allowed immediate health
  regeneration. Resurrection now initializes its regeneration deadlines;
  the repeated native test captured health 65 before the first tick.
- An observer displayed an unknown pet name. Creature reveal now includes
  the current pet-name response, using the same packet builder as owner
  attachment, so an earlier missed query cannot leave the name unknown.
  A process test checks the
  corpse-create and name packets sent to a separate observer. The builder
  preserves the existing zero-timestamp fallback.
- Selecting a target updated only the player's stored state. Selection
  changes now request the ordinary unit-field broadcast, allowing another
  client to assist that player while preserving target-bound combo points.

## Automated coverage and evidence

Tests cover eligibility, health clamping, unchanged mana, retained pet
identity and controls, corpse lifetimes, repeat resurrection, obsolete
timer delivery, owner snapshots, guardian sacrifice cleanup without
reviving another retained pet, cast-completion validation before costs,
observer packets, and real DBC spell values. Existing player resurrection
and pet-stable tests remain part of the full suite.

Final gates: `mix test.all` passed all 7,398 tests in 67.7 seconds;
`mix compile --warnings-as-errors` passed; `mix credo --strict` reported
zero issues. Logs are `/tmp/thistle-pet-resurrection-complete-tests.log`,
`/tmp/thistle-pet-resurrection-complete-compile.log`, and
`/tmp/thistle-pet-resurrection-complete-credo.log`.

Native artifacts are retained in:

- `/home/pikdum/.cache/thistle-wow-playtest.Ypjd3J`: original hunter;
  `pet-combat.png`, `revive-pet-casting.png`, `hunter-pet-revived.png`.
- `/home/pikdum/.cache/thistle-wow-playtest.HkK0ZJ`: initial paladin;
  `actual-redemption-casting.png`, `pet-rename-query.png`.
- `/home/pikdum/.cache/thistle-wow-playtest.eAay5d`: fresh paladin;
  `redemption-final-cast.png`, `reconnect-observer-name.png`.
- `/home/pikdum/.cache/thistle-wow-playtest.LN92cv`: reconnected hunter;
  `hunter-reconnected.png`.

Read-only samples are `/tmp/thistle-pet-resurrection-{corpse,final-revive,
stay,follow,disconnect,reconnected,assist}.txt`. The server log is
`/tmp/thistle-pet-resurrection-server.log`. The original clients' WoW
processes 2697034 and 2698155 both reported nonzero AMD graphics-engine
counters and VRAM usage; the fresh observer process 2706965 did as well.

The runtime log contains the existing account-data and GM-ticket unsupported
opcodes, with no resurrection, owner, movement, or visibility crashes.
All helper-owned sessions and the local server were stopped after testing.
