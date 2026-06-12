defmodule ThistleTea.Game.World.ChaseWatch do
  @moduledoc """
  ETS index of mobs currently chasing a moving target.
  """
  @table_options [:named_table, :public, :duplicate_bag, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _tid -> table
    end
  end

  def watch(target_guid, chaser_pid, last_position, threshold, table \\ __MODULE__)

  def watch(target_guid, chaser_pid, last_position, threshold, table)
      when is_integer(target_guid) and is_pid(chaser_pid) and is_tuple(last_position) and is_number(threshold) do
    init(table)
    unwatch(chaser_pid, table)
    :ets.insert(table, {target_guid, chaser_pid, last_position, max(threshold, 0.0)})
    :ok
  end

  def watch(_target_guid, chaser_pid, _last_position, _threshold, table) when is_pid(chaser_pid) do
    unwatch(chaser_pid, table)
  end

  def unwatch(chaser_pid, table \\ __MODULE__)

  def unwatch(chaser_pid, table) when is_pid(chaser_pid) do
    init(table)
    :ets.match_delete(table, {:_, chaser_pid, :_, :_})
    :ok
  end

  def unwatch(_chaser_pid, _table), do: :ok

  def notify_moved(target_guid, position, table \\ __MODULE__)

  def notify_moved(target_guid, {_x, _y, _z} = position, table) when is_integer(target_guid) do
    table = init(table)

    table
    |> :ets.lookup(target_guid)
    |> Enum.each(&maybe_notify(table, target_guid, position, &1))

    :ok
  end

  def notify_moved(_target_guid, _position, _table), do: :ok

  defp maybe_notify(table, target_guid, position, {target_guid, chaser_pid, last_position, threshold})
       when is_pid(chaser_pid) and is_number(threshold) do
    cond do
      not Process.alive?(chaser_pid) ->
        :ets.delete_object(table, {target_guid, chaser_pid, last_position, threshold})

      moved_enough?(last_position, position, threshold) ->
        :ets.delete_object(table, {target_guid, chaser_pid, last_position, threshold})
        :ets.insert(table, {target_guid, chaser_pid, position, threshold})
        send(chaser_pid, {:target_moved, target_guid})

      true ->
        :ok
    end
  end

  defp maybe_notify(_table, _target_guid, _position, _entry), do: :ok

  defp moved_enough?({lx, ly, _lz}, {x, y, _z}, threshold) do
    dx = x - lx
    dy = y - ly
    :math.sqrt(dx * dx + dy * dy) > threshold
  end

  defp moved_enough?(_last_position, _position, _threshold), do: true
end
