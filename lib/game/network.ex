defmodule ThistleTea.Game.Network do
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry

  def send_packet(packet, target \\ self())

  def send_packet(packets, target) when is_list(packets) do
    Enum.reduce_while(packets, :ok, fn packet, _acc ->
      case send_packet(packet, target) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  def send_packet(packet, pid) when is_pid(pid) do
    GenServer.cast(pid, {:send_packet, packet})
  end

  def send_packet(packet, guid) when is_integer(guid) do
    case EntityRegistry.whereis(guid) do
      pid when is_pid(pid) -> GenServer.cast(pid, {:send_packet, packet})
      _ -> {:error, :not_found}
    end
  end

  def send_packet(_packet, _target), do: {:error, :invalid_target}
end
