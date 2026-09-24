# Taunt lifecycle acceptance

Validated on 2026-09-24 with two native build-5875 clients against local commit
`6131070c`. This covers taunt selection and threat lifetime; it does not establish
general vanilla parity.

## Reference and implementation

The reference paths are VMangos `Unit::GetTauntTarget`, `Unit::TauntApply`,
`Spell::EffectTaunt`, and `ThreatManager::tauntApply` / `tauntFadeOut` under
`refs/vmangos/src/game/`.

- The newest valid taunt wins. An invalid caster is skipped even when it is the
  current victim; an earlier valid taunt can regain control.
- Taunt and druid Growl match the current victim's threat permanently. They do
  not copy a higher entry that has not taken aggro.
- Forced-attack auras borrow threat when their caster is below the current
  victim. Removing the caster's final taunt returns that amount while retaining
  threat earned in the meantime. Existing temporary modifiers are not replaced
  on application.
- Aura transitions own application and removal, `Threat` owns numeric changes,
  and `Engagement` remains the sole owner of victim changes. Reference removal,
  pruning, death, evade, and reset discard temporary state.

## Native setup

Debugdruid (guid 9) used Dire Bear Form; Debugbuyer (guid 10) used warrior stances.
Both were level 50 and used `.tgm` to prevent damage during extended observation.
Setup used native `.go`, `.modify rage`, and `.learn` commands. Taunt 355 and
druid Growl 6795 needed explicit learning because the debug trainer spell set
did not include them. No live BEAM state was mutated.

The selected level-51 Skeletal Flayer was guid `17379390991937511792`, near
`16193.2 16358.1 69.44` on map 451. Other nearby Flayers also received area shouts.
The recorded samples refer to this one owner. Read-only Tidewave sampling ran
every 100 ms. Both clients displayed target changes through the normal target
fields; a small native UI callback printed `UnitName("targettarget")` changes.

## Results

Challenging Roar borrowed 45.5 threat from the warrior. The druid's table entry
became 172.9, including 127.4 ordinary spell threat. Six seconds later the entry
was 127.4 and the temporary map was empty. The client displayed the druid as the
victim during and after the aura, consistent with the remaining higher threat.

Challenging Shout followed by Growl produced the client-visible sequence
`Debugdruid -> Debugbuyer -> Debugdruid -> Debugbuyer -> Debugdruid`. Screenshots
captured both debuffs together and the final victim history.

A repeated Mocking Blow / Growl sequence recorded the full owner timeline:

| Sample time | Active taunts | Victim | Druid threat | Warrior threat |
| --- | --- | --- | --- | --- |
| 1 ms | None | Warrior | 197.0 | 1822.4 |
| 2223 ms | Mocking Blow | Warrior | 197.0 | 1856.8 |
| 4952 ms | Mocking Blow, Growl | Druid | 1856.8 | 1856.8 |
| 7882 ms | Mocking Blow | Warrior | 1856.8 | 1856.8 |
| 8185 ms | None | Warrior | 1856.8 | 1856.8 |

Equal threat at 7882 ms proves that the remaining Mocking Blow selected the
warrior. Growl's permanent match survived expiry. Ordinary selection retained
the current warrior after the final aura ended. An earlier Mocking Blow run
also recorded a 93.0 temporary modifier alongside ordinary damage threat.

For invalid-caster fallback, the druid cast Growl and then used a native teleport
to map 0. The threat reference disappeared at 3944 ms. At 4853 ms the mob selected
the warrior while Growl was still present; the aura expired at 5055 ms. This
exercises the previously broken invalid-current-taunter case.

Both players then left combat and logged out. Final cleanup checks verified no
remaining taunts or temporary threat and an empty threat table on the reset mob.
The server log contained no validation failures, unsupported messages, or owner
errors. Both clients used AMD hardware rendering, verified with increasing
`drm-engine-gfx` counters in each WoW process.

## Evidence and automated checks

- Druid session: `/home/pikdum/.cache/thistle-wow-playtest.BOUXAr`
- Warrior session: `/home/pikdum/.cache/thistle-wow-playtest.P4S5Xj`
- Screenshots: `roar`, `growl-overlap`, `overlap-expired`,
  `repeat-growl-overlap`, `repeat-mocking-expired`, and
  `before-taunter-departure` / `after-taunter-departure` in the respective sessions.
- Server: `/tmp/thistle-taunt-server.log`
- Roar trace: `/tmp/thistle-taunt-overlap-probe.log`
- Complete overlap trace: `/tmp/thistle-taunt-mocking-complete.json`
- Departure trace: `/tmp/thistle-taunt-departure.json`
- `mix test.all`: 5725 passed, including real DBC Taunt, Growl, Challenging Shout,
  and Challenging Roar checks.
- `mix compile --warnings-as-errors`, `mix credo --strict`,
  `mix format --check-formatted`, and `git diff --check` passed.

The helper-owned clients and retained server were stopped after acceptance.
