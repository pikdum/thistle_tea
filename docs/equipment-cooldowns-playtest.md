# Equipment cooldowns and combat swaps

Implemented in `a72a0345` and tested on 2026-09-27 with the native build-5875
client, Debughunter (GUID 7, level 50), and a fresh local server.

## Rules and ownership

Newly occupied equipment slots start a 30-second cooldown for each valid
on-use spell, except items carrying `ITEM_FLAG_NO_EQUIP_COOLDOWN` (`0x80`).
Existing active cooldowns retain their deadline, including timers with less
than 30 seconds remaining. New equip cooldowns use the spell's category data;
ordinary item use still applies the item's cooldown overrides. Deferred item
cooldowns retain their original item identity and overrides when activated.

Combat weapon and relic equips start the swap timer and global cooldown:
1,000 ms for rogues and 1,500 ms for other classes. An existing GCD keeps its
deadline. Another weapon equip is rejected until the swap timer expires.
Canceling a cast cannot clear a GCD started by equipment. Shields and held
offhand items remain changeable in combat without starting that timer.
Client changes to armor and trinkets are rejected in combat, including direct
unequips and auto-store. System-driven equipment expiry remains permitted.

`EquipmentTransitions` stays pure, with injected item/spell lookups and time.
The shared inventory commit projection starts cooldowns after successful slot
changes and sends typed effects through the explicit owner context. Both
legacy inventory results and `Inventory.ChangeSet` use this transition.
Stat recomputation, unchanged equipment, ordinary bag moves, and initial
character construction do not start fresh equip timers. Existing character
storage and initial-spell projection restore cooldowns on reconnect.

References inspected at VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`:

- `Player::ApplyEquipCooldown`, `Player::EquipItem`, `Player::CanEquipItem`,
  and `Player::AddCooldown` in `refs/vmangos/src/game/Objects/Player.cpp`.
- `ItemPrototype::CanChangeEquipStateInCombat` and the item exemption flag.
- `SpellCaster::AddGCD` and build-specific swap spell constants in
  `SharedDefines.h`. Local DBC spells 6119 and 6123 have GCD category 133 and
  durations 1,500 and 1,000 ms respectively.
- `refs/wow_messages/wow_message_parser/wowm/world/item/smsg_item_cooldown.wowm`:
  opcode `0xB0`, item GUID as uint64, then spell ID as uint32.

## Automated acceptance

All **7,239 tests** passed, including database/map integration tests and the
architecture dependency ratchet. Compilation with warnings as errors passed;
strict Credo found zero issues across 2,562 source files. New regressions cover
all item spell slots, missing spells, exemptions, existing shorter/longer
cooldowns, deferred cooldowns, negative monotonic times, category behavior,
both class durations, timer expiry, cast cancellation, owner-only packets,
actual item-use rejection without charge consumption, atomic rejection of
combat inventory changes, and both inventory commit forms.

## Native acceptance

The isolated GPU client used Blazing Emblem (2802, spell 13744), obtained with
`.additem`. Equipping through the native cursor and bind confirmation displayed
**30 seconds**, with 25 seconds remaining in the first screenshot. An immediate
use displayed **Item is not ready yet**; the owner retained the equip deadline
and had no Blazing Emblem aura. After expiry, native activation displayed its
buff and normal **600-second** cooldown.

Moving the item to the other trinket slot preserved the original deadline
`-576459795994` on the server and the 600-second timer on the client. Attempting
to put it in the backpack during combat displayed **You can't do that while
in combat** and left it equipped.

The hunter's pet attacked the seeded Blackrock Warlock near
`{16653.2, 16198.1}` on map 451. The owner remained at roughly 30 yards and
retained full health. The initial swap back to the seeded Barman Shanker was
correctly rejected for missing dagger training. After `.learn 1180`, swapping
from Mining Pick to Barman Shanker produced this sequence in a 50-ms sampler:

| Relative time | Authoritative result |
| --- | --- |
| 5,793 ms | Owner enters combat through pet contact |
| 7,133 ms | Mainhand changes; weapon timer and GCD are active |
| 8,628 ms | Both timers have expired |
| 9,502 ms | Retried Aspect of the Monkey applies aura 13163 |

The swap deadline was `-576460125238`; the first equipped observation was
12 ms after its 1,500-ms timer started. The native cooldown observer printed
**1.5**. Casting Aspect of the Monkey in the same input sequence as the swap
displayed **Spell is not ready yet**, with the corresponding server validation
failure. Retrying after the deadline succeeded. The one-second rogue duration
and repeated-weapon rejection are covered by deterministic tests.

After retreat and normal logout, `Entity.pid(7)`, world position, and metadata
were all absent. Character storage retained the trinket and its exact cooldown
deadline. Reconnecting displayed a **600-second** timer with 225 seconds left;
an immediate use remained blocked. The owner probe confirmed the unchanged
deadline, no combat, and no active weapon timer or GCD.

The client used hardware OpenGL on the RX 7900 XT. WoW PID 2485184's own amdgpu
graphics counter advanced from 635,464,810 to 27,903,274,885 ns. No server errors
occurred. Warnings were the deliberate `not_ready` check and existing account
data / GM ticket messages. The helper-owned client and retained server stopped.

## Retained local evidence

- Session: `/home/pikdum/.cache/thistle-wow-playtest.jSVcxE`.
- Screenshots: `equipped-30-seconds.png`, `trinket-activated.png`,
  `combat-equip-rejected.png`, `combat-weapon-gcd-accepted.png`,
  `logged-out.png`, and `cooldown-reconnected.png` in its `screenshots/`.
- `/tmp/thistle-equipment-accepted.log`, `thistle-equipment-used-deadline.log`,
  `thistle-equipment-reequipped.log`, `thistle-equipment-combat-accepted-sample.log`,
  `thistle-equipment-after-combat.log`, `thistle-equipment-logout.log`, and
  `thistle-equipment-reconnected.log`.
- Server, warning audit, GPU proof, DBC reference, and final gates:
  `/tmp/thistle-equipment-{server,warnings,gpu-proof,dbc-reference,all,compile,credo}.log`.
