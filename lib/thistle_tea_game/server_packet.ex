defmodule ThistleTeaGame.ServerPacket do
  @callback encode(packet :: struct()) :: %ThistleTeaGame.ServerPacket{}

  defmacro __using__(opts) do
    quote do
      @behaviour ThistleTeaGame.ServerPacket
      @opcode unquote(ThistleTeaGame.Opcodes.get(opts[:opcode]))

      alias ThistleTeaGame.ServerPacket
      alias ThistleTeaGame.Message

      defimpl ThistleTeaGame.ServerPacket.Protocol do
        def encode(packet) do
          unquote(Macro.escape(__CALLER__.module)).encode(packet)
        end

        def opcode(packet) do
          unquote(Macro.escape(__CALLER__.module)).opcode()
        end

        def handle(_packet, _conn), do: nil
      end

      def opcode, do: @opcode
    end
  end

  defstruct [
    :opcode,
    :size,
    :payload
  ]

  def build(payload, opcode) do
    %__MODULE__{
      opcode: opcode,
      size: byte_size(payload) + 2,
      payload: payload
    }
  end
end
