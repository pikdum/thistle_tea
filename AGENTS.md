# Thistle Tea - AGENTS.md

## Commands

### Build/Test/Lint
- `mix test` - Run all tests
- `mix test test/path/to/file_test.exs` - Run specific test file
- `mix test test/path/to/file_test.exs:123` - Run specific test at line 123
- `mix test.watch` - Run tests in watch mode
- `mix credo` - Run linting
- `mix format` - Format code
- `mix build_maps` - Generate navigation meshes from map files

## Code Style

### Development
- Ensure `mix test` passes before completing tasks

### Testing
- Use `describe "function/arity" do ... end` to group tests by function
- Use `setup [:named_setup]` for reusable test data
- Keep test names concise and descriptive

### Imports & Structs
- Use `use ThistleTea.Game.Network.Opcodes, [:SMSG_FOO, :CMSG_BAR]` macro to define opcode attributes
- Pattern match on structs in function heads for type safety: `def foo(%Struct{field: val} = entity, ...)`
- Entities are composed of component structs (Object, Unit, Player, GameObject, etc.)

### Network Messages
- Server messages: `use ServerMessage, :SMSG_FOO`, implement `to_binary/1`
- Client messages: `use ClientMessage, :CMSG_FOO`, implement `from_binary/1` and `handle/2`
- Use `<<value::little-size(32)>>` binary patterns for packet parsing

### Architecture Patterns
- Functional core with process boundary layers (GenServers, Registries, ETS tables)
- World systems for cross-cutting concerns (CellActivator, SpatialHash, Pathfinding)
- Network layer abstracts packet handling - use message structs, not raw binaries
- Entity-component inspired design: entities = composition of component structs

### Formatting
- No comments in code (keep functions self-documenting via naming)
- Use snake_case for atoms and files, PascalCase for modules

### Error Handling
- Use `rescue` blocks in GenServer handle callbacks to prevent crashes
- Prefer pattern matching and guards for validation
