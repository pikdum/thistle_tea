defmodule ThistleTeaGame.ClientPacket do
  @callback decode(packet :: %ThistleTeaGame.ClientPacket{}) :: any()
  @callback handle(packet :: struct(), conn :: struct()) :: any()

  @lookup %{
    :CMSG_AUTH_SESSION => ThistleTeaGame.ClientPacket.CmsgAuthSession,
    :CMSG_CHAR_ENUM => ThistleTeaGame.ClientPacket.CmsgCharEnum
  }

  @raw_lookup @lookup
              |> Enum.map(fn {k, v} -> {ThistleTeaGame.Opcodes.get(k), v} end)
              |> Map.new()

  defmacro __using__(opts) do
    quote do
      @behaviour ThistleTeaGame.ClientPacket
      @opcode unquote(ThistleTeaGame.Opcodes.get(opts[:opcode]))

      alias ThistleTeaGame.ClientPacket
      alias ThistleTeaGame.Connection
      alias ThistleTeaGame.Effect
      alias ThistleTeaGame.ServerPacket

      defimpl ThistleTeaGame.Packet do
        def handle(packet, conn) do
          unquote(Macro.escape(__CALLER__.module)).handle(packet, conn)
        end

        def opcode(packet) do
          unquote(Macro.escape(__CALLER__.module)).opcode()
        end

        def encode(_packet), do: nil
      end

      def opcode, do: @opcode
    end
  end

  defstruct [
    :opcode,
    :size,
    :payload
  ]

  def decode(%__MODULE__{opcode: opcode} = packet) do
    case Map.fetch(@raw_lookup, opcode) do
      {:ok, mod} -> mod.decode(packet)
      :error -> {:error, :unhandled_opcode, opcode}
    end
  end
end
