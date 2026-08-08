# Instance data and Aurius playtest

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

## Known limits

- Condition 3758 and Stratholme field 5 remain unknown. The Baron callbacks
  that operate doors, resolve the timed run, remove auras, grant Ysida credit,
  and restore Aurius' quest-giver flag are not implemented.
- Tests can prove quest 5125's required condition and farewell gossip text,
  but the complete live turn-in path remains blocked on field 5.
- Command 6 teleport and other existing Aurius encounter gaps are separate
  coverage items.
- A later condition row in the same pure script batch does not observe an
  instance-data write from an earlier row in that batch.
