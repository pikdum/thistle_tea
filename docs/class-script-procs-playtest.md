# Class-script proc acceptance

Implemented `SPELL_AURA_OVERRIDE_CLASS_SCRIPTS` proc dispatch through the shared
outgoing spell reaction path. Successful triggers use the existing spell
resolver, charge consumption, and cooldown transitions. Target-owned damage
and healing feedback supplies resolved life and active-resource facts; the pure
rules do not query another entity or the world.

## Reference and behavior

Reference: `refs/vmangos` revision
`8f4e608450460efe1e38743e4da74397d4773a3a`,
`UnitAuraProcHandler.cpp::HandleOverrideClassScriptAuraProc` and
`SpellAuras.cpp::Aura::HandleAddModifier`.

| Class script | Behavior |
| --- | --- |
| 4309 | Nightfall triggers Shadow Trance. The existing proc rule restricts it to Corruption and Drain Life ticks. |
| 836 / 988 / 989 | Improved Blizzard selects the 30%, 50%, or 65% Chilled spell; requires Blizzard's visual. |
| 4086 / 4087 | Improved Mend Pet independently rolls the aura's 15% or 50% amount, then triggers the existing all-types dispel. |
| 3656 | Corrupted Healing triggers only for a spell containing a direct heal effect. |
| 4533 | The druid Rejuvenation set bonus selects mana, rage, or energy restoration from the recipient's active power type. |
| 4537 | The druid Regrowth set bonus triggers Blessing of the Claw. |

Every script requires a living recipient. Existing family, periodic-outcome,
chance, and self-proc checks run before script dispatch. Failed script conditions
do not spend charges or start a cooldown. Cast-item and triggering-aura identity
survive the trigger.

The implementation also repairs a discovered charge bug: Shadow Trance and
Netherwind Focus have zero DBC proc charges, but the reference assigns each one
modifier charge. Their next applicable cast now consumes that charge through the
existing cast-cost snapshot and aura lifecycle.

DBC checks establish the current data rather than assuming tooltip values:
Improved Mend Pet uses dispel type 7; Blessing of the Claw adds 50 health per
stack, allows seven stacks, and lasts four seconds. Rejuvenation restores 60
mana, 20 internal rage units, or 8 energy through the existing energize path.

## Native client

Session: `/home/pikdum/.cache/thistle-wow-playtest.Df4NHv`, hardware-rendered
build 5875. Debugwarlock (GUID 6) and Debugmage (GUID 5) were level 50 with god
mode enabled. Talents were learned through `.learn`; all casts and movement
came through the client. Tidewave was used only for reads.

The completed combat checks used the seeded Defias Evoker, entry 1729, low GUID
992300, on Programmer Isle. Caster teleport `{16375, 16258.1, 75}` on map 451
placed the client above the terrain. The evoker spawned at
`{16393.2, 16258.1, 70.0076}`.

### Nightfall

- Learned rank 2, spell 18095. The runtime rule retained family 5, mask 10,
  harmful-periodic flag 262144, and its ordinary 4% chance.
- Cast rank-1 Corruption and Drain Life. The client displayed Shadow Trance and
  its buff icon. A fresh owner sample found one charge, 9,992 ms remaining, and
  effective rank-1 Shadow Bolt cast time zero.
- Stopped the current channel and cast rank-1 Shadow Bolt. The next owner sample
  showed no Shadow Trance and no active cast.
- Cast another rank-1 Shadow Bolt. The client displayed its normal cast bar;
  the owner retained spell 686 with cast time 1,700 ms and no Shadow Trance.
- Logged out, switched characters, and reconnected. Nightfall rank 2 and its
  proc restrictions were restored; Shadow Trance was absent and Shadow Bolt
  still required 1,700 ms. The mage's previous owner and position were gone.

The first observed Nightfall proc was against the seeded Devilsaur. Its later
knockbacks moved the caster out of range and the creature reset; those follow-up
attempts do not establish charge consumption. The completed sequence above used
the evoker. An initial teleport at height 69.44 was below the local terrain and
was replaced with height 75 before that sequence.

### Improved Blizzard

Learned rank 3, spell 12488. The runtime rule inherited family 3, mask 128, and
proc flags 327680. Cast rank-1 Blizzard through its ground cursor, waiting 400 ms
before clicking the evoker's feet. The client displayed the area animation,
channel bar, damage, and Chilled icon.

A 100 ms owner sampler recorded:

| Relative time | Authoritative result |
| --- | --- |
| 1 ms | Evoker health 1,062; run speed 8.00002; no auras. |
| 2,892 ms | Blizzard channel and periodic holder active. |
| 3,933 ms | First 25 damage; Chilled 12486 at -65%; run speed 2.800007. |
| 10,901 ms | Eighth tick retained; health 862; channel and Blizzard holder gone; Chilled still active. |
| 12,463 ms | Chilled expired; speed returned to 8.00002. |

A later read confirmed health 862, restored speed, no active channel, and no
Blizzard or Chilled holder. The evoker's separate Frost Armor remained.

Native acceptance covered Nightfall and Improved Blizzard. Improved Mend Pet,
Corrupted Healing, both druid bonuses, and Netherwind Focus have automated rule
and/or data coverage, not native acceptance in this run.

## Validation and retained evidence

- `mix test.all`: 6,364 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2,346 files.
- Regressions cover resolved feedback ownership, dead/missing recipients,
  script predicates, probability boundaries, family/outcome rejection, charge
  and cooldown transitions, talent chains, real spell data, restoration,
  expiry, and one-use casting modifiers.
- WoW PID 1304783 used `amdgpu`; its graphics counter increased from
  4,968,549,066 to 27,920,333,549 ns.
- No server errors or cast-validation failures appeared. Login emitted existing
  unsupported account-data, GM-ticket, and meeting-stone requests.

Screenshots in the session directory include `evoker-now`,
`shadow-trance-fresh`, `shadow-bolt-normal`, `blizzard-chilled`, and
`blizzard-expired`. Read-only results and logs remain under
`/tmp/thistle-class-script-*`, including `nightfall-fresh.txt`,
`nightfall-consumed.txt`, `nightfall-next.txt`, `blizzard.txt`,
`blizzard-final.txt`, and `reconnect.txt`.

The helper-owned client service was stopped and confirmed inactive. Player
owners, positions, and metadata for GUIDs 5, 6, and 7 were absent after cleanup.
The retained server was then stopped. No changes were pushed.
