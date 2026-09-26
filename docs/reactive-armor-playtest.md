# School-reactive armor procs

Implemented in `a41cb436` and validated with the build-5875 client on
2026-09-26 (America/Chicago).

Reference: `refs/vmangos` at `8f4e608450460efe1e38743e4da74397d4773a3a`,
especially the Obsidian Armor and Adaptive Warding branches in
`UnitAuraProcHandler.cpp`, plus the generated DBC and VMangos data.

## Behavior

Thick Obsidian Breastplate's passive now selects a matching school absorb from
incoming Holy, Fire, Nature, Frost, Shadow, or Arcane spells. Its real data gives
a 30% chance, a ten-second cooldown, and a six-second shield absorbing a random
300–500 damage. Physical damage does not trigger a shield.

Frostfire Regalia's four-piece Adaptive Warding bonus now selects a matching
Fire, Nature, Frost, Shadow, or Arcane resistance buff while Mage Armor is
active. Its real data gives a 20% chance and 35 resistance for 30 seconds. All
three Mage Armor ranks qualify; Frost Armor and Ice Armor do not. Holy and
Physical spells do not trigger this bonus.

The shared incoming-spell reaction path retains responsibility for proc flags,
outcomes, origin, chance, charges, and cooldown. School selection is pure and
emits an ordinary self-targeted spell effect; existing delivery, aura, stat,
absorb, and lifecycle code handles the result. Equipment and enchantment passive
holders now retain their item GUID, and ordinary proc effects carry that GUID
forward. Item-set bonuses have no individual cast-item GUID.

## Automated validation

`mix test.all`: **6501 passed** in 57.5 seconds. Compilation with warnings as
errors passed. Strict Credo reported zero issues across 2378 files. Formatting
and commit hooks passed; the dependency allowlist was unchanged.

Tests cover every school mapping, all Mage Armor ranks, equipment attribution,
bearer credit, chances, cooldown boundaries, charges, resisted and suppressed
hits, periodic exclusion, implicit self delivery, matching-school absorption,
shield depletion, expiry, death, source removal, and delayed delivery to a dead
target. Separate DBC and VMangos tests verify real spell, item, set, and cooldown
data with mutually exclusive database tags.

## Native acceptance

Two isolated hardware-rendered clients ran at level 60 on map 451. Debugbidder,
a human mage (GUID 11), stood at `{16307, 16300, 69.44}`. Orcwarrior (GUID 12)
stood at `{16309, 16300, 69.44}` for the Obsidian test. After that warrior logged
out, Debugshaman (GUID 8) used the same client and stood at
`{16305, 16300, 69.44}` for the Frostfire test. All participants were PvP flagged
with godmode off. Existing development commands prepared levels, gear, and Mage
Armor rank 3. No proc chance was overridden.

### Obsidian Armor

Native inventory use and the binding dialog equipped item 22196, with item GUID
`4611686018427388164`. The passive holder retained that exact item identity.
Incoming rank-1 Fireballs produced a Fire shield with 457 absorb. Sampling
recorded its capacity falling to 456 and 455 from periodic damage, then to 434
after a 21-point direct hit while health stayed at 3518. The client displayed
the active buff, proc visual, and **Absorb** combat text. The shield expired at
six seconds, and subsequent procs respected the ten-second cooldown.

A second sequence removed the breastplate through the native inventory API
while a 414-point shield was active. The equipment passive disappeared, while
the shield continued absorbing and kept its original expiry. Removing stamina
clamped health to the new maximum of 3399. Further Fireballs did not create a
new shield. The warrior then reached character selection, with nil entity
registration, world position, and metadata.

### Adaptive Warding

Native inventory use equipped Frostfire items 22500–22503. The resulting passive
was sourced from `{:item_set, 526, 28764}`. Five incoming rank-1 Lightning Bolts
without Mage Armor dealt damage without producing a ward; Nature resistance
remained zero.

Casting Mage Armor rank 3 raised Nature resistance to 15. A bounded sequence of
up to ten Lightning Bolt casts produced the Nature ward after 34 seconds. Both
owner state and the character panel showed Nature resistance 50, with one 35-point ward
credited to the mage and no cast-item GUID. The buff subsequently expired.

In a second sequence the ward appeared about 16 seconds into sampling.
Replacing Mage Armor with Frost Armor reduced Nature resistance from 50 to 35
without removing the ward. Unequipping the Frostfire bracers then removed the
four-piece passive and retained that same ward. The client displayed Nature
resistance 35 with the empty wrist slot. Further Lightning Bolts neither
recreated the source nor extended the ward's original deadline.

At 46.1 seconds, 30 seconds after application, the ward disappeared and Nature
resistance returned to zero in owner state and the character panel. Re-equipping
the bracers restored exactly one four-piece passive without recreating the ward.
Both clients reached character selection; all three tested GUIDs had nil entity
registration, world position, and metadata. Reconnecting the mage restored the
four-piece passive at the same position, with baseline Fire resistance 22,
Nature and Frost resistance zero, and no expired ward.

## Evidence

- Warrior/shaman session: `/home/pikdum/.cache/thistle-wow-playtest.5HQfUc`.
- Mage session: `/home/pikdum/.cache/thistle-wow-playtest.b73515`.
- Server: `/tmp/thistle-reactive-armor-server.log`.
- Obsidian samples: `/tmp/thistle-reactive-armor-obsidian-samples.txt` and
  `/tmp/thistle-reactive-armor-removal-samples.txt`.
- Frostfire samples: `/tmp/thistle-reactive-armor-unarmored-samples.txt`,
  `-adaptive-samples.txt`, and `-lifecycle-samples.txt`.
- Lifecycle probes: `/tmp/thistle-reactive-armor-armor-replaced.txt`,
  `-set-removed.txt`, `-reequipped.txt`, `-logout.txt`, and `-reconnect.txt`.
- Warrior screenshots include `obsidian-active.png`, `obsidian-unequipped.png`,
  and `warrior-logged-out.png`. Mage screenshots include `adaptive-active.png`,
  `adaptive-with-frost-armor.png`, `adaptive-with-three-pieces.png`,
  `adaptive-expired.png`, `logged-out.png`, and `reconnected.png`.
- Final gates: `/tmp/thistle-reactive-armor-final-all.log`, `-compile.log`, and
  `-credo.log`.

The longer lifecycle Tidewave request exceeded the CLI's HTTP timeout, while
its read-only sampler continued and retained the completed transitions in the
evidence file. Native acceptance covers Fire absorption and Nature resistance;
the other schools, shield depletion, and death are covered by automated tests.
This does not establish full vanilla parity.

WoW's own amdgpu graphics counter increased from 1,625,546,911 to
35,600,400,913 ns for PID 1528469, and from 610,052,786 to 36,894,445,310 ns
for PID 1529328. Duplicate file descriptors were not summed. The server log had
no gameplay validation failures or owner errors. Existing unsupported
account-data, GM-ticket, and meeting-stone login requests were present.

Final logout probes again showed all three players absent from entity
registration, world position, and metadata. Both helper-owned services were
verified inactive, their WoW processes were gone, and the retained server
exited. Artifacts were retained. No push was performed.
