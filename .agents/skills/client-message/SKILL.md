---
name: client-message
description: Implement Thistle Tea CMSG_* client messages following our architecture patterns. Use this when asked to implement a new message or you need to use one that isn't implemented yet.
---

A client message is one module under `lib/game/inbound/` (`ThistleTea.Game.Inbound.CmsgFoo`) that both decodes its payload and handles the decoded struct by calling into the world.

The inbound layer sits above the world: it may call World, Core, Network, and Auth, but nothing below it may reference an inbound module. `boundary` rejects that at compile time. World code never names a client message; the player process applies one through the `ThistleTea.Game.World.ClientInput` protocol, which the `use` macro implements.

## Module

Create or modify a module under `lib/game/inbound/` that:

- has `use ThistleTea.Game.Inbound.ClientMessage, :CMSG_FOO`
- defines a `defstruct` matching the fields decoded from the payload
- implements `from_binary/1` using little-endian bit syntax patterns like `<<x::little-size(32)>>`
- implements `handle/2`, which pattern matches `%__MODULE__{}` and dispatches into a world system

Then register the opcode in `@messages` in `lib/game/inbound/dispatch.ex` so packets decode into the struct.

The macro aliases `ClientMessage`, `Message` (server messages, `ThistleTea.Game.Network.Message`), `BinaryUtils`, and `MovementBlock`. Alias the world modules the handler calls yourself.

Use `use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_FOO, while_possessed: true` only for messages a player's client must still be able to send while another unit possesses the player. These are connection, chat, logout, cache query, and movement acknowledgement traffic. Everything else is suspended during possession.

A minimal payload, `CMSG_GROUP_INVITE`:

```elixir
defmodule ThistleTea.Game.Inbound.CmsgGroupInvite do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GROUP_INVITE

  alias ThistleTea.Game.World.Entity.Player.Groups

  defstruct [:name]

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end

  @impl ClientMessage
  def handle(%__MODULE__{name: name}, state), do: Groups.invite(state, name)
end
```

A payload with strings, from `CMSG_MESSAGECHAT`:

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

## Handling

- Keep `handle/2` as dispatch: destructure the message and call a system module (`World.Entity.Player.*`, `World.System.*`). Game logic belongs in that system module or in `Core`, not in the message module.
- `state` is the player process state once the character is in the world. Messages that arrive before login (auth, character screen, ping) get the connection's `%ConnectionState{}`. `Inbound.Session` handles pings on the connection even after login.
- Every clause matches `%__MODULE__{}` in its head. Guard on state (`%{ready: true}`, in-combat checks) with extra clauses, and end with a `def handle(%__MODULE__{}, state), do: state` fallback when some states should ignore the message.
- World code never names an inbound module. Destructure a few fields in the head and pass them, or hand the whole struct to a world function that reads many of its fields (`Mail.send_mail/2`, `Auction.search/2`).
- `MSG_MOVE_*` is the exception: `Network.Message.MsgMove` stays in Network because the world also builds and rebroadcasts it. Its `ClientInput` implementation lives in `lib/game/inbound/msg_move.ex`.

## How to find the packet spec

- `refs/vmangos/` is the primary reference for 1.12 behavior and packet layouts; `refs/mangos/` is secondary.
- Packet formats are also cataloged in `refs/wow_messages/wow_message_parser/wowm/*/${CMSG_NAME}.wowm`, but those specs are sometimes wrong, so cross-check against vmangos.
- Thistle Tea is a Vanilla (patch 1.12.1) server, so ignore future client versions.
