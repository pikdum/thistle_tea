defprotocol ThistleTea.Game.Network.Message do
  @moduledoc """
  Protocol implemented by every network message struct: binary encoding,
  packet building, and opcode lookup. Handling decoded client messages is a
  world concern; see `ThistleTea.Game.World.Inbound`.
  """
  def to_binary(message)
  def to_packet(message)
  def opcode(message)
end

defmodule ThistleTea.Game.Network.ClientMessage do
  @moduledoc """
  `use` macro for CMSG_* message modules: wires up the opcode, common aliases,
  and the `Message` protocol implementation around `from_binary/1`.
  """
  alias ThistleTea.Game.Network.Opcodes

  @callback opcode() :: integer()
  @callback from_binary(payload :: binary()) :: struct()
  defmacro __using__(opcode) do
    opcode = Opcodes.get(opcode)

    quote do
      @behaviour ThistleTea.Game.Network.ClientMessage

      alias ThistleTea.Game.Core.Entity.Component.MovementBlock
      alias ThistleTea.Game.Network.BinaryUtils
      alias ThistleTea.Game.Network.ClientMessage
      alias ThistleTea.Game.Network.Message

      @impl ClientMessage
      def opcode, do: unquote(opcode)

      defimpl Message do
        def to_binary(_message), do: raise("unimplemented")
        def to_packet(_message), do: raise("unimplemented")

        def opcode(message), do: unquote(opcode)
      end
    end
  end
end

defmodule ThistleTea.Game.Network.ServerMessage do
  @moduledoc """
  `use` macro for SMSG_* message modules: wires up the opcode, common aliases,
  and the `Message` protocol implementation around `to_binary/1`.
  """
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet

  @callback opcode() :: integer()
  @callback to_binary(message :: struct()) :: binary()
  @callback to_packet(message :: struct()) :: Packet.t()
  defmacro __using__(opcode) do
    opcode = Opcodes.get(opcode)

    quote do
      @behaviour ThistleTea.Game.Network.ServerMessage

      alias ThistleTea.Game.Core.Entity.Character
      alias ThistleTea.Game.Network.BinaryUtils
      alias ThistleTea.Game.Network.Message
      alias ThistleTea.Game.Network.Packet
      alias ThistleTea.Game.Network.ServerMessage

      @impl ServerMessage
      def opcode, do: unquote(opcode)

      @impl ServerMessage
      def to_packet(message) do
        to_binary(message)
        |> Packet.build(unquote(opcode))
      end

      defimpl Message do
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
