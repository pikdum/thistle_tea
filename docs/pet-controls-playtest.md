# Pet action bars and autocast

Validated on 2026-09-25 with the native build-5875 client.
Implementation: `1da23349`.

## Behavior

Pet-bar edits and the dedicated `CMSG_PET_SPELL_AUTOCAST` request now pass through
one creature-owned transition. The player first checks its active companion;
the creature checks its current owner and whether its controls are available.
The character retains the returned settings only after the creature accepts the
request. Unknown spells, passive spells, invalid positions and types, duplicate
positions, and edits that remove or duplicate command/reaction buttons fail
without applying either half of the edit. Manual-only spells cannot enter the
AI autocast set.

Autocast changes repaint every instance of the spell on the bar. Attachment
restores and validates the retained layout against the current spellbook before
sending the pet packet. Training upgrades and untraining use the same retained
settings path. Defaults, spell flags, and layout normalization are shared by
training and packet projection. Retention uses the existing in-memory companion
lifecycle; server restart still wipes characters and pets.

References:

- `refs/wow_messages/wow_message_parser/wowm/world/pet/cmsg_pet_spell_autocast.wowm`
- `refs/vmangos/src/game/Handlers/PetHandler.cpp`: `HandlePetSetAction`,
  `HandlePetSpellAutocastOpcode`
- `refs/vmangos/src/game/Spells/SpellEntry.h`: `IsAutocastable`

## Automated validation

All 6,107 tests passed with `mix test.all`. Compilation with warnings as errors,
strict Credo, formatting, and `git diff --check` passed. The dependency allowlist
was unchanged. Tests exercise ownership rejection, disabled controls, atomic
edits, command swaps, invalid spells/types/slots, autocast across duplicate
buttons, manual-only spell projection, stale spell filtering, attachment,
suspension/reactivation, replacement, training upgrades, and untraining.

## Native acceptance

Debugwarlock summoned an Imp on Programmer Isle through `/cast Summon Imp`.
Mouse input performed the following actions; Tidewave probes only read state
and temporarily traced incoming client messages.

1. Right-clicking Blood Pact on the pet bar sent `CMSG_PET_SET_ACTION` for spell
   11767 with type `0xC1`. Both the Imp and character retained it as enabled, and
   the Imp actually applied Blood Pact to itself and its owner.
2. Right-clicking Firebolt in the pet spellbook sent
   `CMSG_PET_SPELL_AUTOCAST` for spell 11762 with `enabled?: true`. Both owners'
   sets became `{11762, 11767}`, and Firebolt's existing bar button changed to
   `0xC1`.
3. Dragging Attack onto Firebolt sent a two-position `CMSG_PET_SET_ACTION`.
   Firebolt moved to slot zero and Attack to slot four. The visible bar, creature
   bar, and retained character bar agreed.
4. Normal logout suspended the companion with that full layout and autocast set.
   The old Imp GUID `17383894568633630807` had no process, world position, or
   metadata after logout; the player process was also gone.
5. Login created Imp GUID `17383894568633630846`. The moved buttons and both
   enabled spells survived in the client and both owners' state. The new Imp
   applied Blood Pact again.
6. Right-clicking Firebolt in the spellbook after reconnect sent
   `CMSG_PET_SPELL_AUTOCAST` with `enabled?: false`. Its moved slot-zero button
   became `0x81`, and both autocast sets retained only Blood Pact.

No owner, pet-control, protocol-dispatch, or spell errors occurred during these
operations. The ordinary login warnings for account data, GM ticket, and
meeting-stone requests remain unrelated to this feature.

The isolated session was `/home/pikdum/.cache/thistle-wow-playtest.i4uGVW`.
Screenshots include `imp.png`, `pet-book.png`, `moved.png`, `restored.png`, and
`disabled.png`. WoW PID 886037 used AMD device `0000:0c:00.0`; its own DRM graphics
counter advanced from 2,966,637,215 to 15,198,155,026 ns. Evidence is retained in
`/tmp/thistle-pet-controls-{actions,disable,moved,logout,restored,disabled-state,native-server}.log`.

Final normal logout also retained Firebolt as disabled. Its replacement Imp's
process, world position, and metadata were removed. The helper-owned client
service and retained server PTY were stopped after acceptance.
