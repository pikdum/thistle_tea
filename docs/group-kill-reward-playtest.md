# Group kill rewards across death and release

Group rewards now distinguish living XP recipients, unreleased quest recipients,
and reputation recipients whose player or corpse is within 74 yards. The original
tagger remains eligible after leaving the tapped group. Their replacement party
does not acquire the tap.

The boundary reads current metadata and world positions, including the deterministic
corpse GUID. A pure `GroupReward` plan separates player XP, pet XP, and quest credit.
Player delivery rechecks death and ghost state. A released player's positive health
no longer qualifies them for solo XP or pet XP either. Creature honor retains its
living-only filter and also includes the departed original tagger.

## Reference

Compared with `refs/vmangos` at `8f4e60845`:

- `Group.cpp`, `GetDataForXPAtKill` and `RewardGroupAtKill`: nearby living members
  supply the XP denominator; the original tagger is added separately, including
  when dead. Each nearby recipient receives full kill reputation. Quest credit
  excludes released ghosts. Player and pet level eligibility are independent.
- `Player.cpp`, `IsAtGroupRewardDistance`: either the player or, when dead, their
  corpse may satisfy the distance check. The local implementation also requires
  online world presence and compares complete `WorldRef` values.
- `Player.cpp`, `GiveXP`: dead players cannot receive XP.
- `Player.cpp`, `CheckAreaExploreAndOutdoor`: dead players cannot discover areas.
- `Formulas.h`, `xp_in_group_rate`: retained the existing reference group rates.
  The reference's reputation helper uses a full multiplier, despite its stale
  comment about dungeon-specific sharing.

## Automated coverage

Regressions cover departed and deduplicated taggers, unreleased corpses, distant
online ghosts with nearby corpses, missing/offline presence, another instance's
corpse, the 74-yard boundary, living XP denominators, the original dead tagger's
special denominator rule, gray kills, no-XP kills, and pet eligibility independent
of a gray owner's XP. Owner tests assert quest and faction packets, retained state,
no XP packet or rested-XP spending after death/release, capped-owner pet rewards,
and suppression of solo XP and pet rewards for ghosts.

## Native group acceptance

Two isolated GPU build-5875 clients used level-50 Human Debugwarlock (GUID 6) and
Human Mage Debugbidder (GUID 11), quest 8460, and real Deadwood creatures in Felwood.
The mage cast Fireball/Fire Blast through ordinary client spell packets. God mode
protected stationary test characters; `.die`, spirit release, corpse reclaim,
party invitation, and logout used client actions. Runtime probes were read-only.

Initial server: `/tmp/thistle-group-server.log`, running commit `1485539c`.
Both characters began beside `{3600, -1150, 218.15}` on open map 1, with 420 XP
from discovering Deadwood Village, Timbermaw standing -3500, and no quest kills.

| Recipient state | Kill | Warlock XP | Warlock quest counts (warrior/pathfinder/gardener) | Warlock Timbermaw | Mage XP |
| --- | --- | ---: | --- | ---: | ---: |
| Both alive | Level-49 Pathfinder | 420 → 557 | 0/0/0 → 0/1/0 | -3500 → -3494 | 420 → 557 |
| Warlock dead, unreleased | Level-48 Warrior | 557 → 557 | 0/1/0 → 1/1/0 | -3494 → -3488 | 557 → 812 |
| Warlock released, corpse nearby | Level-48 Warrior | 977 → 977 | 1/1/0 unchanged | -3488 → -3483 | 812 → 1067 |
| Warlock reclaimed corpse | Level-48 Gardener | 977 → 1104 | 1/1/0 → 1/1/1 | -3483 → -3477 | 1067 → 1194 |

The ghost stood at `{3806.54, -1600.29, 218.83}`, roughly 495 yards from the
corpse. Reputation still arrived, while kill XP and quest credit did not. Corpse
reclaim removed the corpse projection and restored normal group rewards.
The Human reputation bonus produces 5.5 reputation per kill; the existing
reference-compatible dithering legitimately awards either 5 or 6.

The native run exposed exploration XP on release: the ghost gained 420 XP when
first arriving at Morlos'Aran. That explains 557 → 977 before the ghost kill.
The follow-up fix guards discovery with `Death.alive?` at the discovery boundary,
so neither XP nor explored bits can be granted to a corpse or ghost, including
through a direct discovery request. Weather and territory updates still run.
A regression verifies that the area remains discoverable after returning alive.

## Evidence

- Warlock session: `/home/pikdum/.cache/thistle-wow-playtest.3ZSb0i`.
- Mage session: `/home/pikdum/.cache/thistle-wow-playtest.GtebKX`.
- WoW's own DRM counters showed `amdgpu` and advancing graphics-engine time in
  both owned service cgroups.
- Mage `screenshots/alive-rewards.png`: XP 137 and Pathfinder objective progress.
- Warlock `screenshots/unreleased-quest-reputation.png`: dead body and 1/1/0 quest
  tracker while the release dialog remains open.
- Warlock `screenshots/ghost-reputation.png`: distant graveyard ghost and unchanged
  quest tracker; server snapshots establish the reputation delta.
- Warlock `screenshots/reclaim-dialog.png`: native corpse reclaim prompt.
- Warlock `screenshots/restored-rewards.png`: client XP 1104 and standing -3477,
  agreeing with the owner after all four kills.
- `/tmp/thistle-group-{alive-before,alive-after,dead-before,dead-after,ghost-before,ghost-final,restored-final}.txt`:
  owner XP, standing, quest counts, player/corpse locations, and group membership.

Both players then left combat through travel to Stormwind, logged out completely
(owner PIDs absent), and re-entered. Warlock XP 1104 and mage XP 1194, standing
-3477 for both, and their distinct quest counts survived unchanged. Both had no
corpse projection. `/tmp/thistle-group-reconnected.txt` records the restored owners.
The initial server logged no owner, reward, movement, or network errors. Its
warnings were the existing account-data, GM-ticket, and meetingstone requests.

## Validation

After the exploration fix, `mix test.all` passed all 6,297 tests,
`mix compile --warnings-as-errors` passed, and `mix credo --strict` reported no
issues. Logs are `/tmp/thistle-group-final-{tests,compile,credo}.log`. Both commit
hooks also passed Credo and formatting. No architecture allowlist changes were made.

## Fresh-server exploration acceptance

A fresh server running `4099a423` used isolated GPU session
`/home/pikdum/.cache/thistle-wow-playtest.3O9yt8` and level-50 Human Debugwarrior
(GUID 1). The character discovered Deadwood Village while alive, then died and
released to Morlos'Aran. The native client displayed `Ghost XP: 420`; owner state
confirmed XP 420, ghost state, the nearby original corpse, Deadwood's explored
bit 746 set, and Morlos'Aran's bit 930 still unset.

After native corpse reclaim, the corpse projection was absent. Returning alive
to Morlos'Aran displayed its discovery banner, 420 exploration XP, and
`Alive XP: 840`. Owner state agreed and now had both explored bits set.
The fresh server had no gameplay errors; warnings remained the known login
requests listed above.

Evidence:

- `/tmp/thistle-group-fresh-server.log` and `/tmp/thistle-group-fresh-gpu.txt`.
- `/tmp/thistle-group-exploration-{dead,ghost,alive}.txt`.
- Fresh session `screenshots/exploration-ghost.png`,
  `screenshots/exploration-reclaim.png`, and `screenshots/exploration-alive.png`.

All three helper-owned client services and both retained servers were stopped
at the end. Screenshots and logs were retained. Changes were committed locally;
no push or deployment was performed.
