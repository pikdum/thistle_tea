# Random consumable outcomes and periodic emotes

Implementation: `2d641489`. Client notification fix: `b75d45d9`.
Reference: local VMangos revision `8f4e608450460efe1e38743e4da74397d4773a3a`,
`scripts/spells/spell_item.cpp`, `Spells/SpellAuras.cpp`,
`Objects/MovementInfo.h`, and `Handlers/SpellHandler.cpp`.
The empty cancellation packet is also specified by the local `wow_messages`
`world/spell/cmsg_cancel_growth_aura.wowm`.

## Behavior

| Consumable | Outcomes |
| --- | --- |
| Noggenfogger Elixir (8529) | 20% shrink, 20% slow fall, 60% skeleton with water breathing |
| Savory Deviate Delight (6657) | Equal ninja/pirate chance, with the appropriate model for each gender |
| Deviate Fish (6522) | Equal chances of Sleepy, Invigorate, Shrink, Party Time, Healthy Spirit, and Rejuvenation |

These probabilities follow the current local reference. Savory Deviate Delight
uses the two build-5875 outcomes; the extra pre-BWL outcomes are excluded.

A typed `Effects.RandomChoice` holds weighted alternatives of ordinary effect
lists. Selection is deterministic for a supplied roll; the entity boundary
owns randomness and resolves the chosen effects through the existing pipeline.
The consumable scripts request one triggered self-cast from the first dummy
effect. The parent item-use transaction owns consumption and cooldowns.

Party Time's otherwise-unspecified dummy aura is compiled into a periodic
animation with a ten-second interval and its original two-minute duration.
The existing aura scheduler owns ticks and cleanup. Stationary actors may
applaud, cheer, act like a chicken, laugh, or dance. Moving, jumping, falling,
pitching, and spline-elevation movement exclude dancing. Animations are
one-shot packets, without changing persistent emote state.

Native testing exposed an unregistered `CMSG_CANCEL_GROWTH_AURA` notification.
The reference intentionally does nothing with its empty payload. The new codec
and dispatch entry accept it without changing any aura or scale; ordinary aura
cancellation retains ownership of those transitions.

## Automated validation

- `mix test.all`: **6558 passed**, 71.3 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2395 files.
- Formatting, architecture dependency ratchet, and commit hooks passed.

Tests cover weighted boundaries, exactly one outcome, both genders, player/self
restrictions, first-effect dispatch, recursive trigger resolution, real DBC
outcome application, transformation/scale coexistence and cancellation, stat
bonuses, direct and periodic healing, periodic scheduling, movement exclusions,
expiry, cancellation, death, and one animation packet per eligible recipient.
A different-world observer receives none. Separate VMangos tests verify cached
script labels. Database tags remain mutually exclusive. The packet regression
checks real opcode dispatch and unchanged player scale.

## Native acceptance

Build-5875 GPU clients used Debugbidder (GUID 11, human female mage) and nearby
Debugbuyer (GUID 10). All gameplay mutations used native input and existing
development commands. Tidewave probes inspected owner state and projections.

Sixteen real Noggenfogger uses reduced the stack from 20 to 4 and naturally
produced all three outcomes. The owner and observer saw skeleton display 7550;
shrink changed scale to 0.5 while skeleton and slow fall remained active. Slow
fall set movement flag `0x20000000`. Both owner state and world metadata agreed
with the client appearance.

The first Savory Deviate Delight reduced its stack from 10 to 9 and produced
female ninja spell 8220, display 4618. It appeared over the existing half-size
skeleton. Logout removed GUID 11 from entity registration, world position, and
metadata. Reconnect restored the same items and active holders with their
original deadlines: slow fall had 7.79 seconds remaining, then expired and
cleared its movement flag. Right-click cancellation of the costume revealed
the half-size skeleton; cancelling shrink restored scale 1.0; cancelling the
skeleton restored native display 50. The second food use produced female
pirate spell 8222, display 4619, and left eight items. Both costumes were visible
to the observer.

Six raw fish uses reduced the stack from 20 to 14. Natural outcomes included
Shrink (scale 0.7 and its stat changes), Healthy Spirit, Sleepy (30-second stun),
and Party Time. Invigorate and Rejuvenation were covered by DBC integration
tests. Sleepy expired before the next successful use; no interrupted-use claim
is inferred from that attempt.

Party Time scheduled successive tick deadlines exactly 10,000 ms apart.
Screenshots show its unsolicited animations in the owner and observer clients.
The raw-fish shrink expired during sampling and restored scale 1.0. Party Time
was absent after its original two-minute deadline, and a further observation
window showed no renewed periodic holder. Native death then removed the pirate
and spirit buffs, restored display 50 and scale 1.0, and published `alive?: false`.

The initial server had no error-level entries or spell-validation failures.
Alongside existing unsupported account-data, ticket, and meeting-stone requests,
it logged the growth-aura notification subsequently handled by `b75d45d9`.
Both players were logged out and absent from registry, position, and metadata
before shutdown. Both helper services were inactive, both WoW processes were
gone, and the retained server exited.

WoW's own amdgpu graphics counters increased from 2,621,718,984 to
24,237,188,058 ns for PID 1590864 and from 4,545,980,511 to 19,669,812,607 ns
for PID 1593023. Duplicate descriptors were not summed.

A fresh server on `b75d45d9` verified the notification fix separately. The
existing `.learn 16595` command made the shrink spell available, and a native
cast and right-click cancellation changed scale from 0.5 to 1.0. This follow-up
tested cancellation directly; the earlier run covered actual consumable use.
The network profile recorded one `CMSG_CANCEL_AURA` and one
`CMSG_CANCEL_GROWTH_AURA`. There were no error-level entries, spell-validation
failures, or unimplemented growth-notification warnings. The final player left
registry, position, and metadata; its helper service was inactive, WoW PID
1599853 was gone, and the retained server exited.

## Evidence

- Main client: `/home/pikdum/.cache/thistle-wow-playtest.nlwYep`.
- Observer: `/home/pikdum/.cache/thistle-wow-playtest.SleDMx`.
- Follow-up client: `/home/pikdum/.cache/thistle-wow-playtest.4lQ1G2`.
- Server logs: `/tmp/thistle-consumable-server.log` and
  `/tmp/thistle-consumable-final-server.log`.
- Sampling: `/tmp/thistle-consumable-noggen-samples.txt`,
  `/tmp/thistle-consumable-noggen-more-samples.txt`,
  `/tmp/thistle-consumable-party-samples.txt`, and
  `/tmp/thistle-consumable-party-expiry-samples.txt`.
- Owner snapshots: `/tmp/thistle-consumable-{noggen-all,savory-first,
  reconnected,slowfall-expired,costume-cancelled,mini-cancelled,
  native-restored,raw-first,party-late,party-expired,savory-second,death}.txt`.
- Cleanup: `/tmp/thistle-consumable-cleanup.txt`.
- Follow-up: `/tmp/thistle-consumable-final-{mini,cancelled,cleanup}.txt` and
  `final-mini.png`, `final-before-cancel.png`, `final-growth-cancelled.png`.
- Final gates: `/tmp/thistle-consumable-final-{all,compile,credo}.log`.
- Screenshots include `noggen-all-outcomes.png`, `observer-mini.png`,
  `savory-first.png`, `observer-savory.png`, `reconnected.png`,
  `native-restored.png`, `party-animation-1.png`, `observer-party-2.png`,
  `savory-second.png`, `observer-pirate.png`, and `consumable-death.png`.

Nothing was pushed. Full vanilla parity is not established by this change.
