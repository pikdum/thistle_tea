defmodule ThistleTea.Game.World.AggroProbe do
  @moduledoc """
  Movement-triggered aggro probes for nearby idle mobs.
  """
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.SpatialHash

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]
  @movement_threshold 2.0

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _tid -> table
    end
  end

  def notify_player_moved(player_guid, map, position, table \\ __MODULE__)

  def notify_player_moved(player_guid, map, {x, y, z} = position, table) when is_integer(player_guid) do
    table = init(table)

    if should_probe?(table, player_guid, map, position) do
      :ets.insert(table, {player_guid, {map, position}})
      probe_nearby_mobs(player_guid, map, {x, y, z})
    end

    :ok
  end

  def notify_player_moved(_player_guid, _map, _position, _table), do: :ok

  def forget(player_guid, table \\ __MODULE__) when is_integer(player_guid) do
    init(table)
    :ets.delete(table, player_guid)
    :ok
  end

  defp should_probe?(table, player_guid, map, position) do
    case :ets.lookup(table, player_guid) do
      [{^player_guid, {^map, last_position}}] -> moved_enough?(last_position, position)
      [{^player_guid, {_last_map, _last_position}}] -> true
      [] -> true
    end
  end

  defp moved_enough?({lx, ly, _lz}, {x, y, _z}) do
    SpatialHash.distance({lx, ly, 0.0}, {x, y, 0.0}) >= @movement_threshold
  end

  defp moved_enough?(_last_position, _position), do: true

  defp probe_nearby_mobs(player_guid, map, position) do
    map
    |> World.nearby_mobs_at(position, MobBT.max_aggro_radius())
    |> Enum.each(fn {mob_guid, _distance} -> Entity.aggro_probe(mob_guid, player_guid) end)
  end
end
