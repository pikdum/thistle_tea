# Objective carrier auras and flag lifecycle

Carrier auras now use the shared aura transition for positive school immunity
and unattackable states. Warsong carrier removal notifies the owning match
through a typed effect, reusing its ground-flag spawn, announcement, world-state,
and ten-second return logic. Mounting, concealment, cancellation, and death
therefore reach the same flag transition. Duplicate removals do not add deaths,
kill credit, or extra drops.

Friendly targeted school protection, including a one-level triggered protection
such as Divine Intervention, is rejected before costs or execution when its
target carries an objective. The target owner also rejects late protection
delivery. Player presence publishes the restriction into spell target snapshots.

Flag interaction checks the player's state, object visibility, world, and range.
Total school immunity, mounting, death, and incapacitating controls prevent use;
roots and partial immunity alone do not. Valid use removes Stealth and
Invisibility before requesting pickup. Carrier aura delivery rechecks eligibility
to handle a protection or mounting transition after the initial request.

Logout and world transfer remove carrier auras locally before saving or leaving
the old world. Local teleportation retains them. Battleground announcements use
the roster's retained player name after live metadata has disappeared.

## Reference and automated coverage

Compared with local VMangos revision
`8f4e608450460efe1e38743e4da74397d4773a3a`: `SpellAuras.cpp` immunity and
unattackable handlers; `Unit.cpp` targeted protection and total immunity;
`SpellEntry.cpp` triggered-aura classification; `Player::CanUseBattleGroundObject`;
`GameObject.cpp` flag interaction; and `BattleGroundWS.cpp` flag drop/return.

Tests cover immunity polarity and charm exclusions, partial versus total
immunity, objective removal, Silithyst faction-visual cleanup, direct and
triggered protection, target metadata publication, invalid and late pickups,
wrong-world and duplicate notifications, return generations, cancellation,
death, logout retention, world transfer, and offline announcement names.
Silithyst and Invisibility were checked by automated tests, not native acceptance
in this run. No architecture dependency allowlist entries were added.

- `mix test.all`: 7,359 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.

## Native client acceptance

Two isolated build-5875 clients used Debugmage (GUID 5) and Debugpaladin (GUID 2).
Both WoW processes used AMD GPU rendering, verified through their own DRM
counters and helper-owned systemd cgroups. All gameplay mutations originated
in the clients; Tidewave probes only read owner, match, metadata, and saved state.

Each client entered with `.bg join warsong` and the native Enter Battle button.
Both joined world `(489, instance 1)` as Alliance; `.bg start` opened the gates.
The mage moved to `.go xyz 917 1434.4 348`, the paladin to
`.go xyz 922 1434.4 348`. Omitting the map preserves the instance. Use the raised
Z coordinate: the flag's database Z is below the player floor at this location.
The mage learned Ice Block (11958), Stealth (1784), and Brown Horse (458).
The paladin learned Divine Intervention (19752) and received two Symbols of
Divinity (17033). Friendly targeting required disabling auto-self-cast and
clicking the mage's party frame when the spell targeting cursor was pending.

| Action | Client and authoritative result |
| --- | --- |
| Take Horde base flag | Holder 23333 and carrier metadata appeared; match generation 1 named GUID 5. Both clients saw the pickup. |
| Cast Ice Block | Holder 23333 disappeared, holder 11958 applied, rooting and immunity appeared, and generation 2 spawned one ground flag. Both clients saw the drop and Ice Block. After ten seconds, generation 3 returned to base and rooting/immunity cleared. |
| Cast friendly protection on the carrier | Server received Blessing of Protection 1022 and Divine Intervention 19752 targeting GUID 5, rejecting both with `target_aurastate`. The client displayed “You can't do that yet.” The flag stayed carried; paladin health was 2666, mana 2432, and both reagents remained. |
| Enter Stealth while carrying | Carrier removal produced one ground flag and a drop announcement. After return, clicking the base flag removed Stealth and restored holder 23333; the client displayed both changes. |
| Mount while carrying | Brown Horse 458 replaced the carrier aura; generation 8 held one ground flag. After return, a mounted pickup attempt left generation 9 at base. |
| Try pickup under Divine Shield | Paladin holder 642 and the immunity flag were active. The client displayed “You can't do that while you are immune.” The flag remained at base. |
| Cancel carrier buff, then take ground flag | Right-clicking the buff dropped generation 11. Clicking the ground object restored holder 23333 and generation 12. The old return timer did not return the newly carried flag. |

An early protection attempt auto-cast on the paladin, and an early Divine
Intervention attempt lacked reagents. Those are setup failures, not acceptance
evidence; the successful rejection checks above used actual target-5 packets.

## Bugs found and repeated acceptance

The first logout exposed two existing lifecycle problems: the match dropped the
flag after the player had saved its carrier aura, and the observer announcement
used “Unknown” after live metadata removal. Reconnect consequently restored a
flag buff while the match had already returned the flag to base.

After commit `60f56403`, the server was restarted and both clients repeated real
Warsong entry, pickup, logout, and reconnect. The observer announcement named
Debugmage. The saved character had no holder 23333 and no pending effects, while
its owner PID and metadata were absent. Reconnect restored neither the carrier
aura nor carrier metadata; the match flag remained at base, generation 3.

A subsequent pickup reached generation 4. A local `.go xyz` retained the flag.
Leaving with `.bg leave` dropped generation 5, returned the mage to Programmer
Isle, removed the carrier aura and metadata, and applied Deserter normally.
After the paladin left, the match lookup returned `nil` and the instance had no
world GUIDs. No server errors occurred in the repeated acceptance run.

## Local evidence

Implementation: `f95349fa`. Logout/transfer and announcement fixes: `60f56403`.
Screenshots remain under these helper sessions:

- Mage: `/home/pikdum/.cache/thistle-wow-playtest.fD9iEU/screenshots/`
  (`iceblock-flag-dropped.png`, `pickup-reveals.png`, `mount-dropped.png`,
  `cancel-dropped.png`, `carry-after-old-timer.png`, `fixed-reconnect.png`,
  `fixed-carrier-exit.png`).
- Paladin: `/home/pikdum/.cache/thistle-wow-playtest.Mf7Qd5/screenshots/`
  (`iceblock-observer.png`, `intervention-party-target.png`,
  `immune-pickup-rejected.png`, `fixed-logout-announcement.png`).

Read-only logs are `/tmp/thistle-objective-iceblock.log`,
`/tmp/thistle-objective-protection-costs.log`,
`/tmp/thistle-objective-stale-return.log`, and
`/tmp/thistle-objective-fixed-{saved,reconnect,local-travel,exit,cleanup}.log`.
Server logs are `/tmp/thistle-objective-server.log` and
`/tmp/thistle-objective-fixed-server.log`.
Both owned client services and the development server were stopped afterward.
