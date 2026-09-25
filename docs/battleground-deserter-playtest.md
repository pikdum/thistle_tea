# Battleground Deserter acceptance

Build 5875, September 25, 2026. Implementation: `37cff116`; native queue
decoder fix: `e7b10782`. All 6,004 tests, compilation with warnings as errors,
strict Credo, and formatting passed after the final source change.

## Shared departure and admission rules

Warsong Gulch, Arathi Basin, and Alterac Valley use the same roster departure
transition. An inside player leaving during countdown or active play receives
spell 26013 through a typed effect delivered to the player owner. The existing
aura lifecycle supplies its negative presentation, fifteen-minute duration,
death persistence, expiration, and runtime CharacterStore restoration.

Completed matches, unaccepted invitations, and offline reservation cleanup
produce no penalty. Repeated departure delivery does not extend the timer.
Warsong departure also uses the shared resurrection-queue cleanup.

Solo and group admission reject Deserter before changing any queue. Group
admission reads the leader's current character and the other members' existing
aura projections. Invitation acceptance rechecks the owner's aura and cancels
an invitation that is no longer eligible. Tests cover these boundaries and
the existing four-byte Deserter error response, `0xFFFFFFFE`.

Reference behavior comes from `Player::LeaveBattleground`,
`Player::CanJoinToBattleground`, and `BattleGroundHandler.cpp` in `refs/vmangos`.
The DBC integration test verifies spell 26013's duration and attributes.

## Native queue decoder follow-up

The first run exposed a real disconnect before admission: with a zero
battlemaster GUID, the stock queue frame sent nine bytes through
`CMSG_BATTLEFIELD_JOIN`. The old decoder accepted only a four-byte map ID.
The observed solo payload was `E9 01 00 00 00 00 00 00 00`; group admission
changed its last byte to `01`. The decoder now retains the additional instance
ID and group flag while supporting the original map-only form. Regression
tests dispatch this layout and exercise admission through the actual codec.

The failed run used `/tmp/thistle-deserter-native-server.log` and sessions
`9pHTyJ` and `LB7ayQ`. Both clients and that server were stopped before editing.
The final run started fresh processes from `e7b10782`.

## Final native lifecycle

Level-60 Debugmage (5) and Debugpaladin (2) used the same debug account in two
isolated GPU clients. Setup commands supplied levels, solo invitations, match
start, and positions. `.bg list warsong` opened the stock queue frame; its
Join Battle and Join as Group buttons supplied the admission requests.
Runtime probes read state without changing gameplay or time.

The mage entered Warsong instance 1 through Enter Battle, then used `/afk`
after the match started. The client returned to Programmer Isle at the original
position and displayed Deserter with fifteen minutes remaining. The old match
process disappeared and its world contained zero entities. The aura appeared
in the owner, saved character, and metadata projection.

The paladin invited the mage through the client. Both native solo admission
and the leader's Join as Group request displayed the stock Deserter rejection
message. Neither participant was queued. The paladin's party frame showed
the mage's negative aura. Right-clicking the debuff did not remove it.

The mage died through `.die` and retained the penalty. The paladin cast
Redemption through the client, and the mage accepted the resurrection offer.
The mage then logged out and logged back in. Saved health was 701 while
offline; the aura's original application and expiry timestamps survived death,
resurrection, and reconnect. Native admission still displayed the rejection
after reconnect.

The paladin entered a separate Warsong instance 2 while the mage remained
penalized. After one native flag capture, the paladin logged out. The match
retained an offline reservation and its 1-0 score without applying Deserter.
Logging back in restored the same instance and inside membership.

The paladin finished three native flag pickups and captures for a 3-0 victory.
Each pickup used the visible flag; setup travel retained the existing instance,
and client movement crossed the capture trigger. Flag respawn timers elapsed
normally. The scoreboard showed Alliance Wins, three captures, and 1,386 bonus
honor. Clicking its Leave Battleground button returned the paladin to the
original Programmer Isle position without Deserter. Instance 2's match process
and all its entities disappeared. The paladin could immediately join the
ordinary solo queue while still grouped with the penalized mage.

The mage's original penalty elapsed without changing server time. A screenshot
retained eleven seconds on the icon, and a final pre-expiry group request was
still rejected. The next owner observation, 35.878 seconds after the recorded
expiry, found no Deserter holder or metadata entry; both client displays lost
the debuff. The same native Join as Group button then queued both players,
with matching admission timestamps. Each cancelled through the client's
`AcceptBattlefieldPort(1,0)` request, leaving both statuses at none.
Another logout saved the character without Deserter; reconnect restored no
holder or metadata entry and left admission status at none.

The long-running expiry sampler exceeded the CLI's HTTP request timeout, so it
does not establish the precise removal instant. The adjacent native
observations establish natural expiry and restored admission; deterministic
tests establish the exact 900,000 ms boundary.

## Evidence

- Final server: `/tmp/thistle-deserter-final-server.log`.
- Mage: `/home/pikdum/.cache/thistle-wow-playtest.fteIxq`.
- Paladin: `/home/pikdum/.cache/thistle-wow-playtest.o1hMRJ`.
- Screenshots include `final-afk-return`, `final-solo-error`,
  `final-group-error`, `final-dead-penalty`, `final-resurrection-offer`,
  `final-logged-out`, `final-reconnected-denied`, and `final-match-logout`.
- Victory screenshots: `final-victory`, `final-victory-return`, and
  `final-winner-queue`; probes: `/tmp/thistle-deserter-final-{victory,victory-exit,winner-queue}.log`.
- Expiry screenshots: `final-pre-expiry-aura`, `final-pre-expiry-denied`,
  `final-expired`, `final-group-eligible`, `final-member-queued`, and
  `final-reconnect-after-expiry`; probes:
  `/tmp/thistle-deserter-final-{before-expiry,expired-state,group-queued,queue-cleanup,saved-expiry,restored-expiry}.log`.
- State probes: `/tmp/thistle-deserter-final-{initial,denied,dead,offline,reconnected,midpoint,paladin-offline,paladin-return}.log`.
- WoW's own amdgpu DRM counters: `/tmp/thistle-deserter-final-gpu.log`.
- Final source gates: `/tmp/thistle-deserter-codec-{all,compile,credo,format}.log`.

Automated tests cover countdown departures across all three battlegrounds,
stale-invitation rejection, idempotent delivery, cancellation refusal, and the
exact expiry boundary. Those cases should not be inferred solely from the
native active-match departure.

The final server recorded no error-level messages or failed spell validations.
Its only unsupported opcodes were the existing login requests
`CMSG_UPDATE_ACCOUNT_DATA`, `CMSG_GMTICKET_GETTICKET`, and
`CMSG_MEETINGSTONE_INFO`.
Both helper-owned clients and the retained server were stopped. Screenshots
and logs remain in their recorded locations.
