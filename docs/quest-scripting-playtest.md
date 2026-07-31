# Quest scripting playtest guide

Use a fresh server process for this pass. Runtime quest, spawn, and character
state is intentionally ephemeral, so restarting is the clean reset between
scenarios.

The useful debug commands are:

```text
.go xyz <x> <y> <z> [map]
.addquest <quest_id>
.guid
.pid
.pos
.modify hp <value>
.tgm
```

Select an NPC or game object before using `.guid` or `.pid`. Keep the server
console visible so script crashes, unsupported-command messages, and owner
process exits are obvious.

## Fast smoke matrix

### Script-spawned game object: quest 308

1. Restart the server.
2. Run `.go xyz -5605.96 -544.45 392.43 0`.
3. Accept “Distracting Jarven” from Jarven Thunderbrew, or use
   `.addquest 308`.
4. Complete and turn in the quest normally.
5. Confirm the Unguarded Thunder Ale Barrel appears for 60 seconds and then
   disappears.
6. Leave and re-enter the cell after it disappears. Confirm the negative-spawn
   object does not incorrectly become a permanent default spawn.

### Scripted equipment and ordered delays: quest 112

1. Run `.go xyz -9460.30 31.94 57.05 0`.
2. Accept and complete “Collecting Kelp,” or use `.addquest 112` before doing
   the normal objective.
3. Turn it in to William Pestle.
4. Confirm his main-hand and off-hand visuals change immediately.
5. Six seconds later, confirm the scripted slots clear while any `-1` slot is
   preserved.

### Invincibility health floor: quest 590

1. Run `.go xyz 2126.64 1305.95 53.95 0`.
2. Accept “A Rogue’s Deal” from Calvin Montague.
3. Attack Calvin and confirm his health cannot fall below 5% while the script
   floor is active.
4. Confirm damage events continue without death, corpse creation, quest tap
   completion, or owner-process restart.

### Scripted door: quest 6482

1. Run `.go xyz 3347.35 -694.70 159.93 1`.
2. Accept “Freedom to Ruul” from Ruul Snowhoof.
3. Confirm the DB-guided cage door opens.
4. Wait 30 seconds and confirm it returns to its prior state.
5. Repeat inside an instance copy if applicable; confirm the command changes
   only the game object in that world copy.

### Game-object activation: quest 848

1. Run `.go xyz -424.54 -2589.88 95.91 1`.
2. Complete and turn in “Fungal Spores” to Apothecary Helbrim.
3. Confirm the addressed game object activates through its owner. For a trap,
   confirm the configured spell uses the player as the script user; for a
   non-trap, confirm the object state toggles once.

### Escort map event: quest 648

1. Run `.go xyz -8851.94 -4374.93 44.65 1`.
2. Accept “Rescue OOX-17/TN!” from the Homing Robot.
3. Follow the full route and confirm waypoint dialogue, ambush summons,
   attack-start commands, map-event target tracking, and completion credit.
4. Repeat and let the robot die or move more than 80 yards away. Confirm the
   failure script fails the quest once and stops later delayed steps.

### Long delayed termination: quest 5713

1. Run `.go xyz 4390.68 -67.31 86.72 1`.
2. Accept “One Shot. One Kill.” from Sentinel Aynasha.
3. Confirm the event-active condition keeps the delayed chain running while
   the map event is alive.
4. Force the event to fail and confirm the 49/99/119-second termination checks
   prevent later batches.
5. The spell-list swap itself remains in the blocked inventory; do not count
   its absence as a regression in the termination chain.

## Regression checks

- Run each delayed scenario twice without restarting and confirm stale timers
  from the first run do not mutate a replacement entity.
- For pooled objects, confirm scripted removal does not immediately restart the
  member through the supervisor.
- For nearest-entry object commands, place two matching objects at different
  distances and confirm only the nearest in-range object changes.
- For DB-guided spawns in an instance, verify the open-world object is
  unchanged.
- Relog during a timed quest and confirm the current runtime-only behavior is
  explicit; no durable timer persistence is expected.
- Watch for `unsupported`, `ai_script_steps crashed`, duplicate entity, and
  stale registry messages in the server log.
