# Engineering control-device acceptance

Validated with native 1.12.1 build-5875 clients after these commits:

- `93988ced`: implement Gnomish Universal Remote and Mind Control Cap outcomes.
- `1ee9197b`: deliver root changes to the controller of a possessed creature.
- `3d82e13c`: attach charmed players without sending creature-pet requests.

## Reference and implementation

VMangos reference: `8f4e608450460efe1e38743e4da74397d4773a3a`,
`src/game/Spells/SpellEffects.cpp`, cases 8344 and 13180.

Universal Remote chooses equally between Control Machine (8345), Mobility
Malfunction (8346), and target-cast Enrage (8599). The cap chooses ordinary
charm (13181) with weight four, reversed charm with weight one, or no effect
with weight one. The reversed outcome does nothing when the original caster
has a shapeshift form. These choices use typed random-choice and triggered
spell effects, preserving the correct caster and target owner. The child
spells do not inherit an item GUID, matching the reference.

Shared spell and aura systems provide target admission, hit resolution,
channel ownership, control, movement, faction restoration, and expiry.
The parent item cast owns its ordinary item cooldown.

## Native setup

Debugmage (GUID 5) and Debugpaladin (GUID 2) used isolated GPU clients.
Existing level, god-mode, learning, profession, item, and teleport commands
prepared the characters. The mage equipped the actual remote (7506) and
cap (10726) with Engineering 300. Item uses came from `UseInventoryItem`.

Additional native casts used learned parent spells to exercise their random
outcomes without resetting item cooldowns or controlling the random source.
The movement regression used learned Mobility Malfunction followed by
Control Machine to reproduce the exact root/possession overlap reliably.
Tidewave only inspected live state; it did not mutate gameplay.

## Remote acceptance

The characters staged near Moonbrook at approximately
`{-10977, 1380, 46}` on map 0 and targeted Harvest Golems.

| Action | Client and authoritative result |
| --- | --- |
| Use the equipped remote | Enrage 8599 appeared on the target with the target itself as caster and a 120-second lifetime. |
| Immediately reuse the item | The client rejected reuse because the item was cooling down. |
| Native parent casts | Both other outcomes occurred: root 8346 for 20 seconds and channeled possession 8345 for 60 seconds. |
| Possession | The controller received the golem's camera, mover authority, minion portrait, attack button, and channel bar. The observer saw the channel and controlled creature. |
| Natural root expiry | Holder 8346 disappeared and authoritative root state cleared. |
| Root, possess, then move after root expiry on the fixed server | Keyboard input moved the golem from `{-10979.7109, 1364.1696, 45.7994}` to `{-10978.8311, 1371.7185, 46.1826}`, about 7.6 yards. The paladin stayed at `{-10977, 1380, 46}` and retained the possession channel. The client acknowledged unroot. |
| Natural possession expiry | The golem returned to faction 14, charmer 0, no pet owner, and no control aura. The paladin regained mover 2, no camera override, no channel, and no companion. |

The root/possession sequence originally left the client stuck after expiry:
the pure aura transition cleared root, but the event sink discarded the
creature's forced-unroot packet. The fix routes root and unroot only to the
current controller, while keeping ordinary/charmed creatures and nearby
observers out of that forced-movement packet path.

## Cap acceptance

The characters staged on Programmer Isle at `{16320, 16305, 69.444451}`
and `{16323, 16305, 69.444451}` and accepted a native duel.

| Action | Client and authoritative result |
| --- | --- |
| Use the equipped cap | The mage charmed the paladin with holder 13181, caster 5, and a 20-second lifetime. The mage received the command bar; the victim's actions were disabled. Both players stayed connected. |
| Inspect the item cooldown | The retained entry identified item 10726 and a deadline exactly 1,800,000 ms after its start. The head slot still held 10726 and Engineering remained 300. |
| Reuse before cooldown expiry | The client displayed "Item is not ready yet." |
| Natural charm expiry | Both owners cleared control and companion references, restored their own client mover, and accepted native movement again. |
| Paladin casts the learned parent; controller selects Stay | The mage was charmed by player 2. Holding the mage's movement key left its authoritative position unchanged at `{16332.4137, 16305, 69.4444}` while the aura remained active. |
| Paladin's fifth additional native parent cast | The backfire reversed control: holder 13181 on the paladin had caster 5, and the mage received the paladin's command bar. Both screenshots and owner snapshots recorded the reversed roles. |
| Backfire expires | Both owners cleared charm, possession, and companion state and returned to their own movers with no camera override. |
| Disconnect the charmed mage during a later cast | The paladin stayed connected and immediately cleared its companion and charm GUID. |
| Reconnect the mage | The saved and reloaded character had no charm, companion, or control aura, mover 5, and no camera override. The original item cooldown timestamps survived unchanged; native reuse still showed "Item is not ready yet." Native keyboard movement worked. |

The first cap duel exposed a separate attachment regression: a charmed
player was sent the creature-only `pet_controls` call and disconnected.
The fix publishes a player charm command bar directly while retaining
saved-control restoration for creatures. The final server run repeats the
actual item use after that fix.

## Evidence and checks

- Initial remote clients: `/home/pikdum/.cache/thistle-wow-playtest.24HNjp`
  and `/home/pikdum/.cache/thistle-wow-playtest.nzycWu`.
- Movement regression clients: `/home/pikdum/.cache/thistle-wow-playtest.eVOaA0`
  and `/home/pikdum/.cache/thistle-wow-playtest.gHqlxd`.
- Final cap clients: `/home/pikdum/.cache/thistle-wow-playtest.7XiOM8`
  and `/home/pikdum/.cache/thistle-wow-playtest.UQIyA9`.
- Mage reconnect client: `/home/pikdum/.cache/thistle-wow-playtest.Ic9Swc`.
- WoW's own AMD DRM counters were nonzero in all three runs. Final client
  processes were 2681834 and 2682644, plus reconnect process 2689441, on
  device `0000:0c:00.0`.
- Screenshots include `remote-item-enrage`, `remote-root-owner`,
  `remote-control-owner`, `remote-control-observer`, `fixed-unroot-moving`,
  `fixed-unroot-observer`, `cap-item-fixed`, `cap-roll3`, and `cap-roll5`.
- Owner snapshots: `/tmp/thistle-control-devices-remote-*.log`,
  `/tmp/thistle-control-devices-fixed-{rooted,moved,released}.log`, and
  `/tmp/thistle-control-devices-cap-*.log`.
- Server logs: `/tmp/thistle-control-devices-server.log`,
  `/tmp/thistle-control-devices-fixed-server.log`, and
  `/tmp/thistle-control-devices-complete-server.log`. The middle run retains
  the attachment crash described above. The final run has no server errors;
  its warnings are existing account-data and GM-ticket stubs.
- `mix test.all`: **7,388 passed**, 70.6 seconds;
  `/tmp/thistle-control-devices-complete-tests.log`.
- `mix compile --warnings-as-errors`: passed;
  `/tmp/thistle-control-devices-complete-compile.log`.
- `mix credo --strict`: no issues;
  `/tmp/thistle-control-devices-complete-credo.log`.

Automated tests exhaust every weighted outcome, the shapeshift exception,
caster/target ownership, single execution at effect index zero, dead targets,
actual DBC child spell behavior and expiry, possession channel dispatch,
controller-only root packets, and player charm command-bar projection.
The dependency ratchet passes without new allowlist entries.

The cap's no-effect outcome and shapeshift suppression were verified
deterministically in automated tests; the native random samples exercised
normal and reversed charm.

All helper-owned client services and retained test servers were stopped
after acceptance. Logs and screenshots were retained.
