# Mount replacement and forced dismount acceptance

Validated on 2026-09-27 with the native 1.12.1 build-5875 client after
`b5fe166c` (`feat(mounts): handle reindeer replacement and forced dismounts`).

## Reference and behavior

VMangos reference: `8f4e608450460efe1e38743e4da74397d4773a3a`.
`SpellEffects.cpp` handles Reindeer Transformation (25860) by checking the
current run-speed rate before removing mounted auras. A rate of at least
2.0 selects Reindeer 25859; lower rates select 25858. `spell_item.cpp`
requires an existing mounted aura and makes Discombobulate (4060) remove
mounted auras when its first transformation effect applies.

The local implementation uses ordinary aura removal and typed triggered
spell delivery. Forced dismount runs through the shared aura transition,
including dismount interruption flags and speed/display projection. A
blocked transformation effect or an unchanged existing debuff does not
remove a mount.

## Native acceptance

Debugmage (GUID 5) and Debugpaladin (GUID 2), both level 60, used Programmer
Isle near `{16320, 16305, 69.44}`. Existing `.learn`, `.additem`, level, and
teleport commands prepared the test. Gameplay actions came from client
casts, `UseContainerItem`, buff cancellation, logout/login, and a duel.
Tidewave only read owner state and saved characters.

| Action | Client and authoritative result |
| --- | --- |
| Brown Horse (458), then Preserved Holly (21213) | Horse display 2404 became reindeer 15902. Holder 458 was replaced by 25858; run speed stayed 11.2 yards/second. Holly count fell from 5 to 4. The observer saw the reindeer and its aura. |
| Cancel Reindeer | Mount display became 0 and speed 7.0; the horse did not return. |
| Swift White Steed (23228), then Fresh Holly (21212) | Steed display 14338 became reindeer 15902. Holder 23228 was replaced by 25859; run speed stayed 14.0. Fresh Holly count fell from 2 to 1. |
| Logout and reconnect while mounted | The old owner stopped. CharacterStore retained only mount holder 25859, display 15902, and speed 14.0. The new owner and client restored those values. |
| Discombobulator Ray (4388), first use | The spell was resisted. Both clients showed combat feedback; reindeer display 15902 and speed 14.0 remained. |
| Ray use after its cooldown | Both clients showed the Leper Gnome and the mount disappeared. The owner held 4060 with transform, -20% movement, and -40 damage effects; display 6921, mount 0, speed 5.6. |
| Natural Discombobulate expiry | Display returned to native 50 and speed to 7.0. Neither the reindeer nor the original horse returned. |
| Holly while unmounted and ready | The client displayed “Can only use while mounted.” The server rejected 25860 with `only_mounted`; counts remained 4 Preserved Holly and 1 Fresh Holly. |

A 50-ms read-only sampler captured the successful Ray transition at
6,276 ms and its expiry at 18,263 ms, a 11,987-ms observed interval for the
12-second spell. The duel ended through `/forfeit`.

## Evidence and checks

- Mage session: `/home/pikdum/.cache/thistle-wow-playtest.nTnahB`.
- Paladin session: `/home/pikdum/.cache/thistle-wow-playtest.ZhzcMQ`.
- Screenshots include `reindeer-60-owner`, `reindeer-60-observer`,
  `reindeer-100-owner`, `reindeer-100-observer`, `reindeer-reconnect`,
  `discombobulate-landed-owner`, `discombobulate-landed-observer`,
  `discombobulate-expired-owner`, `discombobulate-expired-observer`, and
  `only-mounted-error` in the corresponding session directories.
- Both clients used GPU rendering. WoW processes 2636915 and 2637770 had
  their own AMD DRM file descriptors and nonzero graphics-engine counters.
- Server log: `/tmp/thistle-mount-transform-server.log`. The native item
  packets named both Holly variants and both Ray uses. No server errors
  occurred. Warnings were the expected mounted-only rejection and existing
  login account-data/GM-ticket stubs.
- Sampler: `/tmp/thistle-mount-discombobulate-landed-samples.log`.
- `mix test.all`: **7,369 passed**, 81.6 seconds; log at
  `/tmp/thistle-mount-transform-tests.log`.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: no issues; log at
  `/tmp/thistle-mount-transform-credo.log`.

Automated coverage additionally checks slowed mount selection, transformation
immunity preserving the mount while its slow applies, repeat application,
unrelated transformations, water interruption, death, and wire encoding of
the mounted-only failure. The helper-owned client services and local server
were stopped after acceptance; their logs and screenshots were retained.
