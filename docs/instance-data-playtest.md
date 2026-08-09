# Instance data and Aurius teleport playtest

Use a fresh server process so instance state starts empty.

1. Raise the test character to at least level 55 and add item 12845.
2. Reach the Stratholme back entrance in open map 0 near
   `{3237.46, -4060.60, 112.01}` and walk through area trigger 2214. Do not
   teleport directly to open map 329.
3. Run `.instance info` and confirm map 329 has a non-nil instance ID.
4. Run `.instance data 7` and confirm field 7 is zero.
5. Find Aurius near `{3680.53, -3643.80, 140.03}`.
6. Confirm the initial gossip text appears, quest 5122 is available, and quest
   5125 is not offered.
7. Accept and turn in quest 5122 with item 12845.
8. Confirm `.instance data 7` reports one and no owner process crashes or
   unsupported field-7 diagnostic appears.
9. Enter a separately owned Stratholme copy and confirm its field 7 remains
   zero.
10. Exercise the current Aurius/Baron EventAI path until script 1091703 or
    1044002 executes, then confirm field 7 becomes two. Record unrelated
    encounter blockers without widening this slice.
11. Leave and re-enter the first copy before its five-minute timeout and
    confirm its value is retained.
12. Empty and reset that copy, create a new one, and confirm field 7 starts at
    zero.

Watch the server log for instance-owner crashes, stale projection rows,
commands applied to open map 329, and unsupported field-7 diagnostics.

## Aurius teleport acceptance

Use a fresh server and enter Stratholme through area trigger 2214. Do not
teleport directly to an open map-329 world.

1. Run `.instance info` and record the non-nil map-329 instance ID.
2. Find Aurius near `{3680.53, -3643.80, 140.03}`.
3. Target him, run `.guid`, and record his runtime GUID.
4. Run `.debug position <guid>` and confirm the initial projected position is
   near `{3680.53, -3643.80, 140.03}` in the instance from step 1.
5. Reach Baron Rivendare and enter combat. Baron action script 1044001 should
   forward generic script 10917 to Aurius' owner.
6. At about ten seconds, confirm Aurius' faction, NPC flags, and stand-state
   presentation changes do not crash either owner.
7. At about eleven seconds, run `.debug position <guid>` again and confirm
   `{4032.73, -3366.51, 115.063}`, orientation about `5.42797`, and the same
   instance ID.
8. Confirm a client near the Baron-room destination sees Aurius appear without
   reconnecting. A second client in the same copy can watch the old and new
   visibility sides simultaneously.
9. Confirm a character in another Stratholme copy neither sees Aurius nor
   receives his relocation.
10. Let the delay-12 step run and confirm Aurius remains active and attempts
    movement from the teleported pose.
11. Watch logs for `unsupported command 6`, `ai_script_steps crashed`, stale
    spline warnings, visibility errors, or owner/network termination.

The Baron door may remain closed and the later command-3 path may fail there.
The acceptance point is Aurius' exact same-copy relocation at eleven seconds,
not completion of quest 5125 or the Baron encounter.

## Open-world smoke checks

When practical, also observe one imported open-world path:

- Jesse Halloran's upstairs/downstairs sequence should not snap back to its old
  spline or disappear into another world.
- Tyrion's Spybot failure reset should relocate the Spybot owner, not the
  initiating NPC or player.
- Highlord Taelan Fordring's respawn path should execute command 6 without an
  unsupported-command log.

## Known limits

- Condition 3758 and Stratholme field 5 remain unknown. The Baron callbacks
  that operate doors, resolve the timed run, remove auras, grant Ysida credit,
  and restore Aurius' quest-giver flag are not implemented.
- Tests can prove quest 5125's required condition and farewell gossip text,
  but the complete live turn-in path remains blocked on field 5.
- Stratholme field 5, closed-door callbacks, the Baron timer, Ysida credit, and
  Aurius' quest-giver restoration remain outside the creature-teleport slice.
- Aurius' delay-12 command-3 path can still be blocked by the closed Baron door.
- A later condition row in the same pure script batch does not observe an
  instance-data write from an earlier row in that batch.
