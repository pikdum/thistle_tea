defmodule ThistleTea.Game.World.AreaTriggerCooldown do
  @moduledoc """
  vmangos `Map::m_areaTriggerCooldowns`: a scripted area trigger with a
  cooldown runs its script for the first player through and then rests for
  that long, for everyone in the same copy of the map. Claiming is a single
  atomic table write, so two players stepping in together cannot both win.
  """

  alias ThistleTea.Game.Core.WorldRef

  @table_options [:named_table, :public, write_concurrency: true]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def claim(world, trigger, now, table \\ __MODULE__)

  def claim(%WorldRef{map_id: map_id, instance_id: instance_id}, %{id: id, cooldown_ms: cooldown_ms}, now, table)
      when is_integer(cooldown_ms) and cooldown_ms > 0 and is_integer(now) do
    key = {map_id, instance_id, id}
    ready_at = now + cooldown_ms

    :ets.insert_new(table, {key, ready_at}) or
      :ets.select_replace(table, [{{key, :"$1"}, [{:"=<", :"$1", now}], [{{{:const, key}, ready_at}}]}]) == 1
  end

  def claim(_world, _trigger, _now, _table), do: true
end
