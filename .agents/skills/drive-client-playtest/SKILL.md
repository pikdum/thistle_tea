---
name: drive-client-playtest
description: Launch and drive an isolated World of Warcraft 1.12.1 client against a local Thistle Tea server, including keyboard input, left/right clicks, camera drags, screenshots, real instance entry, log observation, and Tidewave runtime probes. Use for real-client gameplay acceptance, client-sensitive protocol or movement verification, reproducing live bugs, checking visibility and instance isolation, or validating a scripted content chain beyond automated tests.
---

# Drive Client Playtest

Exercise the genuine build-5875 client without disturbing the user's desktop, Steam session, or ordinary Wine prefixes. Treat client presentation, authoritative server state, and logs as separate evidence surfaces.

## Prepare

Read [references/thistle-tea.md](references/thistle-tea.md) before testing instance routing, timed scripts, or live BEAM state.

Define the exact acceptance facts before launching anything: character, content chain, initial and final world, expected position or packets, timing, copy isolation, and forbidden warnings. Prefer a fresh server for stateful instance or EventAI scenarios.

Start the server in a retained PTY:

```bash
mix run --no-halt
```

Keep `SPEC.md` and unrelated worktree changes untouched.

## Launch an isolated client

Use the bundled helper directly. It enters a one-off Nix shell when Xvfb, xdotool, or ImageMagick is unavailable.

```bash
.agents/skills/drive-client-playtest/scripts/wow-client launch
```

Record the printed session directory. Pass it to every later command:

```bash
playtest_session=/home/pikdum/.cache/thistle-wow-playtest.example
.agents/skills/drive-client-playtest/scripts/wow-client status "$playtest_session"
.agents/skills/drive-client-playtest/scripts/wow-client login-debug "$playtest_session"
```

The launcher must create a new Wine prefix and a private Xvfb display. Never point it at an existing prefix or the user's active display.

## Drive the client

Prefer semantic keyboard actions and stable UI frames. Capture a screenshot before using uncertain coordinates.

```bash
.agents/skills/drive-client-playtest/scripts/wow-client chat "$playtest_session" ".instance info"
.agents/skills/drive-client-playtest/scripts/wow-client key "$playtest_session" w
.agents/skills/drive-client-playtest/scripts/wow-client click "$playtest_session" right 650 430
.agents/skills/drive-client-playtest/scripts/wow-client click "$playtest_session" left 130 353
.agents/skills/drive-client-playtest/scripts/wow-client drag "$playtest_session" right 640 360 790 330
.agents/skills/drive-client-playtest/scripts/wow-client capture "$playtest_session" before-action
```

Coordinates are relative to the fixed 1280x720 client window. Recheck screenshots whenever the UI state changes. Use `/target Name` and the fixed target frame when a world model moves unpredictably.

## Verify the real path

Enter instances through the actual area trigger. Do not replace a required entry lifecycle with `.go ... <instance-map-id>`. Once inside a copy, omit the optional map argument from `.go xyz` so the current `WorldRef` is retained.

Use client diagnostics such as `.instance info`, `.instance data`, `.guid`, and `.debug position <guid>`. Correlate them with server logs and, when necessary, small Tidewave reads of the running BEAM. Do not add mutation commands merely to make acceptance easy.

For timed transitions, start a read-only sampler before triggering the client action. Capture the first authoritative change rather than sampling after a subsequent scripted movement has already begun.

Prove all relevant layers:

- the real client sent the intended action and displayed the result;
- the authoritative entity owner retained the expected world and state;
- projections, observers, and other instance copies behaved correctly;
- no owner, network, visibility, movement, or unsupported-command errors appeared.

## Finish

Stop the helper-owned client and X server while retaining logs and screenshots:

```bash
.agents/skills/drive-client-playtest/scripts/wow-client stop "$playtest_session"
```

Stop the retained server PTY. Keep evidence until the result is recorded. Trash the exact helper-owned session directory only after it is no longer needed; never clean a broad cache or temporary root.
