# Outdoor capture points and Plaguelands towers

Native build-5875 acceptance on 2026-09-24, using fresh local servers and normal
capture timers. No capture progress, ownership, or clock was injected through
Tidewave. It was used for read-only owner and projection inspection.

## Implementation

The reusable capture core parses type-29 game-object templates and advances a
signed meter from eligible nearby faction presence. It preserves fractional
progress, caps numerical advantage, distinguishes the neutral band from owned
territory, and projects ordered capture-bar and regional world states.

The world owner samples player presence, monitors regional subscriptions, and
projects ownership changes through player owners, banner owners, rewards, and
announcements. Player reconciliation handles regional buffs, death, resurrection,
zone changes, and reconnects. Capture credit uses the quest lifecycle. Runtime
graveyard control overlays the cached seed links without changing the database.

The four Eastern Plaguelands towers provide faction damage bonuses, capture
quest credit, banner art, sounds, LocalDefense messages, a curing shrine,
spectral flights, reinforcement patrols, a controlled graveyard, and victory
flares at full meter progress. References are `Maps/ZoneScript.cpp`,
`OutdoorPvP/OutdoorPvPEP.cpp`, `OutdoorPvP/OutdoorPvPEP.h`, and migration
`20210724110239_world.sql` under `refs/vmangos/`.

Implementation commits: `2f377b28`, `671a23bc`, `e1a28fd0`, `7f1565ee`.
Native acceptance led to `3d275438`: script recipients prepare missing spells
through the cached loader, special waypoint routes follow authored points
directly, and the random-point boundary converts integer script radii to floats.
The special-route behavior matches `Movement/WaypointMovementGenerator.cpp`.
No architecture allowlist was expanded.

## Clients and artifacts

The main fresh run used commit `3d275438`, server log
`/tmp/thistle-towers-fixed-server.log`, and these isolated GPU sessions:

| Character | GUID | Session suffix | WoW PID | Observed graphics counter |
| --- | --- | --- | --- | --- |
| Debugpaladin | 2 | `ecxj8v` | 428184 | 4,665,185,610 ns |
| Debugbuyer | 10 | `sNSnhQ` | 428912 | 4,645,519,534 ns |
| Debugbidder | 11 | `jHRv2E` | 429692 | 3,778,199,614 ns |
| Debugrival | 12 | `sKpIs9` | 430421 | 3,703,384,400 ns |

Session directories are `/home/pikdum/.cache/thistle-wow-playtest.SUFFIX`.
Each actual WoW process belonged to its recorded systemd service; graphics
counters came from that process's DRM descriptors. Screenshots are in each
session's `screenshots/` directory.

An earlier run at `7f1565ee` used sessions `rQUVzq`, `1iKMHh`, `okjGkU`, and
`JLlczK`, with `/tmp/thistle-towers-acceptance-server.log`. It established stealth
eligibility and initial Horde graveyard behavior, and exposed the script and
movement failures fixed before the main run. A still earlier hot-reloaded run
was discarded as capture-completion evidence.

## Observed behavior

- Three Alliance clients captured Northpass, Eastwall, and Plaguewood while the
  Horde client captured Crown Guard. Each initially contributed one player for
  approximately four minutes. The native UI reported 3 Alliance / 1 Horde,
  displayed LocalDefense announcements, and awarded the corresponding quest
  objectives. Banner-owner reads showed Alliance art kit 2 and Horde art kit 1.
- In the earlier run, Stealth removed the paladin from capture membership and
  hid the bar. Progress remained exactly 202261 across separate reads. Cancelling
  Stealth restored participation and progress (`stealth-no-meter.png`,
  `/tmp/thistle-towers-stealth-paused.txt`).
- Right-clicking the Alliance Northpass shrine granted source aura 30238 and
  automatic regional aura 31906. The client showed Lordaeron's Blessing and its
  30-minute duration (`ecxj8v/service-opened.png`). The Horde client's attempt
  granted neither aura (`sKpIs9/enemy-shrine.png`).
- William Kielar's native gossip offered all three tower destinations.
  Selecting Northpass started path 494 on spectral gryphon display 17328,
  with a 46769 ms flight. The owner reported changing airborne coordinates;
  the client mounted the gryphon and landed at Northpass. The final owner had
  no taxi flight and position `{3099.1855, -4273.4409, 103.2491}` after landing.
  See `sNSnhQ/flight-started.png`, `sNSnhQ/spectral-flight-airborne.png` (captured
  after landing), and `/tmp/thistle-towers-fixed-flight.txt`.
- The five Eastwall reinforcements reached Northpass. The commander completed
  its scripted route and adopted home `{3154.63, -4326.59, 133.206}`, random
  movement type 1, radius 5. Subsequent owner positions changed without the
  previous native radius exception. See the `fixed-patrol-finished` and
  `fixed-patrol-wander` snapshots under `/tmp/thistle-towers-`.
- Both factions' Spirit of Victory traversed the special route and despawned.
  Owner reads captured the Horde spirit at `{1966.7187, -3648.1588, 132.7438}`
  and the later Alliance spirit at `{1973.6409, -3646.4734, 130.4295}`. Subsequent
  registry reads found neither owner. The route starts at the tower roof and
  ends at the graveyard. The main run's screenshots did not isolate the moving
  spirit; the roof follow-up below captures it leaving the tower.
- One Alliance and one Horde player held Crown Guard at exactly -241576 with
  difference 0 across separate reads. With three Alliance players and no live
  Horde participant, progress advanced through neutral toward Alliance control.
  Neutralization removed Crown Guard resources, the Horde buff, and graveyard
  927 from Horde selection. The Horde death/release then used ordinary graveyard
  634 at `{1392, -3701, 76.7009}`. The earlier Horde-owned release used 927.
- Alliance recapture produced a 4 / 0 UI, the all-four announcement, and spell
  1386 on all three Alliance owners. Its native tooltip states 5% increased
  melee, ranged, and spell damage to Undead (`ecxj8v/four-tower-echoes.png`).
  All three received Crown Guard quest credit once. The Horde received none.
- An Alliance death after the flip released at graveyard 927:
  `{1978.4685, -3655.8850, 119.7947}`. Death removed Echoes; native corpse reclaim
  restored it (`jHRv2E/alliance-graveyard.png`, `jHRv2E/resurrected.png`).
- Paladin logout removed its owner and regional subscription. Login restored
  spell 1386 and a fresh subscription. Leaving for Goldshire removed Echoes and
  regional Blessing aura 31906 while retaining source aura 30238. Returning to
  Eastern Plaguelands restored both regional effects. See the `fixed-reconnect`,
  `fixed-left-zone`, and `fixed-returned-zone` snapshots under `/tmp/thistle-towers-`.

No gameplay errors, unsupported script commands, or cast-validation failures
appeared in the main run. Existing login requests for account data, GM tickets,
and meeting-stone information remain outside this feature. Two read-only probes
used incorrect struct fields and were corrected; a long read-only sampler
exceeded the CLI deadline, so its output is not claimed as evidence.

All four main-run services were stopped through the owning helper, all four WoW
PIDs exited, and the retained server PTY was stopped. Artifacts were retained.

## Roof follow-up

The main run also exposed an unlabelled Crown Guard roof: area lookup returned
nil at `{1854, -3724, 194.6}`, removing the regional subscription. The nearest
roof surface has area `{0, 0}`; lower floors have the correct `{139, 2263}`.
Commit `1495e692` resolves unknown areas from the nearest labelled surface at
the same horizontal position. Unknown-map and unsigned-sentinel cases remain
unknown, and the existing Goldshire floor regression still passes.

A fresh server at that commit used `/tmp/thistle-towers-roof-server.log` and
sessions `BE0ZxJ` (Debugpaladin, WoW PID 441809) and `LyI2jw` (Debugbuyer,
PID 442992). Their owned process graphics counters were 2,502,239,290 ns and
1,357,253,274 ns. The paladin stood on the roof at
`{1854, -3724, 192.5124}` and the buyer on the lower tower floor. Both remained
members in zone 139, producing difference 2 and ordinary two-player progress.
After approximately two minutes, both received Crown Guard credit and buff
11413; the roof client displayed the meter, Alliance banner, announcement,
one controlled tower, and completed quest objective.

Screenshots `BE0ZxJ/roof-capturing.png` and `BE0ZxJ/roof-capture-1.png` show the
roof capture before and after ownership. The latter also shows the winged spirit
departing at the right edge; later frames show it leaving view. A one-second
read-only series recorded the spirit moving from
`{1858.9033, -3712.5028, 193.4151}` down the route, and a later registry query
confirmed its owner had exited. Evidence is in `/tmp/thistle-towers-roof-` files
`participation.txt`, `captured.txt`, `spirit-spawn.txt`, and `spirit-cleanup.txt`.
No gameplay errors appeared. Both helper-owned clients and the server were
stopped after acceptance.

## Automated coverage

Tests cover template decoding, numeric advantage and meter transitions,
eligibility, capture credit, subscription replacement and owner death,
regional aura lifecycle, resource reconciliation, graveyard faction filtering,
enemy/dead/remote shrine rejection, defense-message encoding, script spell
preparation, special-route arrival, and the integer-radius native regression.
Full-meter victory flares and remote dungeon buff projection have automated
coverage; the main native run did not wait for full meter saturation or enter
Stratholme and Scholomance.

Final code checks: `mix test.all` passed 5,832 tests in 50.1 seconds;
`mix compile --warnings-as-errors`, `mix credo --strict`, formatting, and
`git diff --check` passed. Logs are `/tmp/thistle-towers-roof-final-tests.log`
and `/tmp/thistle-towers-roof-final-credo.log`.
