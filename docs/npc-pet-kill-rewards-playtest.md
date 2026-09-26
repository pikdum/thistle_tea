# NPC pet kill rewards

Implementation: `43e7c841`. Reference: `refs/vmangos` revision `8f4e60845`,
`Formulas.h::Gain`, `Unit::Kill`, `Player::RewardSinglePlayerAtKill`,
`Group::RewardGroupAtKill`, and the kill-proc gate in `UnitAuraProcHandler.cpp`.

NPC pets and guardians now enter the shared kill-reward path. Pet victims
receive the reference's 0.75 XP factor and never receive an elite bonus.
Template exclusions and damage contribution still apply. Eligible kills also
award quest and reputation credit and forward hunter-pet experience. Pet
victims remain ineligible for kill-triggered procs and Soul Shards.

Eligibility is captured at the lethal hit, before death removes charm or
possession. Player-controlled victims cannot become reward-eligible merely
because that cleanup releases their controller. Respawn clears the snapshot.
Pets do not acquire ordinary loot taps; the killing player's group receives
credit through the existing recipient selection. Their existing corpse and
despawn lifecycle remains responsible for removal.

## Automated evidence

`mix test.all` passed 6,340 tests; compilation with warnings as errors and
strict Credo passed. Coverage includes NPC pet and guardian rewards,
player-owned exclusions, charm/possession death and respawn, group shares,
hunter-pet forwarding, XP/quest/reputation packets, duplicate death delivery,
unlootable corpses, and removal of process and world projections.

A separate C++ float/`nearbyint` oracle compared 702,720 combinations of
owner level, recipient level, victim level, template multiplier, and damage
contribution. The pet formula produced zero mismatches. Artifacts are
`/tmp/thistle-pet-xp-{oracle.cpp,oracle.tsv,compare.exs,oracle-result.txt}`.

## Native acceptance

The fresh build-5875 session was
`/home/pikdum/.cache/thistle-wow-playtest.WZLw5W`, using Debughunter, GUID 7.
Developer commands set levels, enabled god mode, taught spells, and teleported
the character. Taming, casts, stance, logout, and login came from the client;
Tidewave probes only read state.

The level-24 hunter tamed a level-20 Ghostpaw Runner in Ashenvale and set it
passive. At Fire Scar Shrine, native Death Touch killed Ilkrud Magthrull's
level-24 Succubus Minion, entry 10928, GUID `17383894744995725475`.

| Recipient | Before | After | Gain |
| --- | ---: | ---: | ---: |
| Hunter | 200 | 324 | 124 |
| Level-20 wolf | 0/5,800 | 149/5,800 | 149 |

The initial 200 hunter XP came from exploration. Both client diagnostics and
entity owners agreed on the rewards. A sampler observed the dead pet at
3,701 ms and process removal at 18,757 ms, a 15,056 ms interval at 100 ms
sampling resolution. The corpse had no loot session or tap. Totals did not
increase again. Removal cleared its process, position, metadata, and Ilkrud's
companion and summon projections.

The hunter was then changed to level 21, resetting player XP to zero.
Ilkrud's normal Shadow Bolt encounter triggered Voidwalker guardians. Their
template has the no-XP static flag. This run does **not** establish a native
guardian kill reward: one guardian expired between targeting and casting,
and the client switched to a Felslayer. The captured Felslayer death added
158 hunter XP and 165 wolf XP. Guardian reward and exclusion behavior is
covered by automated tests.

After returning to Programmer Isle, the recorded summons and old wolf GUID
had no process, position, or metadata. Logout retained hunter XP 158 and
wolf level 20 with 314/5,800 XP. Login restored those totals and passive stance
on new wolf GUID `17383894625793606025`.

An initial teleport used an unsafe height and fell below terrain; that attempt
awarded nothing. The measured kill used the stable shrine position
`2328, 242, 153.8218`. WoW process 1280502 used amdgpu, with its graphics
counter increasing from 2,040,295,224 to 32,003,845,808 ns.
The helper-owned client and retained BEAM server were stopped afterward.

No error-level or spell-validation logs appeared. Evade exposed unsupported
script command 56, `REMOVE_GUARDIANS`, in script 366401. The immediate
[guardian cleanup follow-up](guardian-script-cleanup-playtest.md) implemented
and tested it in a fresh native encounter. Earlier guardian departure in this
XP session does not prove that command worked.

Evidence: `/tmp/thistle-npc-pet-{tests,compile,credo,server}.log`,
`/tmp/thistle-npc-pet-{tamed,ready,death,after-succubus,guardian-death,logout,reconnected}.txt`,
and session screenshots `succubus-killed.png`, `before-logout.png`, and
`reconnected.png`.
