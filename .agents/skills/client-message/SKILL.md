---
name: client-message
description: Implement Thistle Tea CMSG_* client messages following our architecture patterns. Use this when asked to implement a new message or you need to use one that isn't implemented yet.
---

Create/modify a module under `lib/game/network/message/` that:

- `use ThistleTea.Game.Network.ClientMessage, :CMSG_FOO`
- defines a `defstruct` matching the fields decoded from the payload
- implements `from_binary/1` using little-endian bit syntax patterns like `<<x::little-size(32)>>`
- implements `handle/2` to update state and send any responses

## Quick examples

Minimal payload (`CMSG_PING`):

```elixir
defmodule ThistleTea.Game.Network.Message.CmsgPing do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PING

  defstruct [:sequence_id, :latency]

  @impl ClientMessage
  def handle(%__MODULE__{sequence_id: sequence_id, latency: latency}, state) do
    Network.send_packet(%Message.SmsgPong{sequence_id: sequence_id})
    Map.put(state, :latency, latency)
  end

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

## How to find the packet spec

- Packet formats are cataloged in the `wow_messages` git submodule at `refs/wow_messages/`.
- Look up the `.wowm` spec here: `refs/wow_messages/wow_message_parser/wowm/*/${CMSG_NAME}.wowm`.
- Thistle Tea is a Vanilla (patch 1.12.1) server, so ignore future client versions.
- The `refs/mangos/` directory contains the Mangos C++ server codebase and can be used as a reference for expected `handle/2` behavior.

## Workflow

- Translate the `.wowm` fields into `defstruct` fields and a decoder in `from_binary/1`.
- Use pattern matching in the function head for type safety: `handle(%__MODULE__{} = msg, state)`.
- Register the new handler in `lib/game/network/packet.ex` under the `@l` map so packets dispatch correctly.
