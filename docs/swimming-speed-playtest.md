# Swimming and backward movement speeds

Aura transitions now announce changes to running, backward running, swimming,
and backward swimming independently. Swim Speed Potions and Aquatic Form can
therefore change the controlling client's swimming speed immediately. Removing,
expiring, or clearing their auras on death restores the derived speed through
the same transition path. Nearby players receive the corresponding movement
and speed packets; newly visible players retain the existing create-object
speed snapshot.

Every forced change shares the existing movement counter and validates the
acknowledgement's owner, counter, movement mode, and float speed. Acknowledgements
settle delivery without writing derived speeds back into the entity, preventing
an old acknowledgement from undoing a later aura transition. Spirit release
continues to wait for outstanding movement acknowledgements.

Swim bonuses use the strongest active bonus and affect forward swimming only.
Snares multiply running, backward running, and forward swimming. Backward
swimming stays at its base speed, correcting the previous calculation to match
`Unit::UpdateSpeed` and the speed aura handlers in `refs/vmangos/`. Observer
packet layouts follow `MovementPacketSender::SendSpeedChangeToObservers`;
forced changes and acknowledgements follow the Vanilla `wow_messages` specs.

Automated coverage includes wire layouts and opcode dispatch, owner and observer
routing, shared acknowledgement sequencing, invalid and out-of-order replies,
float precision, spirit release, overlapping buffs, slow removal, cancellation,
expiry, and death cleanup.

## Real-client acceptance

Used the isolated build-5875 client with Debugshaman in Crystal Lake, map 0,
starting at `-9525 -220 54`. Existing developer commands supplied the potion,
learned Aquatic Form on this test character, and staged the location. All aura
application and cancellation went through the real client; runtime probes only
read owner state.

- Two-second forward input moved 9.3408 yards without a bonus and 18.3125 yards
  after consuming item 6372 through `UseContainerItem(0,10)`. Both samples stayed
  swimming at the same depth. The potion displayed its timed buff, applied aura
  7840, and raised authoritative swim speed from 4.722222 to 9.444444 yards/sec.
  The slight difference from an exact twofold distance reflects input timing.
- Natural potion expiry removed the buff and restored 4.722222 with no pending
  movement acknowledgements.
- Client-cast Aquatic Form displayed the aquatic model and buff, applied aura
  1066 and form 4, and set swimming speed to 7.083333. Casting it again toggled
  the form off, removed the aura, and restored 4.722222 with no pending replies.
- After disabling god mode, death while in Aquatic Form removed the form and
  restored 4.722222 at zero health. Client spirit release reached the graveyard,
  applied the ghost aura and its 5.902778 swim speed, and cleared both pending
  movement acknowledgements and the pending spirit-release transition.
- Observer packet delivery and snare transitions were validated by automated
  tests; this acceptance session used one graphical client.

Validation: `mix compile --warnings-as-errors`, `mix test.all` (2,928 passing),
`mix credo --strict` (zero issues), formatting, and diff checks.

Evidence is retained in:

- `/home/pikdum/.cache/thistle-wow-playtest.cwqZrT/screenshots/`
- `/tmp/thistle-speeds-server-final.log`
- `/tmp/thistle-speeds-normal-start.txt` and `-normal-end.txt`
- `/tmp/thistle-speeds-potion-start.txt`, `-potion-end.txt`, and `-potion-expired.txt`
- `/tmp/thistle-speeds-aquatic.txt` and `-cancelled.txt`
- `/tmp/thistle-speeds-dead.txt` and `-released.txt`
- `/tmp/thistle-speeds-tests-final.log` and `-credo-final.log`

An initial position was too close to shore for a clean swimming measurement;
only the later same-depth samples above count as movement acceptance. The
first item command used the wrong name; `.additem` supplied the actual potion.
The initial death command correctly refused while god mode was enabled.

No movement, aura, or owner errors appeared in the final server log. Existing
unimplemented housekeeping requests (account data, raid info, GM tickets,
query time, meeting stones, and cancel trade) remain unrelated protocol gaps.
