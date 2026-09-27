# Gnomish Death Ray

Implementation: `35f3672e`. Channel timing correction: `e8b24871`.

The shared casting lifecycle now supports a compiled channel-start trigger.
Gnomish Death Ray activates its charging aura through this owner-local path,
including the self-targeted activation sent by the native item client.
Periodic auras retain accumulated damage alongside their tick counters, and
the existing aura transition emits the discharge only on natural expiry.
The accumulator merges into current aura state without restoring consumed
shields or removed holders.

The charging aura rolls 100–500 once per application. Each tick while the
Death Ray channel remains active contributes that base amount before received
modifiers and mitigation. Immunity prevents both damage and accumulation;
absorption reduces health loss without reducing the stored charge. Interruption
stops further charging, but the partial charge still fires at natural expiry.
The ray uses the current selection at expiry. Missing or dead recipients,
death, manual removal, and an empty charge cannot produce a discharge.

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`src/scripts/spells/spell_item.cpp` (`GDRChannelScript`,
`GDRPeriodicDamageScript`), `SpellAuras.cpp::PeriodicTick`, and
`sql/migrations/20250407071532_world.sql`. Item 10645 uses channel 13278,
which starts charging aura 13493 and eventually releases damage spell 13279.
The item retains its five-minute cooldown and 20-yard activation range.

## Timing regression

An initial native cast delivered the charging aura 14 ms after channel
activation. Its fourth tick then fell after the channel ended, producing only
three contributions. Application now anchors its tick and expiry times to the
active channel's start. A regression applies the aura 14 ms late and proves
all four contributions occur before channel completion. Transition processing
still uses the current owner time.

## Verification

`mix test.all --seed 2781` passed all **7,072 tests**. Compilation with warnings
as errors, strict Credo, formatting, and whitespace checks passed. No
architecture allowlist was expanded.

Tests cover self-targeted activation, one-time channel-start triggering,
random amount bounds, complete and interrupted charging, inactive or unrelated
casts, current target selection, shields, immunity, death, removal, refresh,
delayed delivery, missing/dead recipients, and the actual DBC/VMangos chain.

Gate logs:

- `/tmp/thistle-death-ray-accepted-all.log`
- `/tmp/thistle-death-ray-verified-compile.log`
- `/tmp/thistle-death-ray-verified-credo.log`
- `/tmp/thistle-death-ray-commit.log`
- `/tmp/thistle-death-ray-timing-commit.log`

## Native acceptance

An isolated GPU-rendered build-5875 client used Debugwarrior, GUID 1, at level
60. Existing native GM commands granted item 10645; normal inventory APIs
equipped it and `UseInventoryItem(13)` activated it. God mode remained off.
Tidewave only inspected live owner state. The accepted session is
`/home/pikdum/.cache/thistle-wow-playtest.9DyBTF`.

For the full cast, the player stood at `{16277.2, 16343.1, 69.44}` on map 451
and selected Skeletal Flayer spawn 990100, GUID 17379390991937510292,
19 yards away. Turning with native keyboard input and selecting with Tab
ensured the nearby flayer was selected; name targeting had selected a distant
same-named spawn during setup.

- The charging aura and channel shared expiry `-576460494171`.
- Four native combat-log entries each reported **147 physical self-damage**.
- The accumulator progressed through 147, 294, and 441 before the final tick
  released **588 base damage**.
- The native combat log reported **378 damage** to the flayer, matching its
  health change **2,980 → 2,602** after its 3,072 armor.
- Player health changed **3,459 → 3,009** over the channel: 588 self-damage
  offset by two 69-point regeneration events. Subsequent melee damage was
  separate from charging.
- After teleporting out of combat, the player and target regenerated to full;
  neither retained combat, a cast, or the charging aura.
- Native logout removed the player owner. Reconnecting retained the equipped
  item and 50,770 ms of its remaining cooldown, with full health and no cast or
  charging aura.

Full-cast evidence:

- Screenshot `screenshots/charged-discharge.png` in the accepted session.
- `/tmp/thistle-death-ray-final-full.log`
- `/tmp/thistle-death-ray-full-after.log`
- `/tmp/thistle-death-ray-armor.log`
- `/tmp/thistle-death-ray-reset-verified.log`
- `/tmp/thistle-death-ray-server-final.log`
- `/tmp/thistle-death-ray-logout.log`
- `/tmp/thistle-death-ray-reconnect.log`

Earlier setup sessions and logs remain available. They include the reproduced
three-tick timing race and unsuccessful client actions outside range or with
an unsuitable selection. The accepted results above use the corrected server.

After the normal cooldown elapsed, a second native item activation rolled
294 per tick. A movement key interrupted the channel after its first tick.
The owner stopped casting at sampler time 4,073 ms, while the aura retained
its original expiry and accumulated value 294. Later scheduled ticks did not
increase the charge or damage the player. At sampler time 6,412 ms, natural
expiry removed the aura and dealt **189 damage** to the same flayer, changing
its health **2,980 → 2,791**. Both combat-log entries are visible in
`screenshots/interrupted-discharge.png`; the owner trace is
`/tmp/thistle-death-ray-partial.log`.

Changing the selection at expiry is covered by deterministic tests. The native
interrupted trial retained the original target. After leaving combat, all three
flayers returned to full health and their spawn positions; the player returned
to full health with no cast, charge, selection, or combat state. The item retained
its new cooldown. See `/tmp/thistle-death-ray-final-state.log`.

## Cleanup

The accepted WoW process, PID 2289562, used amdgpu. Its own graphics counter
increased from 1,378,733,718 ns to 18,743,233,326 ns; the exact readings are
retained in `/tmp/thistle-death-ray-final-gpu-{before,after}.log`.
The final server log contains both item-use and channel-cast inputs, no errors
or cast-validation failures, and only the existing account-data and GM-ticket
query warnings.

All three helper-owned client sessions and all retained server processes were
stopped. Their artifacts remain available. Nothing was pushed.
