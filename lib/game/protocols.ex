defprotocol ThistleTea.Game.Message do
  def to_binary(message)
  def to_packet(message)
end

defprotocol ThistleTea.Game.Handler do
  def handle(message, state)
end

defmodule ThistleTea.Game.ClientMessage do
  @callback opcode() :: integer()
  @callback handle(message :: struct(), state :: map()) :: map()
  defmacro __using__(opcode) do
    opcode = ThistleTea.Opcodes.get(opcode)

    quote do
      @behaviour ThistleTea.Game.ClientMessage

      alias ThistleTea.Game.ClientMessage
      alias ThistleTea.Game.Connection
      alias ThistleTea.Game.Handler
      alias ThistleTea.Game.Message
      alias ThistleTea.Util

      @impl ClientMessage
      def opcode, do: unquote(opcode)

      defimpl Handler do
        def handle(message, state) do
          unquote(Macro.escape(__CALLER__.module)).handle(message, state)
        end

        def opcode, do: unquote(opcode)
      end
    end
  end
end

defmodule ThistleTea.Game.ServerMessage do
  alias ThistleTea.Game.Packet

  @callback opcode() :: integer()
  @callback to_binary(message :: struct()) :: binary()
  @callback to_packet(message :: struct()) :: Packet.t()
  defmacro __using__(opcode) do
    opcode = ThistleTea.Opcodes.get(opcode)

    quote do
      @behaviour ThistleTea.Game.ServerMessage

      alias ThistleTea.Game.Message
      alias ThistleTea.Game.Packet
      alias ThistleTea.Game.ServerMessage
      alias ThistleTea.Util

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

        def opcode, do: unquote(opcode)
      end
    end
  end
end
