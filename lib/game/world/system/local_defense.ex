defmodule ThistleTea.Game.World.System.LocalDefense do
  @moduledoc """
  Sends LocalDefense "under attack" alerts. Creatures report a fallen
  defender with `alert/3`; this process keeps each area's ten-second
  cooldown (`Core.LocalDefense`) and warns the defending team's players on
  the defender's map.
  """
  use GenServer

  alias ThistleTea.Game.Core.Honor
  alias ThistleTea.Game.Core.LocalDefense
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message.SmsgZoneUnderAttack
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Outbound

  require Logger

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))

  def alert(%WorldRef{} = world, area_id, attacking_team, server \\ __MODULE__) when is_integer(area_id),
    do: GenServer.cast(server, {:alert, world, area_id, attacking_team})

  @impl GenServer
  def init(cooldowns), do: {:ok, cooldowns}

  @impl GenServer
  def handle_cast({:alert, world, area_id, attacking_team}, cooldowns) do
    case LocalDefense.alert(cooldowns, area_id, Time.now()) do
      {:alert, cooldowns} ->
        warn(world, area_id, attacking_team)
        {:noreply, cooldowns}

      {:quiet, cooldowns} ->
        {:noreply, cooldowns}
    end
  rescue
    error ->
      Logger.error("LocalDefense alert failed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, cooldowns}
  end

  defp warn(world, area_id, attacking_team) do
    packet = %SmsgZoneUnderAttack{area_id: area_id}

    world
    |> World.players_in()
    |> Enum.filter(&defending?(&1, attacking_team))
    |> Enum.each(&Outbound.send_packet(packet, &1))
  end

  defp defending?(guid, attacking_team) do
    case Metadata.query(guid, [:race]) do
      %{race: race} -> LocalDefense.defending?(attacking_team, Honor.team(race))
      _offline -> false
    end
  end
end
