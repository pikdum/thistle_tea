# Charge combat timing and arrival

Implementation: `0e36e4fc`.

Reference: local VMangos revision `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Spell::OnSpellLaunch` in `Spells/Spell.cpp` and
`ChargeMovementGenerator::Finalize` in `Movement/PointMovementGenerator.cpp`.

Normal and triggered charge spells now carry their attack-on-arrival policy
through path resolution into the owning player or creature. Harmful spells
request an attack unless `SPELL_ATTR_CANCELS_AUTO_ATTACK_COMBAT` suppresses it.
Player charges add `200 + 40 * distance` milliseconds to both melee swing
timers, retaining any existing cooldown. Distance subtracts both bounding radii,
as in the reference. Creature swing timers remain unchanged.

Arrival queues the shared attack request with the original target lifetime.
Players require the same client selection; creatures enter the existing
engagement lifecycle. Dead, missing, replaced, or cross-world targets cannot
start arrival combat. Cancellation, premature completion, death, and a
superseding spline do not enqueue an attack. Normal casts now enqueue their
charge at launch, alongside the existing triggered-spell launch path.

Automated checks cover both swing timers, negative monotonic timestamps,
cooldown preservation, arrival idempotence, interruption, selection changes,
target lifetime changes, player and creature owner dispatch, path timing,
observer spline projection, and real DBC attack-suppression attributes.
`mix test.all` passed **6588 tests**; warnings-as-errors compilation and strict
Credo passed without architecture allowlist changes.

Native acceptance used a build-5875 GPU client with level-50 warrior Debugbuyer
(GUID 10), Battle Stance, and Charge rank 3 (11578). Existing development
commands enabled god mode and placed the warrior 25 yards from the seeded
Land Walker (GUID 17379391051899281576) on Programmer Isle.

The first `/cast Charge` began with autoattack disabled and the target at 6186
health. Sampling observed active movement at +2116 ms, arrival and automatic
attack intent at +2884 ms, and the first hit at +3231 ms. The delayed swing
deadline was +3204 ms. The first hit dealt 192 damage and the next dealt 178;
no Attack command was issued before or during this acceptance sample. Movement
ended at x=16336.662 from x=16318.200. The client showed the charge, target stun,
and subsequent melee stance with the attack button active.

After moving away to let the target reset, a second native Charge tested target
clearing. Escape cleared selection at +2262 ms while the charge was active;
arrival at +2860 ms retained autoattack=false. The target remained at 6186 health
through +6299 ms. Its retaliation caused the client to select it again, but did
not restart the warrior's autoattack. The client showed the charge trail with
no selected target, then the warrior under attack with the attack button idle.

Logout removed registry, position, and metadata entries. The saved character
had no charge or attack intent. Reconnect restored no charge, arrival timer,
selection, or automatic attack. Final disconnect cleared world presence again.
The owned client service became inactive/dead, WoW PID 1629211 disappeared,
and the retained server exited with ports 4000, 3724, and 8085 closed.

WoW's own amdgpu graphics counter increased from 3,839,783,113 to 7,868,168,602
nanoseconds; duplicate file descriptors were not summed. No error-level server
entries or spell-validation failures appeared. Only the existing unsupported
account-data, ticket, and meeting-stone requests were logged.

Evidence:

- Client: `/home/pikdum/.cache/thistle-wow-playtest.C3sRfN`; screenshots
  `before-charge.png`, `charge-arrival.png`, `automatic-melee.png`,
  `cleared-during-charge.png`, `cleared-no-autoattack.png`, and `logged-out.png`.
- Server: `/tmp/thistle-charge-server.log`.
- Samples: `/tmp/thistle-charge-native-first.txt` and
  `/tmp/thistle-charge-native-cleared.txt`.
- Lifecycle: `/tmp/thistle-charge-logout.txt`,
  `/tmp/thistle-charge-reconnected.txt`, and `/tmp/thistle-charge-disconnected.txt`.
- GPU: `/tmp/thistle-charge-gpu-before.txt` and `/tmp/thistle-charge-gpu-after.txt`.
- Gates: `/tmp/thistle-charge-final-{all,compile,credo}.log`.

Creature arrival and interruption have automated coverage; native acceptance
above covers player Charge. Full vanilla parity remains unproven.
