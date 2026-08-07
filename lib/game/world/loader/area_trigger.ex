defmodule ThistleTea.Game.World.Loader.AreaTrigger do
  @moduledoc """
  ETS-cached area trigger data from vmangos: trigger geometry (highest build
  at or below the supported client), quest involvement, taverns, teleport
  destinations, and instance map metadata. `inside?/4` ports the vmangos
  point-in-trigger check (sphere radius or oriented box).
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.AreaTriggerTeleport
  alias ThistleTea.Game.World.Loader.Condition, as: ConditionLoader
  alias ThistleTea.Game.WorldRef

  @supported_build 5875
  @supported_patch 10

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    Mangos.Repo.all(from(t in Mangos.AreaTriggerTemplate, where: t.build <= @supported_build))
    |> latest_by(& &1.id, & &1.build)
    |> Enum.each(&:ets.insert(__MODULE__, {{:trigger, &1.id}, trigger(&1)}))

    Mangos.Repo.all(Mangos.AreaTriggerInvolvedRelation)
    |> Enum.each(&:ets.insert(__MODULE__, {{:quest, &1.id}, positive(&1.quest)}))

    Mangos.Repo.all(Mangos.AreaTriggerTavern)
    |> Enum.filter(&((&1.patch_min || 0) <= @supported_patch))
    |> Enum.each(&:ets.insert(__MODULE__, {{:tavern, &1.id}, true}))

    teleports =
      Mangos.Repo.all(from(t in Mangos.AreaTriggerTeleport, where: t.patch <= @supported_patch))
      |> latest_by(& &1.id, & &1.patch)

    conditions = teleports |> Enum.map(& &1.required_condition) |> ConditionLoader.load_by_ids()
    Enum.each(teleports, &:ets.insert(__MODULE__, {{:teleport, &1.id}, teleport(&1, conditions)}))

    Mangos.Repo.all(from(m in Mangos.MapTemplate, where: m.patch <= @supported_patch))
    |> latest_by(& &1.entry, & &1.patch)
    |> Enum.filter(&(&1.map_type == 1))
    |> Enum.each(&:ets.insert(__MODULE__, {{:instance_map, &1.entry}, true}))

    :ets.insert(__MODULE__, {:loaded, true})
    :ok
  end

  def get(id) when is_integer(id) and id > 0 do
    lookup({:trigger, id}, fn -> load_trigger(id) end)
  end

  def get(_id), do: nil

  def quest_for(id) when is_integer(id) and id > 0 do
    lookup({:quest, id}, fn -> load_quest(id) end)
  end

  def quest_for(_id), do: nil

  def tavern?(id) when is_integer(id) and id > 0 do
    lookup({:tavern, id}, fn -> load_tavern?(id) end)
  end

  def tavern?(_id), do: false

  def teleport(id) when is_integer(id) and id > 0 do
    lookup({:teleport, id}, fn -> load_teleport(id) end)
  end

  def teleport(_id), do: nil

  def instance_map?(map_id) when is_integer(map_id) and map_id >= 0 do
    lookup({:instance_map, map_id}, fn -> load_instance_map?(map_id) end)
  end

  def instance_map?(_map_id), do: false

  def spawnable_world?(%WorldRef{instance_id: nil, map_id: map_id}) do
    case :ets.lookup(__MODULE__, {:instance_map, map_id}) do
      [{{:instance_map, ^map_id}, true}] -> false
      _unknown_or_open_world -> true
    end
  end

  def spawnable_world?(%WorldRef{}), do: true

  def inside?(trigger, map, position, delta \\ 0.0)

  def inside?(%{map: trigger_map}, map, _position, _delta) when trigger_map != map, do: false

  def inside?(%{radius: radius} = trigger, _map, {x, y, z}, delta) when is_number(radius) and radius > 0 do
    dist_sq = :math.pow(x - trigger.x, 2) + :math.pow(y - trigger.y, 2) + :math.pow(z - trigger.z, 2)
    dist_sq <= :math.pow(radius + delta, 2)
  end

  def inside?(%{} = trigger, _map, {x, y, z}, delta) do
    rotation = 2 * :math.pi() - trigger.box_orientation
    sin = :math.sin(rotation)
    cos = :math.cos(rotation)

    dist_x = x - trigger.x
    dist_y = y - trigger.y

    dx = dist_x * cos - dist_y * sin
    dy = dist_y * cos + dist_x * sin
    dz = z - trigger.z

    abs(dx) <= trigger.box_x / 2 + delta and
      abs(dy) <= trigger.box_y / 2 + delta and
      abs(dz) <= trigger.box_z / 2 + delta
  end

  defp lookup(key, load) do
    case :ets.lookup(__MODULE__, key) do
      [{^key, value}] -> value
      _miss -> if(preloaded?(), do: missing_value(key), else: cache(key, load.()))
    end
  end

  defp preloaded?, do: :ets.lookup(__MODULE__, :loaded) == [{:loaded, true}]
  defp missing_value({kind, _id}) when kind in [:tavern, :instance_map], do: false
  defp missing_value({_kind, _id}), do: nil

  defp cache(key, value) do
    :ets.insert(__MODULE__, {key, value})
    value
  end

  defp load_trigger(id) do
    row =
      Mangos.Repo.one(
        from(t in Mangos.AreaTriggerTemplate,
          where: t.id == ^id and t.build <= @supported_build,
          order_by: [desc: t.build],
          limit: 1
        )
      )

    case row do
      %Mangos.AreaTriggerTemplate{} = t ->
        trigger(t)

      _missing ->
        nil
    end
  end

  defp load_quest(id) do
    case Mangos.Repo.get(Mangos.AreaTriggerInvolvedRelation, id) do
      %Mangos.AreaTriggerInvolvedRelation{quest: quest} when is_integer(quest) and quest > 0 -> quest
      _missing -> nil
    end
  end

  defp load_tavern?(id) do
    case Mangos.Repo.get(Mangos.AreaTriggerTavern, id) do
      %Mangos.AreaTriggerTavern{patch_min: patch_min} -> (patch_min || 0) <= @supported_patch
      _missing -> false
    end
  end

  defp load_teleport(id) do
    row =
      Mangos.Repo.one(
        from(t in Mangos.AreaTriggerTeleport,
          where: t.id == ^id and t.patch <= @supported_patch,
          order_by: [desc: t.patch],
          limit: 1
        )
      )

    case row do
      %Mangos.AreaTriggerTeleport{} = teleport ->
        conditions = ConditionLoader.load_by_ids([teleport.required_condition])
        teleport(teleport, conditions)

      _missing ->
        nil
    end
  end

  defp load_instance_map?(map_id) do
    row =
      Mangos.Repo.one(
        from(m in Mangos.MapTemplate,
          where: m.entry == ^map_id and m.patch <= @supported_patch,
          order_by: [desc: m.patch],
          limit: 1
        )
      )

    match?(%Mangos.MapTemplate{map_type: 1}, row)
  end

  defp trigger(t) do
    %{
      id: t.id,
      map: t.map_id,
      x: t.x,
      y: t.y,
      z: t.z,
      radius: t.radius,
      box_x: t.box_x,
      box_y: t.box_y,
      box_z: t.box_z,
      box_orientation: t.box_orientation
    }
  end

  defp teleport(row, conditions) do
    %AreaTriggerTeleport{
      id: row.id,
      name: row.name,
      message: row.message,
      required_level: row.required_level,
      condition: Map.get(conditions, row.required_condition),
      target_map: row.target_map,
      x: row.target_position_x,
      y: row.target_position_y,
      z: row.target_position_z,
      orientation: row.target_orientation
    }
  end

  defp latest_by(rows, key, version) do
    rows
    |> Enum.group_by(key)
    |> Enum.map(fn {_key, versions} -> Enum.max_by(versions, version) end)
  end

  defp positive(value) when is_integer(value) and value > 0, do: value
  defp positive(_value), do: nil
end
