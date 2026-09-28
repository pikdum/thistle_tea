# Mount admission and Qiraji acceptance

Validated on 2026-09-27 with native 1.12.1 build-5875 clients after
`06d9d364` (`feat(mounts): enforce riding rules and summon Qiraji variants`).

## Reference and behavior

VMangos reference: `8f4e608450460efe1e38743e4da74397d4773a3a`.
`Spell.cpp` supplies shared mount admission rules; `Unit.cpp` determines
whether a shapeshift form or transformed display can ride. Mountable
transformed displays require CreatureDisplayInfoExtra plus the applicable
model or race flag. The world boundary caches these DBC facts and resolves
map, area, and transport exterior facts before pure cast validation.

`spell_item.cpp` gives Black Qiraji Resonating Crystal its mounted-use
dismissal and Ahn'Qiraj exception. `SpellEffects.cpp` selects outdoor spell
26655 or restricted spell 25863 from the map's mount policy. The local
implementation removes mounts through the aura owner and resolves a typed
summon effect into the selected triggered spell, retaining the item GUID.
Both cast admission and launch validate the current mount restrictions.

## Native acceptance

Debugmage (GUID 5) and Debugpaladin (GUID 2) used isolated GPU clients.
Existing level, learning, item, and teleport commands prepared level 60,
Riding 150, items 21176 and 21218, and the relevant test spells. Real item
uses came from `UseContainerItem`; casts and movement came from the client.
Tidewave only read live owner state and cached trigger geometry.

| Action | Client and authoritative result |
| --- | --- |
| Black Crystal on Programmer Isle | Black mount display 15677, speed 14.0 yards/second, and only mount holder 26655. The holder retained item GUID 4611686018427388164. |
| Use Black Crystal again while mounted | Immediate dismissal: mount display 0, speed 7.0, no mount holder, and no active cast. The expected server result was `dont_report`. |
| Blue Crystal outside Ahn'Qiraj | Client showed “You need to be in Ahn'Qiraj”; spell 25953 failed with `requires_area`. |
| Noggenfogger skeleton (16591), then Black Crystal | Display 7550 remained unmounted at speed 7.0. Client showed “You are in shapeshift form”; validation returned `not_shapeshift`. |
| Cancel skeleton, cast Flip Out (8219), then Black Crystal | Ninja display 4617 could mount. Both clients showed the Qiraji mount; owner retained 8219 and 26655, mount display 15677, and speed 14.0. |
| Form a raid and walk through entrance trigger 4010 | Both owners entered map 531, instance 1. No direct teleport into the instance replaced entry. |
| Brown Horse (458) inside the raid | Validation returned `no_mounts_allowed`; the character remained unmounted. |
| Blue Crystal inside the raid | Both clients showed blue mount display 15678. Owner retained holder 25953 with item GUID 4611686018427388165 and speed 14.0. |
| Black Crystal while blue-mounted | Removed the blue holder immediately; mount display 0, speed 7.0, and no active cast. |
| Black Crystal again while unmounted inside the raid | Both clients showed the black mount. Owner retained only mount holder 25863, original Black Crystal item GUID, display 15677, and speed 14.0. |
| Walk backward through exit trigger 4012 | Mage returned to map 1 with no instance ID, near {-8238.94, 1993.34, 129.07}. Holder 25863 was removed, mount display became 0, and speed returned to 7.0. The observer remained in instance 1 and no longer saw the mage. |
| Use Black Crystal outside again | Selected holder 26655 with the same item GUID, display 15677, and speed 14.0. No restricted mount holder remained. |

Both clients entered from the open-world staging position
`{-8239.01, 1993.25, 129.071}` on map 1 using keyboard movement. Within the
instance, staging teleports omitted the map argument to retain instance 1.
The exit approach used `{-8226, 2010, 129.1}` followed by native backward
movement. God mode was enabled for the raid checks to keep nearby mobs
from disrupting mount acceptance.

## Evidence and checks

- Mage session: `/home/pikdum/.cache/thistle-wow-playtest.CPdkVm`.
- Paladin session: `/home/pikdum/.cache/thistle-wow-playtest.qpghMB`.
- Screenshots include `black-outdoors`, `black-dismissed`, `blue-wrong-area`,
  `skeleton-rejected`, `humanoid-mounted-owner`, `humanoid-mounted-observer`,
  `aq-blue-owner`, `aq-blue-observer`, `aq-black-owner`, `aq-black-observer`,
  `aq-exited`, `aq-observer-after-exit`, and `black-after-exit` in the
  corresponding session directories.
- WoW processes 2649140 and 2650134 each had their own AMD DRM descriptors
  and nonzero graphics-engine counters.
- Server log: `/tmp/thistle-qiraji-server.log`. Native item packets and
  area-trigger packets were observed. No server errors occurred. Warnings
  were the expected mount rejections/dismissals and existing account-data
  and GM-ticket stubs.
- Focused owner snapshots: `/tmp/thistle-qiraji-aq-mounted.log`,
  `/tmp/thistle-qiraji-exited.log`, and
  `/tmp/thistle-qiraji-outside-remounted.log`.
- `mix test.all`: **7,378 passed**, 81.5 seconds;
  `/tmp/thistle-qiraji-tests.log`.
- `mix compile --warnings-as-errors`: passed;
  `/tmp/thistle-qiraji-compile.log`.
- `mix credo --strict`: no issues; `/tmp/thistle-qiraji-credo.log`.

Automated tests additionally cover transport decks, Black Crystal transport
and swimming restrictions, area 35, animal forms versus allowed stances,
actual area requirements versus quest-only rules, DBC model/race flags,
launch-time changes before costs, silent dismissal without cast-start or
cooldown changes, and both triggered mount variants with item context.
The dependency ratchet passes without new allowlist entries.

Both helper-owned client services and the retained server were stopped
after acceptance. Logs and screenshots were retained.
