# Pet retaliation and combat continuation acceptance

Validated on 2026-09-27 with the native build-5875 client. Gameplay commits:
`4e92914f`, `ecf16d9c`, and `b8d95fe8`.

## Behavior

Incoming attacks, hostile spells, and owner-defense notifications now share
pet retaliation permissions. They respect Stay reach, commanded recall,
breakable crowd control, PvP protection, passive stance, possession, and an
existing living victim. Pure damage logic emits a typed `PetAttacked` effect;
the owning process evaluates the current observations through the explicit
`EventSink.Context` delivery path. Explicit pet commands retain their overrides.

After a victim dies, a player-owned pet prefers its own attackers, then its
owner's active victim, then attackers on the owner. NPC-owned pets prefer their
threat list and reject continuation while the owner evades. Candidate selection
is deterministic and uses immutable observations and shared attack permissions.
Switching preserves the engagement and threat while clearing the previous
explicit Attack override. With no eligible target, normal return movement runs.

Player presence publishes the active melee or ranged attack target separately
from UI selection, along with owned threat references. Pet observations include
the owner's combat opponents and nearby player attackers. No new architecture
allowlist entries were added.

Kill feedback now invokes the pet transition directly, excluding the defeated
GUID even if its death metadata has not yet been published. Player fatal blows
also notify the active companion, including gray kills. Killing an unrelated
enemy preserves the pet's current victim.

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`PetAI::AttackedBy`, `OwnerAttackedBy`, `CanAttack`, `SelectNextTarget`, and
`KilledUnit`.

## Native scenarios

Debughunter, level 50, used its level-49 Prairie Wolf Alpha on map 451.
Commands and movement were driven through the real client; runtime probes were
read-only.

| Scenario | Observed result |
| --- | --- |
| Defensive pet against two attackers | Body aggro brought a Cutpurse onto the pet and a Thug onto the owner. The pet killed the Cutpurse, switched to the Thug, and killed it without an explicit Attack command. The owner's active attack target remained nil. |
| Immediate continuation | At sample time 3,925 ms, the Cutpurse was dead and the pet already targeted the Thug. The owner's last-contact timestamp was unchanged from 2,575 ms; its next incoming attack occurred at 4,544 ms. The switch therefore preceded another owner-defense notification. |
| Final combat cleanup | Both enemies were dead by 6,732 ms. The pet had no victim, combat, Attack flag, or return progress. The owner's combat state subsequently cleared. |
| Stay under ranged spell damage | The final Blackrock Warlock fixture cast Fireball through the normal `main_ranged` spell-list behavior. After recall and Stay, the pet remained at `{16680.7462, 16200.0551, 69.5388}`, 27.64 yards from the caster. Repeated hits reduced health, including 2,138 to 2,074 and later 1,989, while target stayed zero, Attack stayed false, and control blocking stayed false. The client displayed pet health 2,074. |
| Logout during the ranged encounter | The old pet's registry entry, metadata, and position disappeared. The caster cleared combat, target, threat, and casting. The character retained a suspended hunter-pet relationship. |
| Reconnect | A new pet GUID restored level 49 and defensive stance, with Follow, no Stay anchor, no victim, no Attack override, and no return progress. Owner combat projections were empty. |

The first two-attacker run exposed the kill-feedback/metadata race; `b8d95fe8`
fixed it before the accepted repeat. Preliminary ranged attempts were excluded:
Marisa closed to melee, a melee template lacked mana, and the stationary flag
selected passive AI. The final fixture uses a mana-bearing Blackrock Warlock and
the existing ranged-caster stance.

## Verification and evidence

`mix test.all`: **7,153 passed**. `mix compile --warnings-as-errors` and
`mix credo --strict` passed. Regressions cover retaliation delivery and command
changes, zero-damage contact, victim preservation, selection priority, control
and world restrictions, owner snapshots, projection cleanup, stale death
metadata, and pet/owner kill notifications.

- Final checks: `/tmp/thistle-pet-combat-final-{all,compile,credo}.log`.
- Two-attacker client: `/home/pikdum/.cache/thistle-wow-playtest.EfVwIc`,
  screenshots `pair-fighting.png` and `pair-finished.png`.
- Two-attacker samples: `/tmp/thistle-pet-combat-final-pair.log`.
- Ranged and lifecycle client: `/home/pikdum/.cache/thistle-wow-playtest.5FawHO`,
  screenshots `ranged-stay-acceptance.png`, `logged-out.png`, and `reconnected.png`.
- Ranged samples: `/tmp/thistle-pet-combat-ranged-acceptance.log`.
- Lifecycle: `/tmp/thistle-pet-combat-{logout,reconnect}.log`.
- Accepted server logs: `/tmp/thistle-pet-combat-final-server.log` and
  `/tmp/thistle-pet-combat-ranged-acceptance-server.log`.
- WoW PID 2386455 used `amdgpu` in the helper-owned service. Its graphics counter
  increased from 872,188,157 to 14,137,103,824 ns.

No gameplay handler or AI errors appeared in the accepted runs. Warnings were
limited to the existing account-data and GM-ticket opcodes. All helper-owned
client services and retained server sessions were stopped; evidence was retained.
