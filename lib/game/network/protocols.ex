defprotocol ThistleTea.Game.Network.Message do
  @moduledoc """
  Protocol implemented by every server message struct: binary encoding,
  packet building, and opcode lookup. Client messages are decoded and handled
  by `ThistleTea.Game.Inbound`.
  """
  def to_binary(message)
  def to_packet(message)
  def opcode(message)
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
