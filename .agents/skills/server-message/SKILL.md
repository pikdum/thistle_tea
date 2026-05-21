---
name: server-message
description: Implement Thistle Tea SMSG_* server messages following our architecture patterns. Use this when asked to implement a new message or you need to use one that isn't implemented yet.
---

Create/modify a module under `lib/game/network/message/` that:

- `use ThistleTea.Game.Network.ServerMessage, :SMSG_FOO`
- defines a `defstruct` matching the fields needed to encode the packet
- implements `to_binary/1` using little-endian bit syntax patterns like `<<x::little-size(32)>>`

## Quick examples

Minimal payload (`SMSG_PONG`):

```elixir
defmodule ThistleTea.Game.Network.Message.SmsgPong do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PONG

  defstruct [:sequence_id]

  @impl ServerMessage
  def to_binary(%__MODULE__{sequence_id: sequence_id}) do
    <<sequence_id::little-size(32)>>
  end
end
```

Conditional payload (`SMSG_AUTH_RESPONSE`):

```elixir
defmodule ThistleTea.Game.Network.Message.SmsgAuthResponse do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_AUTH_RESPONSE

  @result_auth_ok 0x0C
  @result_auth_wait_queue 0x1B

  defstruct [:result, :billing_time, :billing_flags, :billing_rested, :queue_position]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = msg) do
    <<msg.result::little-size(8)>> <>
      case msg.result do
        @result_auth_ok ->
          <<msg.billing_time::little-size(32), msg.billing_flags::little-size(8),
            msg.billing_rested::little-size(32)>>

        @result_auth_wait_queue ->
          <<msg.queue_position::little-size(32)>>

        _ ->
          <<>>
      end
  end
end
```

## How to find the packet spec

- Packet formats are cataloged in the `wow_messages` git submodule at `refs/wow_messages/`.
- Look up the `.wowm` spec here: `refs/wow_messages/wow_message_parser/wowm/*/${SMSG_NAME}.wowm`
- Note that Thistle Tea is a Vanilla (patch 1.12.1) server, so ignore future client versions

## Workflow

- Translate the `.wowm` fields into `defstruct` fields and an encoder in `to_binary/1`.
- Use pattern matching in the function head for type safety: `to_binary(%__MODULE__{} = msg)`.
