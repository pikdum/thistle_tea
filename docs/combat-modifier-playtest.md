# Ammunition haste and stacked damage acceptance

Validated on 2026-09-24 with the native build-5875 client against the local
compiled server. Gameplay commits: `43607c1c` and `c9f75dd3`.

## Rules and regression coverage

VMangos `Aura::HandleRangedAmmoHaste` in
`refs/vmangos/src/game/Spells/SpellAuras.cpp` gates ammunition haste on an
equipped weapon with nonzero `AmmoType`. Ordinary ranged haste has no such
gate. Thrown weapons in the local data have ammunition type 4 and remain
eligible; wands have type 0. The loader now preserves aura 141 separately
from ordinary ranged haste, and equipment aggregates retain this distinction.

`Player::CanEquipItem` in `refs/vmangos/src/game/Objects/Player.cpp` limits
carried ammunition bags to one quiver or ammo pouch. Inventory placement now
enforces that limit with client errors 33 and 42. Replacement, moving the
existing bag, and bank storage remain valid.

`SpellAuraHolder::SetStackAmount` scales the modifier amount by the stack
count. The shared percentage damage multiplier now does the same, including
reductions and equipment or school restrictions.

Regression tests cover ammunition weapon changes, ordinary ranged haste on
wands, equipment restoration without a duplicate aura, bag placement, loaded
Growth, independent damage modifiers, stack caps, partial dispels, expiry,
and agreement between displayed wand damage, cast snapshots, landed damage,
and combat effects. DBC fixtures provide their own item templates without
querying the generated VMangos database.

## Native results

The isolated GPU session was
`/home/pikdum/.cache/thistle-wow-playtest.oJlv37`. Debugmage (GUID 5) and
Debughunter (GUID 7) were tested at level 60 with god mode disabled.
Preparation used client dev commands and normal inventory, spell, logout,
and corpse actions. Tidewave probes only read runtime state.

### Wand and ammunition bags

Debugmage equipped Lesser Magic Wand (11287) and Small Ammo Pouch (2102).
The pouch contributed 10% ammunition haste, while both the owner and client
reported the wand's unchanged 1,500 ms period. Its unbuffed damage was 12–22.

Attempting to equip Medium Quiver (11362) alongside the pouch produced the
native error “You can only equip one ammo pouch.” The owner retained the
original bag, 10% equipment input, and 1,500 ms period. Replacing the pouch
in its existing slot succeeded. Reconnect restored the medium quiver and
the same wand period.

The hunter-only Ancient Sinew Wrapped Lamina was unsuitable for the mage
fixture. Early screenshots and probes from that setup are not acceptance
evidence.

### Stacked damage and lifecycle

Three native casts of Positive Charge (29659) produced one holder with three
stacks, visibly shown on the client. The owner retained a 1.3 multiplier and
a 15.6–28.6 wand damage range. Against Marisa du'Paige on Programmer Isle,
the combat log showed ordinary hits including 24, 26, and 28 Arcane damage.
The sampled target health fell from 1,062 to 833 over ten landed shots;
successive launch deadlines were 1,501–1,503 ms apart.

After stopping Shoot and leaving combat, Marisa returned to full health with
target 0, empty threat, and combat false. Logout and reconnect preserved the
three stacks and their damage bonus. Normal death removed the holder and
restored 12–22 damage, with no active repeat attack. Release and corpse
recovery returned the mage alive without restoring the removed stacks.

### Ammunition weapon eligibility

Debughunter's Bow of Searing Arrows (2825) had a 2,700 ms base period.
Removing the equipped ammo pouch restored 2,700 ms and zero ammunition
haste. Equipping Ancient Sinew Wrapped Lamina (18714) supplied 15% and
recomputed the period to 2,347 ms. The native client reported both final
periods. The hunter finished alive, out of combat, with the pet dismissed.

## Evidence and checks

Screenshots include `actual-pouch-rejection.png`, `stacked-combat.png`,
`reconnected.png`, `death-cleanup.png`, and `hunter-haste.png`. The final two
diagnostic lines in `hunter-haste.png` are the verified unequipped and 15%
quiver measurements; an earlier setup label above them refers to the
original 10% pouch.

Read-only probes and server logs are retained under
`/tmp/thistle-combat-modifiers-*`, including `quiver.log`,
`three-stacks.log`, `stacked-hits.log`, `rejection-state.log`, `reconnect.log`,
`death.log`, `reclaimed.log`, `hunter-unequipped.log`, and
`hunter-equipped.log`.

WoW PID 560668 belonged to `thistle-wow-playtest.oJlv37.service`; its own
AMDGPU counters showed 193,560 KiB VRAM and 45.89 seconds of graphics work.
The helper-owned session and retained server PTY were stopped, with no
remaining WoW or BEAM processes. Server logs contained no errors; warnings
were the existing account-data, GM-ticket, and meeting-stone handlers.

Final gates passed: `mix test.all` (5,932 tests),
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix format --check-formatted`, and `git diff --check`.
The first full run exposed a 100 ms async pet-attachment test timeout;
`3c360161` gives that assertion a one-second deadline. The affected test
passed in isolation and the subsequent full run passed.
