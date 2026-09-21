# Emotes, posture, and interruption acceptance

Build 5875, September 20, 2026. Implementation: `fbeefe68`; Feign Death
transitions: `27f901b7` and `155cad1a`; channel target cleanup: `829bdaaf`;
pet possession ownership: `38ead707`.

All 3,968 tests pass, along with compilation with warnings as errors, strict
Credo, and formatting. The final client run used `38ead707`. No source changes,
builds, or test runs occurred while a playtest server was live.

## Behavior and ownership

`World.Loader.Emote` loads `Emotes.dbc` and `EmotesText.dbc` into ETS at startup.
Gameplay uses this catalog instead of a partial hardcoded text-to-animation
table. DBC `spec_proc` distinguishes persistent unit animation state from
one-shot animation packets. Scripted NPC emotes use the same definitions.

The three client message modules decode and dispatch to `Player.Emotes`.
`CMSG_EMOTE` accepts only the vanilla hardcoded commands 0 and 3.
`CMSG_TEXT_EMOTE` validates its catalog entry and target world, retains the
client's variation, broadcasts text within 25 yards, and preserves the NPC
receive-emote callback. Target names use UTF-8 byte lengths on the wire.

Pure `Logic.Emote` transitions enqueue typed animation, state, and text effects.
The usual resolver, event sink, and owner context project their packets and
unit updates. Dead, ghost, and animation-blocked actors cannot start emotes.
Persistent animation state survives stationary movement packets and turning;
translation clears it. Moving or turning stands the player up. Explicit posture
requests accept standing, sitting, sleeping, and kneeling, with an owner
acknowledgment. Sit, sleep, and kneel text emotes leave their posture to that
request. Standing removes auras that require sitting. Death and login clear
session animation and posture state.

Animations and explicit posture requests interrupt channels and auras whose
DBC masks include animation interruption. Channel cancellation removes auras
from the recorded channel target, even if selection or companion ownership has
changed. Possessing an existing pet retains its canonical companion identity,
progression, and summon projection. Release clears the possession state,
restores the player's mover and viewpoint, retains the pet monitor, and refreshes
the normal pet controls. Duplicate release notifications cannot detach that pet.

Feign Death now projects the vanilla dead-appearance dynamic flag `0x20`
through the shared aura transition. Final removal or expiry clears that flag
while preserving health, posture, and unrelated dynamic flags. Applying a
replacement holder does not repeat combat cleanup.

Reference behavior comes from local VMangos `ChatHandler.cpp`,
`MiscHandler.cpp`, `Unit::HandleEmote`, `Unit::SetStandState`,
`Unit::SetFeignDeath`, and `Player::ModPossessPet`, plus the build-5875 DBC rows.

## Real-client checks

Debughunter (GUID 7) and Debugbuyer (GUID 10) used separate accounts and isolated
clients in Northshire. Client commands and UI interaction performed all gameplay
mutations. Tidewave probes read owner and world state; packet tracing observed
the real codecs.

| Action | Client evidence | Authoritative evidence |
| --- | --- | --- |
| `/dance`, then turn in place | Observer saw the looping dance, including successive animation frames | Animation state 10 persisted; turning did not change position or clear it |
| Observer leaves and reenters visibility | Returning observer saw the existing dance | Persistent state was included in the newly visible unit |
| Walk forward | Hunter moved and stopped dancing | Position changed; animation state became 0 |
| Target Debugbuyer and `/wave` | Observer saw the wave and `Debughunter waves at you` | Animation 3 and text 101 carried actor GUID 7 and the target name |
| `/train` | Packet trace showed the catalog animation sent to both clients | Text 264 resolved to animation 275, outside the former hardcoded mapping |
| `/sit`, `/sleep`, `/kneel` | Observer saw each corresponding pose | Postures 1, 3, and 8 persisted through stationary packets; sitting remained after more than six seconds |
| `/stand` | Hunter returned to standing | Posture 0; DBC stand animation state 26 |
| Feign Death, then `/wave` | Observer saw the hunter collapse, then stand and wave | Health stayed 1,962; aura 5384 and dynamic flag 32 appeared, then cleared; posture remained 0 |
| Eyes of the Beast, then `/wave` | Channel and pet viewpoint ended; normal hunter camera and pet controls returned | Cast 1002 and both control auras cleared; active mover returned to 7; farsight and charm became 0; the same pet remained attached with its original summon spell, progression, and monitor |
| Move after possession release | Hunter moved normally | Player position advanced while the pet remained owned |
| `/dance`, logout, and login | Observer lost and regained the hunter, now standing normally | Logout removed the owner; login reset animation 10 to 0 with posture 0 |
| `/dance`, then `.die` | Observer saw death without a continued dance | Health became 0; animation and posture became 0 |
| Release, return to corpse, and click Accept | Normal world and living hunter returned | Ghost state and corpse were removed; animation remained 0 |
| Call Pet after resurrection | Normal companion returned | Hunter-pet ownership, monitor, and summon projection were restored; neither owner nor pet retained possession |

The initial client run exposed the old Feign Death implementation's use of
dead posture 7: the client treated it as actual death and suppressed the
attempted cancellation input. The corrected dynamic-flag projection passed in
two subsequent runs. Channel acceptance then exposed target recomputation and
pet-identity loss; both were fixed before the final run.

The client did not emit `CMSG_EMOTE` for `DoEmote("NONE")`; direct command
validation, cancellation, and dispatch are covered by automated tests. The live
animation/interruption checks used actual text-emote and posture packets.
While a ghost, the return-position developer command was sent through whisper
chat. Corpse reclamation used the visible Accept button.

Automated regressions also cover invalid IDs and postures, blocked actors,
Unicode names, cross-instance target rejection, NPC callbacks, owner-only
acknowledgments, selective channel interruption, food posture rules, Feign Death
replacement and expiry, pet process loss, and stale possession releases.

## Retained evidence

- Initial actor: `/home/pikdum/.cache/thistle-wow-playtest.BvVgo7`
- Initial observer: `/home/pikdum/.cache/thistle-wow-playtest.DqYacj`
- Initial observer screenshots: `dance-visible.png`, `reenter-dancing.png`,
  `reenter-dancing-second.png`, `wave-and-train.png`, `sitting.png`,
  `sleeping.png`, `kneeling.png`
- Final actor: `/home/pikdum/.cache/thistle-wow-playtest.auYQzo`
- Final observer: `/home/pikdum/.cache/thistle-wow-playtest.3iu4yd`
- Final actor screenshots: `possession-active.png`, `possession-released.png`,
  `actor-controls-restored.png`, `ghost-return-check.png`
- Final observer screenshots: `feign-active.png`, `feign-wave-cleared.png`,
  `reconnect-cleared.png`, `death-clears-dance.png`, `resurrected-standing.png`
- Packet traces: `/tmp/thistle-emote-packets.log`,
  `/tmp/thistle-emote-accepted-packets.log`
- State samples: `/tmp/thistle-emote-snapshots.log`,
  `/tmp/thistle-emote-control-snapshots.log`
- Final assertions: `/tmp/thistle-emote-final-proof.log`, `accepted: true`
- Final server log: `/tmp/thistle-emote-accepted-playtest.log`
- Gates: `/tmp/thistle-emote-final-all.log`,
  `/tmp/thistle-emote-final-compile.log`, `/tmp/thistle-emote-final-credo.log`,
  `/tmp/thistle-emote-final-format.log`

No server errors occurred in the final run. Both clients and the server were
stopped, with artifacts retained.
