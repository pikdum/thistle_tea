# Alterac Valley wing commander rescue and supplies

This milestone implements the six wing commanders' rescue journeys and fleet
supplies. Named air attacks and planted beacons are the following milestone.
Reference behavior comes from
`refs/vmangos/src/scripts/battlegrounds/battleground_alterac.cpp` and
`refs/vmangos/src/game/Battlegrounds/BattleGroundAV.cpp`.

The first friendly interaction starts a prisoner's authored route, removes
player immunity and quest services, and restores her standing pose. Arrival at
the faction base stops the route, moves her combat home there, and restores
quest services. The NPC owner reports that transition to the matching
battleground through a typed effect; the match owns rescue progress and supply
counts. Death and respawn require another rescue and preserve donated supplies.
Respawn restores the prison position and combat home, including the seated
poses of Vipore and Ichman.

| Fleet | Commander | Quest | Item | Goal | Team reputation per exchange |
| --- | --- | --- | --- | --- | --- |
| Horde soldier | Guse (13179) | 6825 | Soldier's Flesh (17326) | 90 | 1 |
| Horde lieutenant | Jeztor (13180) | 6826 | Lieutenant's Flesh (17327) | 60 | 2 |
| Horde commander | Mulverick (13181) | 6827 | Commander's Flesh (17328) | 30 | 5 |
| Alliance soldier | Slidore (13438) | 6942 | Soldier's Medal (17502) | 90 | 1 |
| Alliance lieutenant | Vipore (13439) | 6941 | Lieutenant's Medal (17503) | 60 | 2 |
| Alliance commander | Ichman (13437) | 6943 | Commander's Medal (17504) | 30 | 5 |

Each exchange consumes one item through the existing quest reward transaction.
Only an admitted friendly player in an active match can begin a rescue or
credit supplies, and supplies count only after the commander reaches home.
Crossing a fleet's goal emits the reference readiness yell once.

## Automated acceptance

Pure tests cover all six commanders, duplicate rescue input, the journey and
arrival transitions, cleared flags and pose, route selection, all donation
goals and reputation amounts, independent stockpiles, wrong factions, invitations,
inactive matches, and death or respawn cleanup. A world test emits the NPC's
typed arrival effect through its event sink, checks matching-world delivery,
rejects a misaddressed event, and verifies subsequent donation credit.
VMangos-tagged tests check the live quest relations, required items, and final
waypoint IDs without querying the DBC database.

The broad suite exposed an existing monitor race in `ScriptDeliveryTest`:
a worker that has already exited can be observed as `:noproc` rather than
`:normal`. The test now verifies the caller's normal exit separately and accepts
either terminal worker observation while requiring that queued delivery is dead.

Final validation: `mix test.all` passed all 8,698 tests;
`mix compile --warnings-as-errors`, `mix credo --strict`, formatting, and
`git diff --check` passed.

## Native acceptance

An isolated build-5875 GPU client entered a live Alterac Valley match as a
Horde shaman. The first right-click on imprisoned Guse started her full authored
journey. Her quest flag cleared while traveling; she ran through the route,
reached waypoint 74 at the Horde base, stopped with full health, and restored
her quest service. Her home matched the arrival position and the match marked
her fleet ready. The NPC was never teleported or advanced with a runtime probe.

The native quest window opened at the base. Ninety actual quest exchanges
consumed ninety Soldier's Flesh, credited ninety fleet supplies and ninety
Frostwolf reputation, and emitted the readiness yell. A temporary client frame
completed the ordinary quest progress and reward UI events for the repeated
exchanges. With no flesh remaining, the client disabled Continue and another
click left the stockpile unchanged. The other five stockpiles remained zero.

Logout and reconnect preserved the commander at home, her quest service, the
stockpile, consumed items, and reputation. Leaving the match returned the
player to the open world, removed the match, and left zero entities in its
instance. The native server log contained no errors or warnings. Guse received
native acceptance; the other five commanders and death or respawn transitions
received automated coverage.

## Local evidence

- Native server: `/tmp/thistle-av-air-native-server.log`.
- Isolated GPU client: `/home/pikdum/.cache/thistle-wow-playtest.73YLuO/`.
- WoW's own `amdgpu` counters: `/tmp/thistle-av-air-gpu.log`.
- Focused checks: `/tmp/thistle-av-air-focused.log` and
  `/tmp/thistle-av-air-delivery.log`.
- Final checks: `/tmp/thistle-av-air-final-tests.log`,
  `/tmp/thistle-av-air-final-compile.log`, and
  `/tmp/thistle-av-air-final-credo.log`.
- Reconnect and cleanup probes: `/tmp/thistle-av-air-reconnect.log` and
  `/tmp/thistle-av-air-cleanup.log`.
- Client captures: `guse-prisoner.png`, `guse-arrived.png`,
  `guse-supply-quest.png`, `guse-no-supplies.png`, `guse-reconnect.png`, and
  `guse-match-cleanup.png` under the client's `screenshots/` directory.
