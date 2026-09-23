# Corpse recovery

Repeated deaths increase the corpse recovery delay from 30 to 60 to 120
seconds. The history decays in five-minute steps and survives resurrection
and reconnect within the running server. Spirit release starts the current
countdown; logging back in sends its remaining duration.

The shared lethal-damage transition records the history once, including
environmental damage. Nonlethal hits, further damage to a dead body, and
non-player entities do not advance it. `CorpseReclaim` owns the pure time
rules, and `Player.Corpses` owns release, graveyard travel, countdown packets,
and reclaim validation. The CMSG modules only decode and dispatch.

Reclaim requires a released ghost and its own nearby corpse in the same
world copy. The owner enforces the delay, restores half health and mana,
removes the corpse and its projections, and clears the active release while
retaining repeat-death history. Other resurrection paths clear the release
through the shared death logic. Battleground recovery requires an admitted
player in an active match and restores full resources; recovery during
preparation or after the match ends is rejected.

References are VMangos `Player::UpdateCorpseReclaimDelay`,
`GetCorpseReclaimDelay`, `SendCorpseReclaimDelay`, and
`WorldSession::HandleReclaimCorpseOpcode`. As in that reference, the client
countdown uses the decay tier at release, while server admission rechecks the
live tier. Waiting dead before release can reduce the initial delay.

Automated coverage includes lethal transitions from multiple damage sources,
escalation and decay boundaries, negative monotonic times, reconnect countdown
projection, early reclaim rejection, distance and copy isolation, corpse
cleanup, resurrection history retention, and battleground admission phases.

## Native acceptance

A fresh build-5875 GPU client used Debugwarrior (1) on open map 0 near
Northshire. The existing `.die` command exercised the shared damage funnel;
spirit release and recovery used the client's `RepopMe()` and
`RetrieveCorpse()` actions. Developer teleports shortened the corpse run.
Runtime probes only read state.

- Three deaths selected 30,000, 60,000, and 120,000 ms delays. The second
  native recovery dialog displayed 49 seconds with its Accept button disabled.
  An early recovery attempt left the player a ghost.
- During the third countdown, logout removed the live player process while
  the character store retained the exact history and release timestamps.
  Reconnect preserved both timestamps and the corpse, with 55,552 ms left at
  the owner probe. A later client screenshot and `GetCorpseRecoveryDelay()`
  both reported 18 seconds.
- After the third deadline, a read-only sampler observed recovery at
  1,244/2,489 health, with no corpse position and no release timestamp. The
  repeat-death expiry was retained. The client returned to the living world.
- A fresh Debugpaladin (2) entered Warsong Gulch through the native invitation.
  A recovery attempt 50 seconds after spirit release, beyond its 30-second
  corpse timer, left the player a ghost while the match was still preparing.
  The client showed the nearby corpse and an enabled recovery button. After
  the match became active, recovery restored 2,516/2,516 health and
  2,252/2,252 mana, removed the corpse, and cleared the release timestamp.

Evidence remains in `/tmp/thistle-corpse-reclaim-*.txt`, the server log
`/tmp/thistle-corpse-reclaim-server.log`, and screenshots under
`/home/pikdum/.cache/thistle-wow-playtest.HSAwO2/screenshots/`. WoW's own
AMDGPU engine counters increased during acceptance, and the server log had
no error-level entries. The helper-owned client and retained server were
stopped after acceptance.

Validation: all 4,989 tests passed with `mix test.all`, along with
`mix compile --warnings-as-errors`, `mix credo --strict`, formatting, and
diff checks.
