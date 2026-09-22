# GPU rendering and isolated playtest cleanup

## Launcher behavior

`wow-client launch` now starts a private headless Gamescope/Xwayland display and
uses hardware OpenGL by default. Gamescope owns a 1280×720 output at 60 Hz. Each
session still has a fresh Wine prefix, dummy audio, retained screenshots, and a
local-server realm-list check. The helper captures the game window; root-window
capture does not work with rootless Xwayland.

`THISTLE_PLAYTEST_RENDERER=software` explicitly selects the previous Xvfb and
llvmpipe route. GPU mode records `glxinfo -B` output and rejects software
rendering. Missing graphics utilities are supplied by a temporary Nix shell;
no system configuration or global package installation was needed.

Both modes run inside a unique systemd user service with
`KillMode=control-group`. The service name and invocation ID are saved in the
session directory. Cleanup checks both, stops only that unit, and includes
children that detached from their original process groups. A five-second stop
timeout bounds cleanup. Failed startup receives the same cleanup. Software
launches wait for their own Xvfb readiness notification before publishing the
display to input helpers.

Stale ownership records cannot stop a replacement service or send input to a
reused display. Legacy sessions without ownership records require individual
inspection; the helper does not fall back to broad Wine or Steam process
matching. Logs and screenshots remain after stopping a session.

The implementation uses Gamescope's [headless backend](https://github.com/ValveSoftware/gamescope/blob/master/src/main.cpp)
and systemd's cgroup ownership rather than tracking launcher process groups.

## Native rendering and input acceptance

Tested on the local RX 7900 XT with Gamescope 3.16.28, Mesa 26.2.2, Proton
Experimental, and the native WoW build-5875 client. GLX reported the AMD
hardware renderer and `Accelerated: yes`. The WoW process itself opened
`/dev/dri/renderD128`; its AMD graphics-engine counter increased from
5,056,126,817 to 5,609,580,810 ns during the GPU sample, independently confirming
game rendering on the GPU.

The helper completed login, chat input, mouse clicking, screenshots, camera
right-dragging, and forward movement on the private display. Debugwarlock moved
from Programmer Isle's seed position to
`{16307.016602, 16314.839844, 69.440002}`. Owner and public positions agreed.
A Gamescope/libei sync-event warning appeared, but the tested input operations
continued to work.

### CPU comparison

The same level-50 character and view on Programmer Isle were sampled for 15
seconds in each mode at 1280×720. CPU measurements include each playtest's entire
cgroup: game, Wine/Proton runtime, and display server/compositor. They exclude the
Thistle Tea server and other applications. FPS values are nearby native
`GetFramerate()` observations, not averages over the CPU sampling window.

| Mode | Elapsed | CPU time | CPU use, one core = 100% | Observed FPS |
| --- | --- | --- | --- | --- |
| GPU / Gamescope | 15.009 s | 5.904 s | 39.3% | 59 |
| Software / Xvfb | 15.018 s | 120.659 s | 803.4% | 14 |

GPU mode used approximately 95% less CPU in this scene while rendering more
frames. These are local acceptance measurements, not a general benchmark. This
client did not expose a `maxfps` CVar; the comparison did not rely on a claimed
software frame cap.

## Cleanup acceptance

The regression script creates temporary services and verifies:

- Detached children, including a child with its own session ID, are removed.
- A sibling service survives and repeated cleanup succeeds.
- A saved invocation ID cannot stop a replacement service with the same name.
- A mismatched unit name cannot target another session.
- Legacy sessions without ownership metadata are refused.
- A failed compositor launch removes its detached child and preserves siblings.

Native acceptance also stops one complete software session while a GPU session
remains available, then stops the GPU session while a second software session
remains available. Every PID recorded from the stopped cgroup is checked for
removal, and the surviving client is captured after each stop. The host Steam
process remained the same process across the software cleanup check.

An earlier Steam shutdown was observed while no playtest stop command was
running. Its cause was not established; it is not evidence for or against the
new cleanup behavior. The cleanup claims above come from the controlled checks.

## Screenshot capture follow-up

The subsequent [binary spell playtest](binary-spells-playtest.md) exposed stale
OpenGL frames from X11 window capture. Gameplay and GPU rendering continued,
but repeated captures could show a previous frame. GPU screenshots now use
Gamescope's `screenshot` command on the session's recorded socket, with a unique
temporary path and completion check before publishing the image. Software
captures continue to use the game window. The compositor command is defined in
[Gamescope 3.16.28](https://github.com/ValveSoftware/gamescope/blob/3.16.28/src/steamcompmgr.cpp).

A fresh GPU client in `/home/pikdum/.cache/thistle-wow-playtest.G07DZd` verified
three successive account-field values (`CAPTURE_A`, `CAPTURE_B`, `CAPTURE_C`).
Each capture showed the current value and a new animation frame, including an
overwrite of the second output path. Retained images are `screenshots/frame-a.png`
and `screenshots/frame-b.png` (the latter now shows `CAPTURE_C`). Capture after
session cleanup was refused. Bash syntax, ShellCheck, skill validation, and all
cleanup regressions passed again; the fresh client was stopped.

## Final validation

Bash syntax checks, ShellCheck, the cleanup regressions, and skill validation all
passed. The repository passed all 4,840 tests with `mix test.all`, compiled with
`--warnings-as-errors`, and passed `mix credo --strict` with no issues. All owned
playtest clients, display servers, and the local acceptance server were stopped
after validation.

## Retained evidence

- GPU session: `/home/pikdum/.cache/thistle-wow-playtest.kKZJaq`.
- Software comparison: `/home/pikdum/.cache/thistle-wow-playtest.uJSHGb`.
- Software readiness and sibling check: `/home/pikdum/.cache/thistle-wow-playtest.N2pPD0`.
- CPU samples: `/tmp/thistle-{gpu,software}-cpu.txt`.
- WoW hardware counters: `/tmp/thistle-gpu-fd-{before,after}.txt`.
- Runtime input probe: `/tmp/thistle-gpu-input-state.txt`.
- Native cleanup results: `/tmp/thistle-{gpu,software}-stop.txt`.
- Cleanup regressions: `/tmp/thistle-playtest-cleanup-tests.log`.
- ShellCheck: `/tmp/thistle-playtest-shellcheck.log`.
- Skill validation: `/tmp/thistle-playtest-skill-validation.log`.
