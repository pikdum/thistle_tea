defmodule ThistleTea.Game.Network do
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry

  def send_packet(packet, target \\ self(), opts \\ [])

  def send_packet(packets, target, opts) when is_list(packets) do
    Enum.reduce_while(packets, :ok, fn packet, _acc ->
      case send_packet(packet, target, opts) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  def send_packet(packet, pid, opts) when is_pid(pid) do
    GenServer.cast(pid, send_packet_message(packet, opts))
  end

  def send_packet(packet, guid, opts) when is_integer(guid) do
    case EntityRegistry.whereis(guid) do
      pid when is_pid(pid) -> GenServer.cast(pid, send_packet_message(packet, opts))
      _ -> {:error, :not_found}
    end
  end

  def send_packet(_packet, _target, _opts), do: {:error, :invalid_target}

  defp send_packet_message(packet, []), do: {:send_packet, packet}
  defp send_packet_message(packet, opts), do: {:send_packet, packet, opts}
end
