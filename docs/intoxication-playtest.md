# Alcohol intoxication

Alcohol items now execute spell effect 100 through the shared spell-effect
pipeline. Each point adds 256 to the player's inebriation value, clamped to
0–65535. Negative amounts support Sober Up. Logged-in players sober by 256
every ten seconds, including while stationary with full resources. Additional
drinks preserve the existing deadline; delayed ticks apply one pulse rather
than a burst of catch-up work. Death clears both alcohol and its deadline.

The existing `PLAYER_BYTES_3` projection carries inebriation while preserving
gender and honor fields. The build-5875 client supplies messages and visual
effects. Its message bands differ from VMangos's named server states, so this
implementation does not duplicate those labels.

References: `Spell::EffectInebriate`, `Player::HandleSobering`,
`Player::SetDrunkValue`, and `Player::SetDeathState` in `refs/vmangos/`.

## Automated validation

- `mix test.all`: 2,938 passing.
- `mix compile --warnings-as-errors`, `mix credo --strict`, formatting, and
  diff checks passed.
- Regression coverage includes item-spell strengths from real DBC rows,
  negative amounts, saturation, packed player fields, repeated drinks,
  monotonic timestamps, idle scheduling, delayed ticks, restored state,
  non-player exclusion, and the shared death transition.

## Real-client acceptance

Used Debugshaman on Programmer Isle in an isolated build-5875 client. Existing
`.additem` commands supplied Thunder Ale (2686) and Cuergo's Gold with Worm
(9361). All drinking used client `UseContainerItem` calls; owner probes were
read-only.

- Thunder Ale followed `CMSG_USE_ITEM` into Weak Alcohol (11007). The client
  displayed “You feel tipsy. Whee!” (`first-drink.png`). A subsequent owner
  sample showed 1024 after the first sobering pulse.
- Standing still returned the value to zero with no sobering deadline, and
  the client displayed “You feel sober again.” (`naturally-sober.png`).
- Potent Alcohol (11629) initially produced 12800. Repeated drinks accumulated
  to sampled values 24832, 36096, and 47872 despite intervening sobering pulses.
  The client displayed “You feel drunk. Woah!” and pronounced scene blur
  (`repeated-drink.png`, `third-drink.png`, `fourth-drink.png`).
- An eleven-second read-only sample observed 24576 → 24320, with the next
  sobering deadline advancing by approximately ten seconds.
- `.die` at high intoxication produced health 0, alcohol 0, and a nil deadline.
  The death dialog appeared and the blur disappeared (`death-clears-alcohol.png`).
- Clicking Reincarnation resurrected the character with alcohol still zero
  and no sobering deadline (`resurrected-sober.png`).

No gameplay or owner errors appeared in the server log. Existing unimplemented
account-data, raid-info, GM-ticket, query-time, and meeting-stone requests were
unrelated to drinking. A long diagnostic sampling request timed out; the
shorter eleven-second sample above completed successfully. Observer delivery
was not separately exercised with a second graphical client.

Evidence:

- `/home/pikdum/.cache/thistle-wow-playtest.1BuAhy/screenshots/`
- `/tmp/thistle-alcohol-server.log`
- `/tmp/thistle-alcohol-first.txt`, `-sober-state.txt`, `-potent.txt`,
  `-repeated.txt`, `-third.txt`, `-fourth.txt`, `-sobering-pulse.txt`,
  `-death.txt`, and `-resurrected.txt`
- `/tmp/thistle-alcohol-tests-final.log` and `-credo-final.log`
