defprotocol ThistleTea.Game.Network.Message do
  def to_binary(message)
  def to_packet(message)
  def opcode(message)
  def handle(message, state)
end

defmodule ThistleTea.Game.Network.ClientMessage do
  alias ThistleTea.Game.Network.Opcodes

  @callback opcode() :: integer()
  @callback handle(message :: struct(), state :: map()) :: map()
  @callback from_binary(payload :: binary()) :: struct()
  defmacro __using__(opcode) do
    opcode = Opcodes.get(opcode)

    quote do
      @behaviour ThistleTea.Game.Network.ClientMessage

      alias ThistleTea.Character
      alias ThistleTea.Game.Entity.Data.Component.MovementBlock
      alias ThistleTea.Game.Entity.Data.Component.Unit
      alias ThistleTea.Game.Network
      alias ThistleTea.Game.Network.ClientMessage
      alias ThistleTea.Game.Network.Connection
      alias ThistleTea.Game.Network.Message
      alias ThistleTea.Game.Network.UpdateObject
      alias ThistleTea.Util

      @impl ClientMessage
      def opcode, do: unquote(opcode)

      defimpl Message do
        def to_binary(_message), do: raise("unimplemented")
        def to_packet(_message), do: raise("unimplemented")

        def handle(message, state) do
          unquote(Macro.escape(__CALLER__.module)).handle(message, state)
        end

        def opcode(message), do: unquote(opcode)
      end
    end
  end
end

defmodule ThistleTea.Game.Network.ServerMessage do
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet

  @callback opcode() :: integer()
  @callback to_binary(message :: struct()) :: binary()
  @callback to_packet(message :: struct()) :: Packet.t()
  defmacro __using__(opcode) do
    opcode = Opcodes.get(opcode)

    quote do
      @behaviour ThistleTea.Game.Network.ServerMessage

      alias ThistleTea.Character
      alias ThistleTea.Game.Network.Message
      alias ThistleTea.Game.Network.Packet
      alias ThistleTea.Game.Network.ServerMessage
      alias ThistleTea.Util

      @impl ServerMessage
      def opcode, do: unquote(opcode)

      @impl ServerMessage
      def to_packet(message) do
        to_binary(message)
        |> Packet.build(unquote(opcode))
      end

      defimpl Message do
        def handle(_message, _state), do: raise("unimplemented")

        def to_packet(message) do
          unquote(Macro.escape(__CALLER__.module)).to_packet(message)
        end

        def to_binary(message) do
          unquote(Macro.escape(__CALLER__.module)).to_binary(message)
        end

        def opcode(message), do: unquote(opcode)
      end
    end
  end
end
