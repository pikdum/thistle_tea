# Hunter pet naming and abandonment

Hunter pets expose the normal Pet Details, Rename, and Abandon menu. A pet can
receive one chosen name, using two to twelve letters from a supported Latin,
Cyrillic, or East Asian script. Invalid names leave the rename permission intact.
The Vanilla invalid-name packet is empty; it does not use the later expansion's
reason and declined-name fields.

`Companion.name` retains a typed `PetName` with its client cache timestamp.
The player serializes requests, the pet owner process validates ownership and
permission again, and `PetNaming` performs the pure transition. Updating the
timestamp invalidates the name cache even when creation and naming happen in
the same second. The pet publishes its new metadata and update fields;
same-world observers can answer the resulting name query.

Dismissal, owner death, process loss, stabling, and reconnect retain the name and
consumed rename permission. A different or abandoned pet does not inherit it.
The stable window uses the retained chosen name. Abandonment uses the existing
companion suspension and cleanup boundary, then clears the current bond and
client controls without changing pets in the stable. CharacterStore remains
an in-memory runtime store, consistent with the rest of the server.

The protocol and behavior references are VMangos `PetHandler.cpp`, `Pet.cpp`,
`ObjectMgr::CheckPetName`, and the Vanilla pet packet definitions in
`refs/wow_messages/`. Native testing found that publishing the rename bit alone
is insufficient: the client also requires the hunter pet abandon bit to choose
the hunter menu. Both permissions and the abandon handler are now implemented.

## Native acceptance

Two isolated build-5875 GPU clients used Debughunter and Debugbuyer on a fresh
server. All state probes were read-only.

- The hunter renamed Prairie Wolf Alpha to Fang through the pet portrait menu,
  text dialog, and confirmation. Rename disappeared while Pet Details and
  Abandon remained. The observer displayed Fang in its target frame and above
  the pet. The owner, CharacterStore, live pet, and metadata agreed on the name
  and timestamp `1790143788`; the pet number stayed `4194329`.
- Dismiss Pet removed the old process and spatial position. Call Pet created a
  new live GUID with the same chosen name and rename permission already used.
- Jenova Stoneshield's normal stable window displayed Fang. Purchasing a slot,
  dragging the pet into it, and retrieving it retained the name, timestamp,
  pet number, health, and progression.
- Logout saved the suspended named companion. Reconnect created a new pet,
  retained the same name and number, and left the previous process, metadata,
  and spatial position absent.
- Owner death and release removed the live pet while retaining its name in the
  suspended bond. After corpse recovery, Call Pet restored Fang with the same
  name, timestamp, pet number, and consumed rename permission.
- Abandon through the normal menu and confirmation removed the pet bar, current
  bond, owner monitor, live process, metadata, and spatial entry. Call Pet then
  displayed "You do not have a pet". CharacterStore also contained no current
  pet; the purchased stable slot remained.

Both WoW processes used the GPU: their own DRM graphics counters increased from
3.55 to 25.27 billion ns and from 2.75 to 24.55 billion ns. There were no
error-level logs or unsupported pet commands. Existing account-data, raid-info,
GM-ticket, and meeting-stone login warnings were unrelated to these actions.
Both helper-owned client services are inactive, all recorded owned processes
are absent, and the server has stopped with its listeners closed.

Evidence is retained in `/tmp/thistle-pet-naming-*.txt`,
`/tmp/thistle-pet-naming-final-server.log`, and the screenshot directories under
`/home/pikdum/.cache/thistle-wow-playtest.wq0ucO/` (hunter) and
`/home/pikdum/.cache/thistle-wow-playtest.tRaFS5/` (observer).

Automated regressions cover name validity, one-time permission, timestamp
changes, wrong owners, broken bonds, foreign GUIDs, stable retention, old
attachments, abandonment cleanup, packet dispatch and encoding, observer name
queries, world isolation, and loader restoration.

Final validation passed: `mix test.all` (4,951 tests),
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix format --check-formatted`, and `git diff --check`.
