# Seasonal zone weather acceptance

Native build-5875 acceptance on 2026-09-23 used a fresh local server and two
isolated GPU clients. The behavioral reference was VMangos `Weather.cpp`,
including seasonal selection, gradual and radical changes, intensity limits,
sound thresholds, and the ten-minute update interval.

## Implementation

`Game.Weather` calculates transitions from explicit seasonal chances and random
samples. The boundary loads `game_weather` into ETS at boot and owns clocks,
randomness, and independent timers for each `{WorldRef, zone}`. No gameplay
request queries the world database. New zones start clear; zones without weather
data remain clear when regenerated.

Players subscribe through the existing exploration and zone transition path,
covering login, ordinary movement, travel, and taxi movement. Each visit gets a
new token. The player owner rejects stale subscriptions and updates during world
transfer. Departure removes the subscription; process monitors also clean up
disconnected owners. Empty nonpermanent zones expire on their next timer, keeping
weather available for a quick reconnect. World teardown cancels all copy timers
and subscriptions, including permanent overrides.

`SMSG_WEATHER` encodes Vanilla types 0–3, float intensity, the appropriate sound
ID, and smooth transition mode. `.weather` reports current weather;
`.weather rain|snow|storm <0..1> [permanent]` controls it. `.weather fine` clears
the zone, `.weather auto` resumes natural generation, and `.weather step` advances
the same regeneration path used by its timer.

## Native results

Debugshaman (GUID 8) and Debugmage (GUID 5) entered Elwynn Forest on open map 0.
The shaman stood at Goldshire, approximately `-9465 -66 59.98`; the mage stood at
Crystal Lake, approximately `-9484 -550 65.32`, 484 yards away. Developer commands
selected weather so all three precipitation types could be checked promptly.

| Check | Observed result |
| --- | --- |
| Shared rain | Intensity 0.95 produced rain and reduced visibility in both clients. Both owners subscribed to zone 12 and shared one authoritative weather record. |
| Shared snow | Changing that record to snow 0.95 rendered snowflakes in both clients. |
| Travel and reentry | The shaman traveled to Kharanos in zone 1, which cleared the old snow. Returning to Elwynn restored its current rain. |
| Logout and reconnect | During the shaman's logout, its owner was absent and only the mage remained subscribed. Re-entering the world restored Elwynn's rain without another control command. |
| Movement zoning | The mage moved from `-9840 760` across the river to `-9840 813.295`, entering Westfall, zone 40. Ordinary movement changed the subscription and cleared the rain. |
| Zone isolation | Elwynn changed to a sandstorm while Westfall stayed clear. The shaman displayed blowing particles and haze; the mage received no Elwynn weather. |
| Permanent override and resume | Advancing a permanent storm retained intensity 0.95. After `.weather auto`, another step raised it to 0.9999 through the natural transition logic. |
| Clear and cleanup | After the mage returned to Elwynn, `.weather fine` cleared both clients. Stopping both clients left no weather subscribers. |

The normal ten-minute timer, seed probabilities, sound IDs, stale-message
rejection, empty-zone expiry, and world-copy teardown are automated evidence.
The native regeneration check used `.weather step`; it did not wait ten minutes.
Audio output was disabled by the isolated launcher, so audible playback is not
claimed. Snow and storms in Elwynn were explicit test overrides.

## Evidence and validation

- Shaman session: `/home/pikdum/.cache/thistle-wow-playtest.BrBqKq`.
- Mage session: `/home/pikdum/.cache/thistle-wow-playtest.SXhU57`.
- Shaman screenshots: `clear-elwynn`, `heavy-rain`, `snow`, `zone-clear`,
  `reconnected-rain`, `sandstorm`, `automatic-roll`, and `cleared`.
- Mage screenshots: `shared-rain`, `shared-snow`, `walking-zone-exit`,
  `isolated-clear`, and `shared-cleared`.
- Server log: `/tmp/thistle-weather-server.log`.
- Both clients used the RX 7900 XT at PCI `0000:0c:00.0`. WoW's own gfx counters
  increased from 2184598236 to 17639619786 ns for PID 2313366, and from 731923291
  to 11356379974 ns for PID 2314050.

Logs contain the expected duplicate-character rejection during second-client
selection and existing unsupported account-data, raid-info, ticket, and meeting
stone requests. No weather, owner, movement, or visibility failures occurred.
All helper-owned clients and the retained server were stopped; evidence remains.

Validation: `mix test.all` passes 5227 tests; compilation with warnings as errors,
strict Credo, formatting, and `git diff --check` pass. The real weather seed test
is tagged `:vmangos_db`; default tests use fixtures. No architecture allowlist
entries were added.
