# Creature and pet attack power

Attack-power buffs and debuffs now change ordinary creature damage. Previously,
creatures loaded their current AP and weapon damage without canonical AP inputs,
so applying Demoralizing Shout could show a debuff without reducing damage.

Creature weapon damage uses the VMangos relationship:

```text
damage = seed_damage * (0.7 + 0.3 * current_attack_power / seed_attack_power)
```

Current AP includes changes to strength and agility, flat equipment and aura
bonuses, and percentage AP modifiers. AP cannot fall below zero. A zero AP seed
leaves weapon damage unchanged. Melee and ranged inputs remain independent.
The seed damage already includes the creature template multiplier; ordinary
auto-attacks no longer multiply it a second time.

Hunter pets use their current level's canonical strength-derived AP and apply
happiness once after weapon damage recomputation. Summoned pets use their
current strength-derived AP as the damage denominator, including the imp's
different strength formula. Pets have no ranged AP. Weapon spell snapshots
include the creature damage adjustment without adding the player's AP-per-speed
formula again, while retaining total AP for abilities that scale directly from it.

Player recomputation also supports percentage melee and ranged AP modifiers.
On-equip ranged AP bonuses now enter the canonical equipment aggregate and
disappear when the item is broken or removed. Wands retain their no-AP damage
rule. Aura application, replacement, expiry, removal, and death use the existing
shared transitions; there is no separate debuff bookkeeping.

## References and architecture

- `refs/vmangos/src/game/StatSystem.cpp`: creature AP and physical damage,
  strength/agility deltas, and pet AP, damage, and happiness rules.
- `refs/vmangos/src/game/Objects/Unit.cpp`: flat and percentage AP modifiers.
- `refs/vmangos/src/game/Spells/SpellAuras.cpp`: AP aura handlers.
- `Logic.AttackPower` is pure. Mob and pet builders supply canonical inputs;
  `Logic.Stats` recomputes the projections. `CastContext` carries the adjusted
  weapon snapshot into the existing spell-effect path.
- No new gameplay database queries or architecture allowlist entries were added.

## Native client acceptance

Tested on 2026-09-21 using the build-5875 client, isolated Wine prefixes and
Xvfb, and fresh local servers. The broad combat run used `1103fbaf`; a second
fresh run verified the pet ranged-AP correction in `4a1f0f7b`. Actions used
ordinary client packets, including development commands for learning spells,
positioning, resources, and happiness. Tidewave only read owner state.
No source edits, tests, builds, or commits ran while either live setup was active.

| Scenario | Observed result |
| --- | --- |
| Creature baseline | Three Skeletal Flayers each had 210 AP and a 56.07888–74.33712 weapon range. Recomputing their stats was idempotent. The warrior received real damage; client normal-hit examples included 28, 29, 34, and 36 after armor. |
| Demoralizing Shout | Rank 5 (11556) applied one visible debuff in slot 32 on each Flayer. AP became 70 and weapon damage became 44.863104–59.469696, exactly 20% lower. The client showed the debuff and hits including 24, 25, 27, and 28; authoritative player health fell. |
| Timed expiry | The first unprotected warrior died during sampling, so the expiry check was repeated after corpse recovery with god mode enabled. Health stayed at 2,489 throughout the repeat. On expiry, the debuff disappeared and AP and damage returned to their exact original values. |
| Trueshot Aura | Rank 3 (20906) raised the happy level-49 hunter pet from 200 to 300 AP. Its range changed from 51.7715625–65.2771875 to 59.537296875–75.068765625, a 15% increase. The owner received 100 melee and ranged AP. Both had exactly one Trueshot holder. |
| Pet combat | A native Pet Attack command produced visible melee hits, including 46 damage. The sampled target fell from 2,858 to 2,443 health over 12.7 seconds. The unprotected pet later died under the three-mob attack; the active summon reference cleared. |
| Revival and cancellation | Revive Pet restored the companion. After recasting Trueshot safely out of combat, right-clicking the owner buff removed it from both owner and pet. Client combat text reported both removals. Pet AP returned to 200 and its original happy damage range. |
| Logout and reconnect | Logout removed both the hunter owner and the old pet process. Reconnecting restored a new pet owner with level 49, 200 AP, the original happy damage range, and no Trueshot holder. |
| Final correction | In the fresh `4a1f0f7b` run, Trueshot again produced pet melee AP 300 and the same buffed range, while pet ranged AP stayed zero. Cancellation restored pet AP 200, zero ranged AP, and the original range. Owner melee/ranged AP returned from 391/462 to 291/362. |

Both server runs had no error-level logs or cast-validation failures. Existing
unsupported account-data, raid-info, GM-ticket, and meetingstone requests
appeared during login. A diagnostic sampler started after the first pet died
had no live pet to inspect; the cancellation test was repeated after revival.
All helper-owned clients, Wine/Xvfb processes, and servers were stopped.

## Automated coverage and evidence

Final gates: **4,296 tests passed** with `mix test.all`;
`mix compile --warnings-as-errors`, `mix credo --strict`, and
`mix format --check-formatted` passed.

Regression coverage includes class-level and template fallback loading,
single application of template damage multipliers, zero AP seeds, negative AP
clamping, independent melee/ranged modifiers, low-stat deltas, stacked flat and
percentage effects, equipment breakage/removal, disarm, hunter growth with an
active buff, happiness, imp and summoned-pet formulas, pet ranged-AP exclusion,
weapon spell damage, cast snapshots, aura refresh/expiry/removal/death, and
respawn restoration. DBC tests verify actual signed AP effects and aura 166.

Retained local evidence:

- `/tmp/thistle-ap-server.log` and `/tmp/thistle-ap-final-server.log`
- `/tmp/thistle-ap-{baseline,debuffed,protected-shout,protected-expiry}.json`
- `/tmp/thistle-ap-{trueshot,pet-combat,pet-safe-cancel,cleanup,pet-reconnected}.json`
- `/tmp/thistle-ap-final-pet-{buffed,cancelled}.json`
- `/tmp/thistle-ap-final-{all,compile,credo}.log`
- `/home/pikdum/.cache/thistle-wow-playtest.8UgD4J/screenshots/`, including
  `ap-shout.png`, `ap-protected-expired.png`, `ap-pet-combat.png`,
  `ap-pet-safe-cancel.png`, and `ap-pet-reconnected.png`
- `/home/pikdum/.cache/thistle-wow-playtest.MDfaNS/screenshots/`, including
  `ap-final-buffed.png` and `ap-final-cancelled.png`
