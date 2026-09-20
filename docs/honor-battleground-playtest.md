# Battleground kill credit client acceptance

Build 5875, September 20, 2026. Implementation: `4db13f08`; exit cleanup:
`fb3a6dd3`; worldport acknowledgement cleanup: `35f7da6a`.
The final implementation passed all 3,852 tests, compilation with
warnings as errors, strict Credo, and formatting.

## Team sharing and pet credit

Level-60 Debugpaladin (2), Debughunter (7), and Debugshaman (8) entered the
same Warsong instance through their clients. None belonged to a normal party.
Developer commands supplied levels, positions, health, and Death Touch for
reproducible lethal hits. Ordinary client spell casts and `PetAttack()` supplied
the attacks; runtime probes only read state.

| Shaman death | Paladin scoreboard KB / HK | Paladin honor | Hunter scoreboard KB / HK | Hunter honor |
| --- | --- | --- | --- | --- |
| Paladin spell kill | 1 / 1 | 94 | 0 / 1 | 94 |
| Hunter pet kill | 1 / 2 | 178 | 1 / 2 | 178 |
| Hunter spell kill beside dead paladin | 1 / 3 | 178 | 2 / 3 | 328 |

The hunter dealt no damage on the first kill. The second killing source was
the Prairie Wolf Alpha's GUID, while the scoreboard credited its owner. Both
players received the two-member team share and their individual repeat penalty.
On the third kill, the dead paladin received a scoreboard HK but no honor or
honor-ledger HK. Its lifetime ledger stayed at two kills; the hunter reached
three. The shaman's deaths reached three.

The pet initially remained at the setup teleport's elevated height. Dismissing
and recalling it from the grounded hunter allowed ordinary combat. Two paladin
setup casts hit itself after its target was cleared; those deaths correctly
added no killing blows or HKs. Subsequent casts explicitly verified the target.
The hunter also died once during setup. Automatic graveyard resurrection
interrupted the attempted released-corpse distance test; that specific fallback
has automated coverage. The successful client case used a nearby dead body.

## Spirit of Redemption

Debugpriest (4) learned the passive talent and entered the same match. After
the paladin and hunter left, the priest picked up the Horde flag through the
client. The shaman targeted the priest and cast Death Touch.

A 100 ms read-only sampler observed these transitions:

| State | Priest health / deaths | Shaman KB / HK / honor | Horde flag |
| --- | --- | --- | --- |
| Before hit | 2,087 / 0 | 0 / 0 / 0 | Carried |
| Spirit form | 2,087 / 0 | 1 / 1 / 188 | Dropped |
| About 10 seconds later | 2,087 / 0 | 1 / 1 / 188 | Returned to base |
| 15.002 seconds after initial credit | 0 / 1 | 1 / 1 / 188 | At base |

The clients showed the spirit model, flag-drop announcement, immediate killer
credit, and delayed victim death. No second honor award or killing blow occurred.
Owner state, saved character projections, and the realm ledger agreed; consumed
damage histories were empty.

## Exit follow-up

The initial run exposed a dead-player exit bug: leaving the match could retain
death or ghost state. VMangos resurrects dead participants and removes Spirit
of Redemption before returning them. The follow-up routes voluntary, trigger,
and timed exits through one player-owned cleanup, removes the corpse, restores
dead players and ghosts, and cancels the form without scheduling its suicide.
Living players retain their current health and resources.

The first follow-up exposed a second defect: a root/unroot acknowledgement
could replace the new-map destination with the old battleground coordinates
while the client loaded. The priest fell at those coordinates on map 0. The
worldport fix rejects movement reconciliation during loading, discards old
acknowledgements when sending the new world, and cancels pending graveyard
teleports. Regression tests cover acknowledgements before and after world entry.

A fresh client and server validated three separate solo match lifecycles after
the worldport fix. The existing `.bg leave` developer command exercised the
player exit boundary; dead and ghost characters sent it by self-whisper.

| Exit state | Verified result |
| --- | --- |
| Active Spirit of Redemption | Original open-world position, 2,087 health and 4,111 mana, normal model, no spirit auras or root; stable for more than 24 seconds |
| Dead, before spirit release | Same return position and full resources, alive, no ghost or spirit auras |
| Released ghost | Ghost flag and aura removed, full resources, corpse removed, correct return position |

The final character walked 1.75 yards after returning, proving client movement
was restored. All three match processes disappeared and their worlds contained
zero entities. The final server log had no error-level, unsupported-message,
or failed-validation entries. Both client and server were stopped afterward.

## Evidence

- Initial server: `/tmp/thistle-bg-kills-playtest.log`.
- Paladin: `/home/pikdum/.cache/thistle-wow-playtest.7VDlVf`, screenshots
  `bg-team-kill-score.png`, `bg-pet-kill-score.png`, and
  `bg-dead-teammate-credit.png`.
- Hunter: `/home/pikdum/.cache/thistle-wow-playtest.kzGt2K`.
- Shaman: `/home/pikdum/.cache/thistle-wow-playtest.rjO9Tk`, screenshots
  `bg-spirit-initial-score.png` and `bg-spirit-final-score.png`.
- Priest: `/home/pikdum/.cache/thistle-wow-playtest.biQura`, screenshots
  `bg-spirit-initial.png` and `bg-spirit-final-death.png`.
- State probes: `/tmp/thistle-bg-kills-pet-state.log`,
  `/tmp/thistle-bg-kills-dead-state.log`, and
  `/tmp/thistle-bg-kills-final-ledger.log`.
- Spirit timeline: `/tmp/thistle-bg-kills-spirit-timeline.log`.
- Final exit server: `/tmp/thistle-worldport-ack-playtest.log`.
- Final exit client: `/home/pikdum/.cache/thistle-wow-playtest.hicwE7`, with
  `exit-active-spirit.png`, `exit-spirit-returned.png`,
  `exit-dead-before-leave.png`, `exit-dead-returned.png`,
  `exit-ghost-before-leave.png`, `exit-ghost-returned.png`, and
  `exit-movement-restored.png`.
- Final exit probes: `/tmp/thistle-worldport-ack-spirit-timeline.log`,
  `/tmp/thistle-worldport-ack-dead-state.log`,
  `/tmp/thistle-worldport-ack-ghost-state.log`, and
  `/tmp/thistle-worldport-ack-cleanup.log`.
- Final checks: `/tmp/thistle-worldport-ack-{all,compile,credo,format}.log`.

The initial run produced no error-level server logs. Its clients and server
were stopped before implementing the exit follow-up.
