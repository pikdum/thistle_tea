# Spell casting and automatic attacks

Implementation: `5cc8073f` and `51a49bb1`.
Reference: local VMangos revision `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Spells/Spell.h` (`IsMeleeAttackResetSpell`), `Spells/Spell.cpp` (launch and
successful finish), and `Objects/Unit.cpp` (`AttackStop`).

Ordinary casts with `SPELL_INTERRUPT_FLAG_COMBAT` now reset melee swing timers
to the current weapon periods when they launch. The offhand resets only when
usable. Triggered casts and `SPELL_ATTR_EX2_DO_NOT_RESET_COMBAT_TIMERS` preserve
the timers. The rule follows spell data, including instant spells such as Frost
Nova; it is not inferred from cast duration. Channels reset at launch once,
while preparation and interruption preserve the pending melee timers.

Successful completion honors `SPELL_ATTR_CANCELS_AUTO_ATTACK_COMBAT` for players
and creatures. Player cancellation uses the existing melee/autorepeat funnels,
clears queued next-swing spells, and emits their normal feedback. Creature
cancellation uses `Engagement.stop_attack`. Both retain combat membership and
threat. Triggered completion uses the same rule through outgoing spell feedback.
Cancellation does not depend on a hit recipient, so resisted or recipient-free
casts can still stop attacks. A damage-breakable aura alone no longer decides
whether the caster should stop attacking.

Testing exposed stale behavior-tree memory overwriting the combat changes made
by casting. The regression failed with autoattack still enabled before the fix.
Scheduled spell ticks and instant creature spell-list/commanded casts now pass
the current blackboard into casting and return its resulting blackboard, keeping
both combat changes and previously scheduled behavior intact.

Automated acceptance passed **6604 tests** with `mix test.all`; warnings-as-errors
compilation and strict Credo passed. Coverage includes negative timestamps,
both hands, unusable offhands, trigger and spell-data exceptions, channel timing,
interrupted casts, empty hit lists, queued attacks, autorepeat cancellation,
creature engagement, triggered completion, and behavior-tree handoffs. Separate
DBC tests check real spells and attributes. The dependency allowlist is unchanged.

Native acceptance used level-50 mage Debugbidder (GUID 11) in a build-5875 GPU
client. Existing commands enabled god mode, taught Frostbolt rank 1, and placed
the mage near the seeded Land Walker on Programmer Isle. Melee attack was
enabled before casting; the current weapon period was 2900 ms.

The Frostbolt sample began with an active melee attack. A weapon hit occurred at
+906 ms, scheduling the next swing for +3781 ms. Frostbolt began at +2305 ms and
was due at +3805 ms. The first completed-cast sample at +3823 ms showed a new
melee deadline of +6707 ms while autoattack remained enabled. Frostbolt dealt
21 damage at +4048 ms; the next weapon hit dealt 82 damage at +6736 ms, after the
new deadline. The client showed the cast bar and then resumed melee combat.

For attack cancellation, the mage selected a Stonetusk Boar and enabled melee
attack from fifteen yards away. Polymorph rank 3 (12825) began at +2122 ms;
the +3652 ms sample showed the completed cast, autoattack=false, the attack
field cleared, and the client selection retained. The boar held Polymorph,
remained at 102 health through +9028 ms, and appeared as a sheep in the client.
A later read confirmed the holder's 40,000 ms duration and no resumed attack.

Logout completed and removed registry, position, and metadata entries. The saved
character had no melee intent, autorepeat, queued swing, or cast. Reconnect
restored none of those states and remained out of combat. Final disconnect
again cleared world presence. The owned client service became inactive/dead,
WoW PID 1637890 disappeared, and the retained server exited with ports 4000,
3724, and 8085 closed.

WoW's amdgpu graphics counter increased from 6,320,666,786 to 13,277,783,596 ns;
duplicate descriptors were not summed. No error-level or spell-validation
failures appeared. Only existing unsupported account-data, ticket, and
meeting-stone requests were logged.

Evidence is retained in `/home/pikdum/.cache/thistle-wow-playtest.ObNexX` and
`/tmp/thistle-casting-combat-*`. Key screenshots are `frostbolt-casting.png`,
`melee-after-frostbolt.png`, `attack-before-polymorph.png`,
`polymorph-attack-stopped.png`, and `character-after-logout.png`. Runtime samples
are `frostbolt.txt`, `polymorph.txt`, `polymorph-late.txt`, `logged-out.txt`,
`reconnected.txt`, and `disconnected.txt` under that temporary-file prefix;
`logout.txt` is an earlier sample taken while the logout countdown was pending.
The server log, GPU snapshots, and final gate logs use the same prefix.

Native coverage above exercises player melee timing and cancellation. Creature,
offhand, triggered, and autorepeat transitions have automated coverage. Full
vanilla parity remains unproven.
