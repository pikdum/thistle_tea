defmodule ThistleTeaGame.ClientPacket do
  @callback decode(packet :: %ThistleTeaGame.ClientPacket{}) :: any()
  @callback handle(packet :: struct(), conn :: struct()) :: any()

  @registry_key :thistle_tea_client_packet_registry

  defmacro __using__(opts) do
    quote do
      @behaviour ThistleTeaGame.ClientPacket
      @opcode unquote(ThistleTeaGame.Opcodes.get(opts[:opcode]))

      alias ThistleTeaGame.ClientPacket
      alias ThistleTeaGame.Connection
      alias ThistleTeaGame.Effect
      alias ThistleTeaGame.ServerPacket

      defimpl ThistleTeaGame.Packet do
        def handle(packet, conn),
          do: unquote(Macro.escape(__CALLER__.module)).handle(packet, conn)

        def encode(_packet), do: nil
      end

      def opcode, do: @opcode

      @on_load :__register__
      def __register__ do
        ThistleTeaGame.ClientPacket.register_module(__MODULE__, @opcode)
        :ok
      end
    end
  end

  defstruct [
    :opcode,
    :size,
    :payload
  ]

  def register_module(module, opcode) do
    registry = Application.get_env(:thistle_tea_game, @registry_key, %{})
    Application.put_env(:thistle_tea_game, @registry_key, Map.put(registry, opcode, module))
  end

  def decode(%__MODULE__{opcode: opcode} = packet) do
    registry = Application.get_env(:thistle_tea_game, @registry_key, %{})

    case Map.fetch(registry, opcode) do
      {:ok, mod} -> mod.decode(packet)
      :error -> {:error, :unknown_opcode, opcode}
    end
  end
end
