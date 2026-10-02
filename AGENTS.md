# Thistle Tea - AGENTS.md

## Commands

### Build/Test/Lint
- `mix compile --warnings-as-errors` - Compile (warnings are not allowed)
- `mix test` - Run all tests
- `mix test.all` - Run all tests, including DBC, VMangos, and Namigator map integration tests
- `mix test test/path/to/file_test.exs` - Run specific test file
- `mix test test/path/to/file_test.exs:123` - Run specific test at line 123
- `mix credo --strict` - Run linting (must stay at zero issues; enforced as a pre-commit hook via devenv)
- `mix format` - Format code

## Code Style

### Development
- Ensure `mix test.all` and `mix credo --strict` pass before completing tasks

### Testing
- Use `describe "function/arity" do ... end` to group tests by function
- Use `setup [:named_setup]` for reusable test data
- Keep test names concise and descriptive
- Mint guids, ids, and names with `ThistleTea.Test.Unique.integer/0`, never `System.unique_integer/1` or a hand-picked offset: async tests share the entity registry and stores, and independently minted values collide. Draw once per id (`Unique.integer() + 1` can equal another test's next draw), and match `{:ok, _} = Entity.register(guid)` so a duplicate fails loudly
- Do not query generated sqlite databases in default tests; `db/vmangos.sqlite` tests must be tagged `:vmangos_db`, and tests that query `db/dbc.sqlite` must be tagged `:dbc_db`
- Database and map tags are mutually exclusive: a test must never have more than one of `:vmangos_db`, `:dbc_db`, and `:namigator_maps`. Split a test or use fixtures when it needs data from more than one unavailable source
- `:vmangos_db` tests require generated VMangos data and run with `mix test --only vmangos_db`; `:dbc_db` tests require the DBC database and are not run by CI; `:namigator_maps` tests require Namigator map data and are not run by CI
- CI runs `mix test` first, then generates `db/vmangos.sqlite` and runs only `:vmangos_db` tests; the mutually exclusive tags keep DBC and map tests out of that run
- Tests that need Namigator map geometry (line of sight, terrain heights, or pathfinding) must be tagged `:namigator_maps`; run them with `mix test --include namigator_maps`

### Imports & Structs
- Use `use ThistleTea.Game.Network.Opcodes, [:SMSG_FOO, :CMSG_BAR]` macro to define opcode attributes
- Pattern match on structs in function heads for type safety: `def foo(%Struct{field: val} = entity, ...)`
- Use struct-update syntax and dot access on structs (`%{s | f: v}`, `s.field`), never `Map.put`/`Map.get` — struct-update raises on an unknown field (type-safe) while `Map.put` silently adds bogus keys. `Map.*` is only for genuine plain maps (`Metadata`/ETS rows, DB rows, ad-hoc maps, or a value that may be a struct *or* a map)
- Entities are composed of component structs (Object, Unit, Player, GameObject, etc.)
- Module names keep their domain prefix when the bare name would be ambiguous once aliased (`Core.Combat.CombatTimer`, `Core.Pet.PetStable`). When a core module collides with a world module in the same file, alias the core one as `<Name>Core` (`alias ThistleTea.Game.Core.Aura, as: AuraCore`). World modules and behavior trees are aliased by role (`SpellLoader`, `PartySystem`, `PlayerServer`, `MobBT`)

### Network Messages
- Server messages: `use ServerMessage, :SMSG_FOO`, implement `to_binary/1`
- Client messages: one module per message in `lib/game/inbound/` (`Inbound.CmsgFoo`). `use Inbound.ClientMessage, :CMSG_FOO`, implement `from_binary/1` and `handle/2` side by side, and register the opcode in `Inbound.Dispatch`. Use `opcode: :CMSG_FOO, while_possessed: true` for messages a possessed player's client must still be able to send
- Use `<<value::little-size(32)>>` binary patterns for packet parsing

### Layout and Layers
- `lib/game/core/` (`ThistleTea.Game.Core`): pure data and rules, grouped by domain (`combat/`, `spell/`, `aura/`, `item/`, `quest/`, `pet/`, `class/`, ...). Things that use SMSG_UPDATE_OBJECT (character, mob, game object, item, corpse, dynamic object) and their components live in `core/entity/`; generic entity operations are `Core.Entity`
- `lib/game/world/` (`ThistleTea.Game.World`): everything effectful. `world/entity/` holds the entity owner processes (player, mob, game object, ...) with their event sinks and effect resolvers; `world/system/` holds shared-owner GenServers (party, guild, battleground, instance, ...); `world/loader/` translates seed rows into core structs and caches them; root modules are shared infrastructure (Metadata, SpatialHash, stores, Pathfinding, Visibility)
- `lib/game/network/` (`ThistleTea.Game.Network`): the connection handler, header crypto, opcodes, binary helpers, and server message encoders. It hands framed packets to the `Network.Session` behaviour, whose implementation (`Inbound.Session`) the application passes in at startup
- `lib/game/inbound/` (`ThistleTea.Game.Inbound`): client input, above the world the way a web layer sits above its domain. Each client message module decodes its payload and handles the struct by calling into the world; `Inbound.Session` decodes packets and routes messages to the connection or the player process
- Module names follow their paths: `lib/game/core/combat/threat.ex` is `ThistleTea.Game.Core.Combat.Threat`
- The `boundary` compiler enforces the layering: Core depends on nothing, Network on Core, World on Core, Network, DB, Auth, and Native, and Inbound on Core, Network, World, and Auth. Nothing but the application depends on Inbound. `ThistleTea.DB` (VMangos and DBC schemas) depends on nothing. A forbidden reference is a compiler warning, so `--warnings-as-errors` rejects it. Core has no `dirty_xrefs`; never add one. Pass the data in instead, or, when core must ask the world synchronously, define a port behaviour in core that a world module implements (`Core.Spell.TargetResolver`, wired by `config :thistle_tea, :spell_target_resolver`)

### Architecture Patterns
- Functional core / boundary layer split (à la "Designing Elixir Systems with OTP"): the core handles data + logic and stays pure; the boundary handles process orchestration (GenServers, Registries, ETS tables)
- Keep the core pure: functions like `take_damage` operate on entity/component data and return new data — no DB calls, no process sends, no side effects. This makes logic generic across players, mobs, and game objects, and trivially testable
- Time and randomness are inputs: core takes `now` as a parameter and never reads the clock (`Core.Time.now/0` is for world callers), and rolls come from a caller-supplied source — a roll argument, `BT.Context.Random`, or the `Core.Rolls` on `CastContext` (pin with `Rolls.fixed/1` in tests, not `:rand.seed`). `dependency_test.exs` ratchets both: no clock reads in core, and no new files with ambient `:rand`/`Enum.random` draws
- Database queries live at the boundary, not in the core. Loaders (e.g. `lib/game/world/loader/mob.ex` and `World.Loader.Mob.Builder`) query Mangos and translate rows into core structs (e.g. `lib/game/core/entity/mob.ex`); core code never touches `Mangos.*` or `DBC.*` schemas
- Runtime state is decoupled from the Mangos DB — Mangos is a read-only seed at boundaries, not the system's source of truth at runtime
- No Mangos queries in gameplay paths: loaders cache in ETS (boot preload or lazy + cache); CMSG handlers and game systems answer from those caches, never `Mangos.Repo` per request
- Effects as data: pure logic enqueues typed `Core.Effects.*` structs with `Effects.enqueue/2`; the entity owner drains them with `EventSink.emit_pending/1`. `EffectResolver` turns semantic requests into concrete effects, and `EventSink` projects them. Owner-local delivery uses `EventSink.Context`, never ambient `self()` or direct packet sends in interpreters
- `World.Metadata` is a denormalized ETS read cache (faction, level, alive?, …) so processes can check other entities without IPC; only the entity's owning boundary process writes its own metadata. Player metadata and `SpatialHash` publication go through `World.Presence`; use `World.position/1` instead of caching `:world` in metadata
- `Core.Combat.Hostility` is pure over reaction actors (Metadata-shaped maps with a `:guid` and the controlling player's projection under `:owner`); a struct or a map without `:guid` raises instead of silently degrading to faction templates. Behavior-tree code builds them with `Perception.actor/2`, and core code holding a struct uses `Hostility.actor/2`. World code calls `World.Reaction`, which resolves guids and structs. In a loop, build the caster actor once, not once per candidate
- Server message modules are pure encoders (`to_binary/1`) and never reference the world. Client message modules keep decoding and handling together: `handle/2` clauses dispatch into system modules (`World.Entity.Player.*`, `World.System.*`, `Core.*`), and game logic stays out of them. World code never names a client message; the player process applies one through the `World.ClientInput` protocol, which `use Inbound.ClientMessage` implements. Server messages go out through `World.Outbound.send_packet/3`
- No durable persistence by design until feature-complete; everything is wiped on restart. Runtime stores are plain ETS in the `ItemStore` shape (`ItemStore`, `CharacterStore`, `Account`). The player entity is `Core.Entity.Character`; saving means `CharacterStore.put/1`. Don't add disk persistence or reintroduce mnesia
- World systems for cross-cutting concerns (CellActivator, SpatialHash, Pathfinding, GameEvent)
- Network layer abstracts packet handling — use message structs, not raw binaries
- Entity-component inspired design: entities = composition of component structs (Object, Unit, Player, GameObject, …), so one implementation can work across entity types
- Derived stats, never mutated stats: displayed unit fields (stats, resistances, max health/mana, attack power, weapon damage, movement speeds) are outputs of pure recompute functions (`Core.Stats.recompute/1`, `Core.Stats.MovementStats.recompute/1`) over three canonical inputs — `base_*` fields (naked level/DB values, written by `Player.Stats.apply`, entity builders, and weapon-equip sync), `unit.equipment_bonuses` (computed by `EquipmentStats.resync`), and active auras. To change a stat, write the base input and recompute; never write a derived field directly and never read a current field as an input (lazy "capture base from current" is how stale-snapshot bugs happen). Recompute skips fields whose base inputs are nil, which is how mobs keep their DB maxima/damage untouched
- Single funnel over multi-site bookkeeping: give each truth one owner and one transition path. Hang lifecycle effects off the state transition (for example health→0), not every entry point; use denormalized projections only behind a single writer
- Mob engagement lifecycle transitions go through `Core.Combat.Engagement`; `Core.Combat.Threat` owns threat values, not victim, tap, combat, death, or reset cleanup
- Multi-item inventory changes use `Inventory.Batch` → `Inventory.plan` → `Inventory.ChangeSet`; commit once with `InventoryUpdate.apply/2` only after the full plan succeeds
- Behavior trees are the primary abstraction for AI/action logic. `World.Entity.Mob` and `World.Entity.Player` tick them through `BehaviorRunner`/`TickPlan`; nodes consume immutable `BT.Context`, keep state in typed `Blackboard` subtrees, and enqueue `NavigationIntent` for `NavigationResolver`. Do not add direct world, metadata, pathfinding, clock, or random dependencies to new nodes
- `test/game/architecture/dependency_test.exs` backs these rules at file level: no core file references World, Network, or DB; core never reads the clock; the ambient-random allowlist only shrinks; plus event-sink and spatial-index rules. Do not expand its allowlists; remove entries as debt is eliminated

### Formatting
- No comments in code (keep functions self-documenting via naming); the only exceptions are TODO comments and `# credo:disable-for-next-line` markers where a refactor would hurt clarity
- Every module needs a `@moduledoc`; use `@moduledoc false` for self-explanatory modules (packet messages, ecto schemas, pure field-declaration components)
- Use snake_case for atoms and files, PascalCase for modules
- Use conventional commits

### Error Handling
- Use `rescue` blocks in GenServer handle callbacks to prevent crashes
- Prefer pattern matching and guards for validation
