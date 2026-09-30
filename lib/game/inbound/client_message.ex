defmodule ThistleTea.Game.Inbound.ClientMessage do
  @moduledoc """
  `use` macro for client message modules: wires up the opcode and common
  aliases, and implements `ThistleTea.Game.World.ClientInput` around the
  module's `handle/2`.

  Pass the opcode alone, or `opcode: :CMSG_FOO, while_possessed: true` for a
  message that a possessed player's client must still be able to send.
  """
  alias ThistleTea.Game.Network.Opcodes

  @callback opcode() :: integer()
  @callback from_binary(payload :: binary()) :: struct()
  @callback handle(message :: struct(), state :: term()) :: term()

  defmacro __using__(opcode) when is_atom(opcode), do: build(opcode, false)

  defmacro __using__(opts) when is_list(opts) do
    build(Keyword.fetch!(opts, :opcode), Keyword.get(opts, :while_possessed, false))
  end

  defp build(opcode, while_possessed?) do
    opcode = Opcodes.get(opcode)

    quote do
      @behaviour ThistleTea.Game.Inbound.ClientMessage

      alias ThistleTea.Game.Core.Entity.Component.MovementBlock
      alias ThistleTea.Game.Inbound
      alias ThistleTea.Game.Inbound.ClientMessage
      alias ThistleTea.Game.Network.BinaryUtils
      alias ThistleTea.Game.Network.Message

      @impl ClientMessage
      def opcode, do: unquote(opcode)

      defimpl ThistleTea.Game.World.ClientInput do
        use Boundary, classify_to: Inbound

        def handle(message, state), do: @for.handle(message, state)
        def while_possessed?(_message), do: unquote(while_possessed?)
      end
    end
  end
end
