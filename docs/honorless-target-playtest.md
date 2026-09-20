# Honorless Target: client acceptance

Validated travel and combat behavior at `fe2f1f77` with the build-5875 client,
Debugmage (GUID 5) and Debugshaman (GUID 8), both level 60. Setup used owner
commands and ordinary client spells. Tidewave only read live state; a 100 ms
sampler retained changed position, health, combat, flight, and aura state.

## Travel and lifecycle

1. Initial login on Programmer Isle granted no Honorless Target, despite
   enforced PvP. Cross-map travel to Stormwind and a near teleport inside
   Stormwind also granted none after their acknowledgements completed.
2. A near teleport to Aerie Peak applied spell 2479 for thirty seconds. The
   client showed its icon and countdown. The owner, saved character, and
   published aura stacks contained one holder. Another near teleport
   refreshed that holder; it expired 32 ms after its recorded deadline in
   the sampler, without another action.
3. Debugshaman's cross-map arrival from Programmer Isle to Hillsbrad also
   applied protection. The client displayed Contested Territory and the
   countdown. A later near teleport moved the combat setup off a steep slope
   to open ground near `{-930, -800, 22.85}`.
4. Guthrum Thunderfist's real flight-master menu started path 475, Aerie Peak
   to Chillwind Camp. No protection remained during flight. Landing at
   `{931.32, -1430.11, 64.67}` cleared flight state and mount display, refreshed
   destination territory, and applied thirty seconds of protection. Owner,
   saved character, metadata, and the visible client icon agreed.
5. After expiry, logout/login at Chillwind Camp retained enforced PvP and
   granted no new protection. Both owner and saved character had no 2479.

## Combat and honor accounting

Both characters received protection through ordinary near teleports.
Debugmage cast rank-one Fire Blast (2136), dealing 33 damage: the mage's
protection disappeared and the shaman's remained. Both entered combat.

Blink (1953) moved the mage from `{-950, -800, 23.82}` to approximately
`{-942.85, -781.81, 19.50}`. Combat remained active across the teleport and
acknowledgement, ending through its ordinary timeout later. No new Honorless
Target appeared. The client displayed Blink and retained its combat indicator.

The shaman refreshed protection through another near teleport. Death Touch
killed the protected victim: health became zero, the holder disappeared,
published alive state became false, and damage history was consumed. The
killer's ledger remained empty with zero kills and zero contribution.

The shaman used the actual Reincarnation button, recovered health through
`.modify hp`, and received another arrival aura. After thirty seconds, the
owner and metadata contained no protection. A second Death Touch awarded
exactly 188 honor and one honorable kill. The ledger recorded one victim
credit; owner and saved honor fields agreed. This proves that the protected
kill did not consume the first eligible kill's full credit.

## Evidence

- Mage session: `/home/pikdum/.cache/thistle-wow-playtest.GPVe7G`.
- Shaman session: `/home/pikdum/.cache/thistle-wow-playtest.XhXXle`.
- Useful screenshots: `flightmaster.png`, `refreshed-protection.png`,
  `taxi-destinations.png`, `in-flight.png`, `flight-landing.png`,
  `reconnect-contested.png`, `hostile-cast-blink.png`,
  `damage-keeps-protection.png`, `protected-death.png`, and
  `reincarnated-protected.png` in the corresponding session.
- Timing trace: `/tmp/thistle-honorless-samples.log`.
- Runtime evidence: `/tmp/thistle-honorless-{safe-near,refreshed,flight-and-far,landing,reconnected,protected-kill,expired,eligible-kill}.log`.
- Server log: `/tmp/thistle-honorless-playtest.log`. No errors or spell
  validation failures occurred. The flight exposed an unhandled
  `CMSG_MOVE_SPLINE_DONE`, addressed in the follow-up below. Other warnings
  were the existing login stubs for account data, raid info, GM tickets,
  query time, and meeting stones.

Both helper-owned clients and the retained server were stopped after this run.

## Spline completion follow-up

Commits `3f571efd` and `9467191b` add `CMSG_MOVE_SPLINE_DONE` dispatch and its
vanilla movement block, spline identifier, and trailing float. The boundary
accepts only the active player's current taxi spline after the server's
deadline. Early, obsolete, loading, foreign-mover, and duplicate completions
cannot land the player or refresh protection; client coordinates are ignored.

The first repeat flight exposed the trailing-float decoder error through a
read-only handler trace. After correcting it and adding layout regression
coverage, a fresh build-5875 run repeated path 475 at `9467191b`:

- The client reported spline ID 1, matching the owner's ID 1, with trailing
  float 1.0. The acknowledgement reached the registered handler about 80 ms
  after the server had already completed the flight.
- The owner had already reached the server destination, cleared flight and
  mount state, and applied one thirty-second protection holder. The client
  showed the landing and aura countdown. A later snapshot retained exactly
  the same expiry, proving that the acknowledgement did not refresh it.
- The server recorded one handled `CMSG_MOVE_SPLINE_DONE` and no errors,
  spell-validation failures, or unimplemented spline-completion warning.
  The existing login-stub warnings remained.

Final session: `/home/pikdum/.cache/thistle-wow-playtest.WNmL4a`, screenshot
`acknowledged-landing.png`. Evidence is
`/tmp/thistle-spline-ack-trace.log`,
`/tmp/thistle-spline-final-landed-state.log`, and
`/tmp/thistle-honorless-spline-final-playtest.log`. The helper-owned client,
X server, and retained game server were stopped afterward.

Final gates after the decoder correction: `mix test.all` passed 3,883 tests;
`mix compile --warnings-as-errors`, `mix credo --strict`, and
`mix format --check-formatted` passed. Logs are
`/tmp/thistle-honorless-final-{all,compile,credo,format}.log`. Coverage includes
loaded spell data, aura refresh/expiry/death, hostile versus friendly casts,
interrupted casts and misses, owner publication, Blink combat/companion state,
acknowledgement replay, packet dispatch, and server-timed taxi completion.
