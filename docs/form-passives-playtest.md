# Learned form passives

Validated on 2026-09-25 with the native build-5875 client and the local VMangos
reference at `8f4e60845`.

## Implementation

Learned passive and hidden spells activate from their stance masks when a player
enters a matching form. Learning and login use the same eligibility and aura
application path. Form exit removes self-cast form-bound effects, including
active effects such as Enrage; effects cast by another unit are retained.

The rules follow `Player::IsNeedCastPassiveLikeSpellAtLearn`,
`SpellEntry::IsNeedCastSpellAtFormApply`, `IsRemovedOnShapeLostSpell`, and
`Aura::HandleShapeshiftBoosts` in `refs/vmangos`. The missing Cat mask on spell
24864 uses the same compatibility exception as VMangos.

Hidden dependencies are preloaded from build-compatible inactive
`spell_learn_spell` rows. Feline Swiftness's speed and dodge spells therefore have
independent aura lifetimes: entering a building removes the speed bonus while
retaining dodge. The dependency spells are embedded in their parent's runtime
spell data and remain absent from the learned spell list. Rank replacement and
unlearning remove dependencies that no remaining known spell owns.

## Native acceptance

Session: `/home/pikdum/.cache/thistle-wow-playtest.HPvxep`.
Server log: `/tmp/thistle-form-server.log`.
The helper used GPU rendering. WoW PID 1026935's own `amdgpu` graphics counter
advanced from 666,966,874 ns to 2,058,687,240 ns.

Debugdruid, level 60, entered Cat Form through the client in Northshire. Native
`.learn` commands used the regular player spell-learning boundary. Read-only
Tidewave probes inspected the owner and `World.position/1`; they did not mutate
state. Client `GetDodgeChance()` output independently verified the private stat
projection.

| State | Dodge | Run speed | Relevant owner auras |
| --- | ---: | ---: | --- |
| Before talents | 6.45% | 7.0 | None |
| Cat, Feline Swiftness rank 1 | 8.45% | 8.05 | 17002, 24867 |
| Cat, rank 2 | 10.45% | 9.1 | 24866, 24864; old rank absent |
| Cat, inside the abbey | 10.45% | 7.0 | 24864 retained; 24866 absent |
| Dire Bear | 6.45% | 7.0 | Cat-only passives absent |
| Unshifted | 6.45% | 7.0 | All form passives absent |

Sharpened Claws rank 1 and rank 2 activated immediately when learned in Cat Form.
The owner's client-facing critical-strike field rose from 10.45% to 12.45% on upgrade, with
only the new rank present. Rank 2 remained active in Dire Bear and disappeared
on leaving the form. The equipment baseline contributes two percentage points
to both dodge and critical strike.

Enrage was observed on Dire Bear and disappeared immediately on cancellation of
the form, before its natural expiration. The resulting owner had form 0 and no
Sharpened Claws, Feline Swiftness, hidden dodge, or Enrage holders. Hidden talent
holders had no client buff slot.

Logging out and back in while in Cat Form inside the abbey retained 10.45%
dodge, 12.45% critical strike, and speed 7.0, with exactly one hidden dodge
holder. `.talents reset` kept Cat Form active but returned dodge to 6.45% and
removed both learned talents and their dependent holders. Relearning followed
by `.die` removed the form and all form-bound holders at health zero. Releasing
to a ghost retained that cleanup at health one. After the native corpse-reclaim
timer elapsed, clicking Accept resurrected the player; casting Cat Form restored
the learned rank-3 Sharpened Claws and rank-2 Feline Swiftness. Outside the abbey,
the owner again had 10.45% dodge and speed 9.1, with one holder per passive.

Debugwarrior learned Defiance rank 5 through the native client. Defensive Stance
activated spell 12792 with no buff slot and an authoritative physical threat
multiplier of `1.3 * 1.15 = 1.495`. Berserker Stance removed Defiance and restored
the stance's 0.8 multiplier. Returning to Defensive restored exactly one talent
holder and multiplier 1.495. The client displayed each stance change.

Evidence includes `cat-rank-one.png`, `cat-rank-two.png`, `cat-abbey.png`,
`dire-bear-enrage.png`, `normal-cleanup.png`, `cat-reconnect.png`,
`cat-reset.png`, and `druid-death.png` in the session's `screenshots/`
directory. Owner probes are retained under `/tmp/thistle-form-*.log`.
Further evidence includes `druid-ghost.png`, `druid-resurrect.png`,
`warrior-defensive.png`, and `warrior-berserker.png`.

No owner crashes, spell-validation failures, or relevant protocol errors occurred.
The existing account-data, GM-ticket, and meeting-stone warnings were unchanged.
The owned client session and retained server were stopped after acceptance;
screenshots and logs remain available.

## Automated checks

- `mix test.all`: 6,198 tests passed; `/tmp/thistle-form-final-tests.log`.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- `mix format --check-formatted`: passed.

The new regressions cover Defiance, Sharpened Claws, Feral Instinct, Blood Frenzy,
Primal Fury, Feline Grace, Feline Swiftness, and Enrage. They exercise form entry
and exit, self versus external caster ownership, hidden dependencies, rank
replacement, indoor speed versus dodge, unlearning, retained proc state,
death/ghost suppression, resurrection, and login spellbook restoration.
DBC and VMangos fixtures remain in separately tagged tests.
