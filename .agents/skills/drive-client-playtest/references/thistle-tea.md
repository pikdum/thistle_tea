# Thistle Tea real-client reference

## Local defaults

The helper defaults to:

- client directory: `/storage/games/World of Warcraft - Vanilla (Automation)`
- executable: `WoW.exe`
- realm list: `realmlist.wtf`, which must already point to localhost
- Proton: `/home/pikdum/.local/share/Steam/steamapps/common/Proton - Experimental`
- rendering: hardware OpenGL through headless Gamescope and its private Xwayland display
- software fallback: Xvfb displays 98 through 109
- resolution: 1280x720x24
- session root: `${XDG_CACHE_HOME:-$HOME/.cache}/thistle-wow-playtest.*`

Override defaults only with task-specific variables:

- `THISTLE_PLAYTEST_WOW_DIR`
- `THISTLE_PLAYTEST_PROTON_PATH`
- `THISTLE_PLAYTEST_CACHE_DIR`
- `THISTLE_PLAYTEST_RENDERER` (`gpu`, the default, or `software`)
- `THISTLE_PLAYTEST_DISPLAY_NUMBER` (software sessions only)

The launcher uses `umu-run`, a new `WINEPREFIX`, dummy audio, and `STEAM_COMPAT_MOUNTS=/storage`. GPU sessions unset inherited software-rendering overrides and run Gamescope with `--backend headless` at 1280×720 and 60 Hz. No window appears on the user's desktop. Required graphics tools are obtained with a one-off Nix shell when missing. A working systemd user manager is required for both rendering modes.

The helper writes the private display to `display`, the selected mode to `renderer`, and GLX hardware details to `renderer.log`. It rejects a software renderer in GPU mode. For native acceptance, also verify WoW's own GPU usage through its `/proc/PID/fdinfo` DRM counters; the compositor's renderer alone is not proof. Captures target the game window because a root-window capture is unavailable under rootless Xwayland.

The launcher does not edit `realmlist.wtf` or client files; the game can still save its normal settings. XKB warnings are harmless. A Proton game-drive warning can also be nonfatal; require the WoW window and a screenshot rather than judging launch from that line alone.

## Session ownership and cleanup

Each launch creates `thistle-wow-playtest.TOKEN.service` with `KillMode=control-group` and a five-second stop timeout. The directory stores the unit name and invocation ID. `stop` verifies both before asking systemd to terminate the owned cgroup. This includes Wine and Proton children that create their own process groups or sessions. Repeated stops are harmless. A stale directory cannot stop a replacement unit or send input to a reused display.

Use `wow-client status SESSION` and `systemctl --user show UNIT -p ControlGroup -p InvocationID` to inspect ownership. The host Steam process must be outside that cgroup. For legacy sessions without a unit record, inspect each candidate's saved PID/start time, command, and `WINEPREFIX` before stopping it individually. Never use `pkill wine`, `killall wineserver`, or broad Proton/Steam process matches.

Run the helper's cleanup regressions with:

```bash
.agents/skills/drive-client-playtest/scripts/test-cleanup
```

They create temporary services, exercise detached children, sibling survival, repeated cleanup, stale and mismatched ownership, legacy refusal, and failed-startup cleanup. Fixtures and logs remain under the printed temporary directory. Also run `bash -n` and ShellCheck on both scripts after changes. Native performance and isolation evidence is recorded in [the GPU playtest acceptance notes](../../../../docs/gpu-playtest-acceptance.md).

## Helper commands

```text
wow-client launch
wow-client status SESSION
wow-client window SESSION
wow-client focus SESSION
wow-client login-debug SESSION
wow-client chat SESSION TEXT
wow-client type SESSION TEXT
wow-client key SESSION KEY...
wow-client click SESSION left|middle|right X Y
wow-client drag SESSION left|middle|right X1 Y1 X2 Y2
wow-client capture SESSION [NAME]
wow-client stop SESSION
```

`login-debug` enters the local `debug/debug` account and presses Enter again after the character list loads. Confirm the selected debug character before relying on class-specific behavior.

## Reliable input patterns

Focus before each sequence. Open chat, pause briefly, type with a small per-character delay, then submit. Without the pause, the client may drop the first characters.

Use left button 1 and right button 3. Right-clicking an NPC opens gossip; left-clicking selects quest rows and buttons. Hold right-click and move the mouse to rotate the camera.

Static UI coordinates are more reliable than world-model coordinates. At 1280x720, the login fields and common gossip buttons are stable, but always capture and inspect the current screen before a consequential click.

## World and instance routing

`.go xyz <x> <y> <z> [map]` treats the fourth value as a map ID, not orientation.

- Use an explicit map only to move between open maps, such as reaching the Stratholme entrance from Programmer Isle.
- Omit the map inside an instance so the existing non-nil instance ID survives.
- Walk through the actual entrance trigger after moving near it. For Stratholme back entrance, use area trigger 2214 near `{3237.46, -4060.60, 112.01}` on map 0.
- Confirm `.instance info` before testing copy-sensitive content.

Useful Stratholme commands and locations:

```text
.character level 60
.tgm
.go xyz 3237.46 -4060.60 112.01 0
.instance info
.instance data 7
.go xyz 3680.53 -3643.80 140.03
.go xyz 4035.83 -3340.30 115.144
```

For the Aurius chain, add item 12845, accept quest 5122, and turn it in to set Stratholme field 7 to one before entering combat with Baron. A fresh field value of zero legitimately prevents action script 1044001.

## Live BEAM inspection

Use Tidewave only after the client and logs establish the live symptom. Keep expressions small and query existing public APIs first:

```bash
nix run github:albert-io/flakes.nix#tidewave-cli -- eval --timeout 30000 \
  'alias ThistleTea.Game.World; alias ThistleTea.Game.WorldRef; world = WorldRef.instance(329, 1); %{aurius: World.spawn_guid(world, :mob, 53297), baron: World.spawn_guid(world, :mob, 54241)}'
```

Use `Entity.pid/1` plus `:sys.get_state/1` as an interactive diagnostic only when public projections cannot explain owner-local state. Never put `:sys.get_state/1` into gameplay code or a player command.

For a narrow timed pose, poll the known owner at roughly 50 ms and retain only the initial pose, first changed pose, expected-pose timestamp, a later pose, and `Process.alive?/1`. Avoid returning hundreds of full entity states through Tidewave.

## Evidence hierarchy

Use all applicable surfaces:

1. client screenshot and visible behavior;
2. client diagnostic output for GUID, world, instance, and projected position;
3. server logs for the input packet and absence of relevant failures;
4. public runtime projections such as `World.position/1` and metadata;
5. focused Tidewave owner inspection for unresolved lifecycle details;
6. automated regression tests for deterministic copy isolation and packet assertions.

UI completion, packet receipt, projection updates, and owner state are distinct facts. Do not treat one as proof of all the others.
