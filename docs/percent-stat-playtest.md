# Percentage stat modifiers

Aura 80 (`mod_percent_stat`) now participates in the shared stat recompute
pipeline. This enables the stat penalty from Resurrection Sickness, Sayge's
five stat fortunes, Invocation of the Wickerman's stamina bonus, Elune's
Blessing, Celebrate Good Times, and Festival Fortune.

Each stat is calculated as:

```
((base stat + item stat) * base percentages + flat aura bonuses) * total percentages
```

Independent percentage effects multiply within each layer. A holder's stack
count scales its percentage before multiplication. Selectors 0–4 affect one
stat and -1 affects all five; other selectors are ignored. Percentage factors
are clamped at zero, and the final stat is truncated once. Recomputing never
captures or changes the canonical base inputs. Creatures without base-stat
inputs retain their existing stats.

Health and mana maxima, attack power, weapon damage, and player combat ratings
are recalculated through the existing pipeline. Reduced maxima clamp current
resources; removing the penalty does not refill them.

The implementation follows `Aura::HandleModPercentStat`,
`Aura::HandleModTotalPercentStat`, `Unit::GetTotalStatValue`, and item-stat
application in `refs/vmangos/src/game/`. It also fixes the existing additive
stacking of total-stat percentages.

## Death persistence

Resurrection Sickness revealed that the shared death transition discarded
all non-passive auras. The loader now decodes the build-5875
`SPELL_ATTR_EX3_ALLOW_AURA_WHILE_DEAD` flag, and the death transition retains
those holders alongside passive ones. Their original expiry remains intact.
This follows `SpellEntry::IsDeathPersistentSpell` and
`Unit::RemoveAllAurasOnDeath` in the local reference.

## Automated acceptance

Coverage includes layer ordering, independent and stacked percentages,
single-stat and all-stat selectors, penalties, invalid selectors, changed
equipment and level inputs, idempotence, untouched creature base values,
resource clamping, player ratings, refresh, cancellation, death, release,
resurrection, and expiry while alive or dead. Retained periodic resource
auras continue advancing without damaging or restoring a corpse's resources.
DBC-tagged tests check all 18 vanilla spells containing aura 80, including
signed all-stat selectors and the death-persistence flag on sickness.

## Real-client acceptance

An isolated build-5875 client controlled Debugmage. All casts, buff
cancellation, spirit-healer choices, deaths, releases, and corpse recovery
entered through the client. Tidewave probes inspected the authoritative
player owner without changing gameplay state.

- At level 50, Sayge's Intelligence fortune changed intellect from 195 to
  214 and maximum mana from 3,693 to 3,978. Raw item intellect was 93 and
  base intellect was 102.
- Adding Arcane Intellect's 22 points and Blessing of Kings produced 260
  intellect and 4,668 maximum mana. Cancelling only Sayge's fortune restored
  intellect to 238 and maximum mana to 4,338, retaining both other buffs.
  The character sheet and resource bars reflected the changes.
- At level 11, the spirit-healer gossip and both confirmation dialogs
  applied one minute of Resurrection Sickness. With the existing equipment,
  stamina changed from 94 to 23, intellect from 128 to 32, maximum health
  from 912 to 202, and maximum mana from 1,855 to 415. The client displayed
  the debuff and reduced stats.
- A repeated healer resurrection was followed by `.die`. Sampling captured
  zero health with stamina still 23, the sickness holder still present,
  and its original expiry unchanged. The debuff also remained visible on
  the dead player's client. After expiry, ghost state had the original
  stats again; corpse recovery returned the character alive with 94 stamina,
  128 intellect, 912 maximum health, and 1,855 maximum mana, without sickness.

Exact expiry timing, resurrection before expiry, and no-refill behavior are
covered by deterministic tests. A second observer client was not used;
primary stats are private update fields.

The original automation client did not show the healer dialog despite a
correct outbound gossip packet. A separate copy with fresh WDB/WTF state
(retaining only the display configuration) and no copied addons displayed
it normally. No server change was needed for that setup issue, and the
original client files were left intact. The separate client copy is at
`/storage/games/Thistle-stat-playtest.RCwIPv`.

No gameplay owner errors or cast-validation failures appeared in the server
log. Login and client UI activity emitted existing unsupported account-data,
raid-info, GM-ticket, time-query, meeting-stone, and cancel-trade messages.
All helper-owned clients and the retained server were stopped.

## Evidence and final checks

- Initial buff evidence: `/tmp/thistle-percent-stat-client-{baseline,fortune,layers,cancelled}.txt`.
- Death and recovery evidence: `/tmp/thistle-percent-stat-client-{death-verified,recovery-verified,restored}.txt`.
- Buff screenshots: `/home/pikdum/.cache/thistle-wow-playtest.FeOtuc/screenshots/`.
- Resurrection screenshots: `/home/pikdum/.cache/thistle-wow-playtest.7VrPro/screenshots/`.
- Server log: `/tmp/thistle-percent-stat-server.log`.
- Validation: `/tmp/thistle-percent-stat-final-{tests,compile,credo}.log`.

`mix test.all` passed all 3,321 tests, `mix compile --warnings-as-errors`
passed, and `mix credo --strict` reported no issues.
