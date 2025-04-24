defmodule ThistleTeaGame.ClientPacket do
  alias ThistleTeaGame.Opcodes

  @callback decode(packet :: %ThistleTeaGame.ClientPacket{}) :: any()
  @callback handle(packet :: struct(), conn :: struct()) :: any()

  # TODO: does it make sense to unify client/server packet structs?
  # to handle MSG_* where it's both client and server?
  # then maybe i could have `use ServerPacket`, `use ClientPacket`, in the same thing
  # and a behavior + protocol for each too?
  @lookup Opcodes.opcodes()
          |> Enum.map(fn {opcode, name} ->
            {opcode, Module.concat("ThistleTeaGame.Message", Opcodes.module_name(name))}
          end)
          |> Map.new()

  defmacro __using__(opts) do
    quote do
      @behaviour ThistleTeaGame.ClientPacket
      @opcode unquote(ThistleTeaGame.Opcodes.get(opts[:opcode]))

      alias ThistleTeaGame.ClientPacket
      alias ThistleTeaGame.Connection
      alias ThistleTeaGame.Effect
      alias ThistleTeaGame.Message

      defimpl ThistleTeaGame.ClientPacket.Protocol do
        def handle(packet, conn) do
          unquote(Macro.escape(__CALLER__.module)).handle(packet, conn)
        end

        def opcode(packet) do
          unquote(Macro.escape(__CALLER__.module)).opcode()
        end
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
    with {:ok, mod} <- Map.fetch(@lookup, opcode),
         {:module, ^mod} <- Code.ensure_loaded(mod) do
      mod.decode(packet)
    else
      {:error, _} ->
        {:error, :unhandled_opcode, opcode}
    end
  end
end
