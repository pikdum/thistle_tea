# Spell interrupts and school lockouts

Landed interrupt effects now use the shared casting cancellation path. They
stop eligible preparing casts and channels, remove channel auras from local
and remote targets, release owned channel objects and area effects, and send
the native interruption and combat-log packets. Already launched projectiles,
instant casts, and spells without the required prevention and interrupt flags
remain unaffected.

School locks retain separate deadlines from ordinary spell and category
cooldowns. Overlapping locks cannot shorten an existing lock. Learned spells
receive the native school cooldown display without replacing longer ordinary
cooldowns or deferred cooldowns. Login restores the remaining lock, and a
spell cooldown reset reprojects any school lock that still applies.

Creature construction now retains the template mechanic-immunity mask. Shared
spell and aura application respect both whole-spell and individual-effect
mechanics, including the reference exceptions for self casts and attributes.
Silence-immune creatures can lose an interruptible cast without acquiring a
school lock. Interrupt-immune creatures reject an interrupt effect while still
taking accompanying damage. Respawn retains the template mask.

The pure `SpellInterrupt` module owns eligibility and transitions; typed effects
carry packet projection through `EventSink`. Creature immunity is a pure helper
over retained entity data. No database queries enter gameplay paths, and the
architecture dependency allowlist is unchanged.

Local references are VMangos `Spell::EffectInterruptCast`,
`Player::LockOutSpells`, `Creature::LockOutSpells`, and its mechanic-immunity
checks, plus the build-5875 `SMSG_SPELLLOGEXECUTE` interrupt layout in
`refs/wow_messages`.

## Automated coverage

Tests cover cast eligibility, dead targets, zero-duration interrupts, exact
school-lock expiry and overlap, channel healing cancellation, owned-object
cleanup, interruption packets, combat-log encoding, longer and deferred
cooldowns, cooldown resets, login projection, and template immunity through
spell, effect, aura, and respawn paths.

DBC-tagged integration tests exercise Counterspell (10 seconds), Kick (5),
Pummel (4), Shield Bash (6), Earth Shock (2), the real Drain Life channel, and
Kick damage against an interrupt-immune creature. Default tests use fixtures.

## Native acceptance

Two isolated GPU-rendered build-5875 clients used Debugmage and Debugwarlock
in a duel on Programmer Isle. A third isolated client was prepared at character
selection for the reconnect check. Gameplay actions used native input and
existing development commands; Tidewave probes only read owner state.

| Check | Observed result |
| --- | --- |
| Preparing cast | Counterspell stopped Shadow Bolt 11659. The warlock displayed the red Interrupted bar and `SPELLCAST_INTERRUPTED`; the mage took no Shadow Bolt damage. |
| School isolation | Shadow Bolt reuse displayed Spell is not ready yet. Immolate 11667 cast and dealt damage while the shadow school remained locked. |
| Expiry | The sampled lock started at 3,996 ms and was absent at 13,944 ms, within the 100-ms sampling interval. A later Shadow Bolt cast succeeded. |
| Channel cleanup | Drain Life 11699 started at 2,168 ms, dealt one 56-damage tick at 3,198 ms, and was interrupted at 4,029 ms. Its remote aura disappeared and no further drain damage occurred. The owner cleared its cast and channel fields. |
| Observer feedback | The mage displayed Drain Life fades and the native combat-log message You interrupt Debugwarlock's Drain Life. |
| Client timers | The warlock's spellbook reported ten-second shadow cooldowns and zero for Immolate. Drain Life returned to zero after expiry. |
| Reconnect | After another interrupted channel, the old client was closed and the prepared client logged in. A new owner process retained the active lock and no channel. The client reported a remaining cooldown of 5.113 seconds, then zero after expiry. |

Final owner probes found no cast, Drain Life aura, or school timer on either
player, and the warlock's channel field was zero. Creature template immunity
and ordinary cooldown reset interactions are covered by automated tests.

WoW's own AMD DRM graphics counters advanced in each owned cgroup: the mage
from 3,602,588,091 to 17,772,036,505 ns, the initial warlock from 2,933,752,120
to 11,034,264,380 ns, and the reconnect client from 2,831,295,357 to
3,712,340,831 ns. All three helper-owned units and the server were stopped.
No gameplay errors appeared. Preparation included one failed authentication
attempt; logs also contain the existing unsupported login requests for account
data, raid information, GM tickets, and meeting stones.

Local evidence:

- `/home/pikdum/.cache/thistle-wow-playtest.ywzW4p/screenshots/`: casting,
  interruption, school isolation, channel, and cooldown screenshots.
- `/home/pikdum/.cache/thistle-wow-playtest.oMPvYB/screenshots/channel-interrupt-observer.png`.
- `/home/pikdum/.cache/thistle-wow-playtest.jO7M4Z/screenshots/reconnected-lockout.png`
  and `reconnected-expiry.png`.
- `/tmp/thistle-interrupt-cast-samples.txt`,
  `/tmp/thistle-interrupt-channel-samples.txt`,
  `/tmp/thistle-interrupt-reconnect-samples.txt`,
  `/tmp/thistle-interrupt-final-state.txt`, and
  `/tmp/thistle-interrupt-server.log`.

Validation: `mix test.all`, `mix compile --warnings-as-errors`,
`mix credo --strict`, `mix format --check-formatted`, and `git diff --check`.
