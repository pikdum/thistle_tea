---
name: client-message
description: Implement Thistle Tea CMSG_* client messages following our architecture patterns. Use this when asked to implement a new message or you need to use one that isn't implemented yet.
---

A client message has two halves:

1. A pure codec under `lib/game/network/message/` that decodes the payload.
2. A handler clause under `lib/game/world/inbound/` that routes the decoded struct into a world system.

Network message modules never call into the world; `boundary` rejects it at compile time.

## Codec

Create/modify a module under `lib/game/network/message/` that:

- `use ThistleTea.Game.Network.ClientMessage, :CMSG_FOO`
- defines a `defstruct` matching the fields decoded from the payload
- implements `from_binary/1` using little-endian bit syntax patterns like `<<x::little-size(32)>>`

Then register the opcode in `@messages` in `lib/game/network/message/dispatch.ex` so packets decode into the struct.

Minimal payload (`CMSG_PING`):

```elixir
defmodule ThistleTea.Game.Network.Message.CmsgPing do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PING

  defstruct [:sequence_id, :latency]

  @impl ClientMessage
  def from_binary(payload) do
    <<sequence_id::little-size(32), latency::little-size(32)>> = payload

    %__MODULE__{
      sequence_id: sequence_id,
      latency: latency
    }
  end
end
```

Payload with strings (`CMSG_MESSAGECHAT`):

```elixir
def from_binary(payload) do
  <<chat_type::little-size(32), language::little-size(32), rest::binary>> = payload
  {:ok, message, _rest} = BinaryUtils.parse_string(rest)

  %__MODULE__{
    chat_type: chat_type,
    language: language,
    message: message
  }
end
```

## Handler

Pick the domain module in `lib/game/world/inbound/` (guild, trade, movement, ...), add the struct to its `messages/0` list, and add a `handle/2` clause that pattern matches the struct:

```elixir
def handle(%Message.CmsgGuildQuery{guild_id: id}, state), do: Guilds.query(state, id)
```

- Keep clauses as dispatch: destructure the message and call a system module (`World.Entity.Player.*`, `World.System.*`). Game logic belongs in that system module or in `Core`, not in the inbound clause.
- `state` is the player process state once the character is in the world. Messages that arrive before login (auth, character screen, ping) get the connection's `%ConnectionState{}` and belong in `Inbound.Session`.
- A clause for every routed message must match its own struct in the head; never add a catch-all `handle(message, state)` clause to a domain module.

## How to find the packet spec

- `refs/vmangos/` is the primary reference for 1.12 behavior and packet layouts; `refs/mangos/` is secondary.
- Packet formats are also cataloged in `refs/wow_messages/wow_message_parser/wowm/*/${CMSG_NAME}.wowm`, but those specs are sometimes wrong, so cross-check against vmangos.
- Thistle Tea is a Vanilla (patch 1.12.1) server, so ignore future client versions.
