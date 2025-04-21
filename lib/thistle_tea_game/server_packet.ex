defmodule ThistleTeaGame.ServerPacket do
  @callback encode(packet :: struct()) :: %ThistleTeaGame.ServerPacket{}

  defmacro __using__(opts) do
    quote do
      @behaviour ThistleTeaGame.ServerPacket
      @opcode unquote(opts[:opcode])

      alias ThistleTeaGame.ServerPacket

      defimpl ThistleTeaGame.Packet do
        def handle(_packet, _conn), do: nil
        def encode(packet), do: unquote(Macro.escape(__CALLER__.module)).encode(packet)
      end

      def opcode, do: @opcode
    end
  end

  defstruct [
    :opcode,
    :size,
    :payload
  ]
end
