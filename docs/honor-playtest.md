# Player honor client acceptance

Build 5875, September 20, 2026. Implementation: `cbc354a4`.
All 3,817 tests, compilation with warnings as errors, strict Credo, and format
checks passed before this run. The ordinary inspection acknowledgement found
missing during this run is covered by the subsequent protocol fix.

## Setup

Three isolated clients used the seeded level-50 characters Debugpaladin (2),
Debugshaman (8), and Debughunter (7). They met near `{-9000, -450}` in open
map 0. Developer commands positioned the characters, lowered victim health,
and taught the paladin Fireball for reproducible spell kills. The clients
sent ordinary spell casts and pet commands; Tidewave probes only read state.

The shaman used Reincarnation after the first death and normal spirit release
and corpse retrieval for later deaths. The paladin logged out and back in
after the second credited kill. The hunter joined the paladin's party before
the pet kill. Its Prairie Wolf Alpha dealt the damage; neither player attacked
during that kill.

## Results

| Action | Paladin result | Hunter result |
| --- | --- | --- |
| First opposing level-50 player kill | 1 HK, 179 honor | Not present |
| Second kill of the same victim | 2 HK, 340 honor; second award 161 | Not present |
| Logout and login | 2 HK, 340 honor retained | Not present |
| Third ordinary kill | 3 HK, 483 honor; third award 143 | Not present |
| Kill after victim changed to level 1 | No additional kill or honor | No credit |
| Pet kill after victim returned to level 50 | 4 HK, 545 honor; party share 62 | 1 HK, 89 honor |

The 62/89 split matches equal two-member party shares with separate victim
repeat penalties. The paladin received credit despite dealing no damage in
the pet kill. The owner state, honor ledger, and saved character projection
agreed. Victim damage history was empty after each observed death. The level
change also updated the ledger profile, so gray-target rejection used the
current level.

The clients showed the floating `HK: Scout` credit and updated today's and
lifetime kill counts. The hunter's Honor inspection tab showed the paladin's
three kills and 483 honor before the party kill.

The stock Honor panel caches yesterday/weekly rows until world entry. This
was confirmed by extracting `Interface/FrameXML/HonorFrame.lua` from the
client's `patch.MPQ`: `HonorFrame_Update(updateAll)` only refreshes those rows
when `updateAll` is set, and ordinary kill events call it without that flag.
The client API already returned `2 / 340` before reconnect, and reconnect
displayed those values in the panel. The final paladin screenshot also uses the existing
`HonorFrame_Update(1)` display refresh; it does not alter gameplay state.

An attempted manual Honorless Target setup did not apply the aura. That kill
was an ordinary third kill, not evidence of Honorless Target acceptance.
Automated tests cover the aura snapshot before death cleanup; client testing
of the aura remains with the world-entry integration.

## Evidence

- Server log: `/tmp/thistle-honor-playtest.log`.
- Paladin session: `/home/pikdum/.cache/thistle-wow-playtest.KqlOSD`.
  Screenshots: `honor-zero.png`, `honor-first-kill.png`,
  `honor-second-refreshed.png`, `honor-reconnect.png`,
  `honor-gray-dead.png`, and `honor-final-paladin.png`.
- Shaman session: `/home/pikdum/.cache/thistle-wow-playtest.jBz9rO`.
  `honor-victim-dead.png` shows the Reincarnation option.
- Hunter session: `/home/pikdum/.cache/thistle-wow-playtest.yCzVXQ`.
  Screenshots: `honor-inspected-paladin.png` and `honor-pet-kill.png`.
- Extracted client UI source: `/tmp/thistle-patch.MPQ-HonorFrame.lua`.

No owner crashes, honor failures, or packet-encoding errors appeared. Ordinary
inspection emitted an unimplemented `CMSG_INSPECT` warning even though its
Honor tab worked; the follow-up adds the vanilla `SMSG_INSPECT` acknowledgement
and shares the existing distance/hostility admission checks. All three clients
and the server were stopped after the run; screenshots and logs were retained.

## Inspection follow-up

Commit `972b8fa0` passed all 3,818 tests, compilation with warnings as errors,
strict Credo, and formatting. A fresh server and two fresh clients then
repeated ordinary inspection and opened the Honor tab.

Diagnostic tracing recorded the client's `CMSG_INSPECT` payload for GUID 2
and the server's matching `SMSG_INSPECT` encoding, both
`02 00 00 00 00 00 00 00`. The Honor tab rendered correctly. The new server
log had no unimplemented inspection warnings or errors.

- Server log: `/tmp/thistle-honor-inspection-playtest.log`.
- Packet trace: `/tmp/thistle-inspection-packets.log`.
- Inspector session: `/home/pikdum/.cache/thistle-wow-playtest.Rtks06`, with
  `inspect-acknowledged.png` and `inspect-honor.png`.
- Target session: `/home/pikdum/.cache/thistle-wow-playtest.8XtHhC`.
- Final gate logs: `/tmp/thistle-honor-inspection-{all,compile,credo,format}.log`.

Both clients and the server were stopped after verification.
