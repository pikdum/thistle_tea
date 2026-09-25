# Creature retreat and assistance

Script command 47 now honors its seek-assistance argument. A fleeing creature
selects the nearest eligible, visible ally within 30 yards in the same world.
It retains its authoritative combat victim while projecting target zero to
clients, retreats to the ally, calls helpers within 10 yards on arrival, and
waits 1.5 seconds before resuming combat. Without an eligible ally, it uses the
existing seven-second panic movement.

Helper eligibility is shared by retreat selection and assistance delivery.
The creature owner publishes availability alongside its orientation metadata;
dead, busy, evading, controlled, invisible, spawning, stunned, pacified,
unselectable, and no-assist creatures are excluded as applicable. Faction rules
remain distinct for initial assistance and the broader friendly call-for-help
pulse.

Delayed assistance captures eligible helpers when the call starts and rechecks
that set on delivery. Moving during the delay cannot recruit a different group.
A combat-generation reference prevents an old callback from recruiting helpers
after a reset and subsequent pull. Recruited allies share the caller's leash
clock and suppress recursive initial assistance.

The behavior tree consumes immutable observations and enqueues navigation
intents. Walking presentation uses the creature's derived running speed, so
wounded penalties and aura changes continue to retime the retreat. Roots and
stuns pause movement; control takeover or victim loss cancels it. The normal
engagement transitions clear assistance on combat end and death. Ordinary
scripted panic also now projects the fleeing flag and stops its remaining path
when its deadline expires.

Reference behavior comes from `Creature::DoFleeToGetAssistance`,
`Creature::CallAssistance`, `AssistDelayEvent`, the assistance grid checks, and
the assistance movement generators under `refs/vmangos/src/game/`.

## Native acceptance

Server commit `b6beaf51` stayed fixed throughout the run. Two isolated,
hardware-rendered build-5875 clients controlled level-50 Debugmage and
Debugbuyer. Both WoW processes had matching helper-owned systemd cgroups,
AMD DRM activity, and allocated VRAM. Combat actions came from the clients;
Tidewave probes only read existing state.

The debug playground supplies two Horde Laborers, entry 14718, at
`{16463.2, 16318.1}` and `{16487.2, 16318.1}` on map 451. They retain the real
low-health EventAI command 1471802. Their initial aggro shout is disabled in
this fixture so the helper remains idle until the retreat arrives. Their
GUIDs were `17379391208950801152` and `17379391208950801153`; their maximum
health was 788 and 840 respectively. This is a controlled fixture, not an
unmodified natural-spawn acceptance run.

- Frostbolt pulled the first laborer while the second stayed idle. At 117/788
  health, the caller displayed the flee emote and retreated from approximately
  `x=16459.70` to its ally at `x=16487.20`. Both clients displayed the movement.
- A 250 ms sampler first observed the retreat at 3,012 ms, arrival and waiting
  at 10,291 ms, and helper combat entry at 11,797 ms. The observed 1,506 ms
  interval agrees with the 1,500 ms assistance delay. The caller's authoritative
  victim remained player 5 while its client projection was zero; the projection
  returned to 5 when the wait ended. Both creatures then approached the mage.
- The recruited helper retained a shared leash rather than an independent
  extension timestamp. Both owners and public metadata reported combat and
  unavailable assistance status during the fight.
- Moving the mage away caused both creatures to evade and return home at full
  health, with target zero, empty threat, no assistance memory, and helper
  eligibility restored.
- On the next pull, client-cast Curse of Recklessness prevented the retreat.
  The caller stayed at 106/788 health and continued fighting; a 13.5-second
  sample retained no assistance or panic state, while the helper stayed idle.
- Another reset and pull recruited the ally again. Death Touch then killed
  both creatures. Both clients displayed the corpses; both owners retained
  zero health, empty paths and threat, target zero, combat false, and no
  assistance state. Both player owners and their metadata cleared combat.
- The normal 30-second fixture respawn restored both creatures at their home
  positions with full health, cleared EventAI disabled sets, empty threat,
  no assistance memory, and availability true.

Deterministic tests additionally cover root pause and resumption, fear takeover,
victim changes and loss, path failure, speed retiming with walking flags,
no-helper panic fallback, movement-interruptible casts, eligibility filters,
stale delayed calls, world-copy separation, and death during a retreat. Root
pause and resumption were not separately exercised in the native run.

Artifacts remain in `thistle-wow-playtest.nGZUqU` and
`thistle-wow-playtest.rTJ1Lx` under the local cache. Curated samples and server
logs are in `/tmp/thistle-assistance-*.log`. Both sessions and the retained
server were stopped after acceptance.

No entity-owner, movement, or spell failures appeared. Existing unsupported
account-data, GM-ticket, and meeting-stone requests remain visible in the log.

Validation: 5,885 tests passed with `mix test.all`; compilation with warnings as
errors, strict Credo, formatting, and the diff whitespace check passed.
