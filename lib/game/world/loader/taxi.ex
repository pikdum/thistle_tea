defmodule ThistleTea.Game.World.Loader.Taxi do
  @moduledoc """
  Preloads VMangos flight-master nodes and route transitions together with
  the client DBC taxi graph into one immutable runtime network.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Taxi.Network
  alias ThistleTea.Game.Entity.Data.Taxi.Node
  alias ThistleTea.Game.Entity.Data.Taxi.Path
  alias ThistleTea.Game.Entity.Data.Taxi.PathNode

  @client_build 5875
  @send_taxi_effect 123
  @table_options [:named_table, :public, read_concurrency: true]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    network =
      Network.build(
        load_nodes(),
        load_paths(),
        load_transitions(),
        load_spell_path_ids()
      )

    :ets.insert(__MODULE__, {:network, network})
    network
  end

  def get do
    case :ets.lookup(__MODULE__, :network) do
      [{:network, %Network{} = network}] -> network
      _missing -> nil
    end
  end

  def load_nodes do
    latest_builds =
      from(node in Mangos.TaxiNode,
        where: node.build <= @client_build,
        group_by: node.id,
        select: %{id: node.id, build: max(node.build)}
      )

    rows =
      Mangos.TaxiNode
      |> join(:inner, [node], latest in subquery(latest_builds),
        on: latest.id == node.id and latest.build == node.build
      )
      |> Mangos.Repo.all()

    display_ids =
      rows
      |> Enum.flat_map(&[&1.mount_creature_id1, &1.mount_creature_id2])
      |> Enum.reject(&(&1 in [nil, 0]))
      |> load_mount_display_ids()

    Enum.map(rows, fn row ->
      %Node{
        id: row.id,
        map_id: row.map_id,
        position: {row.x, row.y, row.z},
        name: row.name,
        mount_display_ids: %{
          horde: Map.get(display_ids, row.mount_creature_id1, 0),
          alliance: Map.get(display_ids, row.mount_creature_id2, 0)
        }
      }
    end)
  end

  def load_paths do
    nodes_by_path =
      TaxiPathNode
      |> order_by([node], [node.taxi_path, node.node_index])
      |> ThistleTea.DBC.all()
      |> Enum.group_by(& &1.taxi_path)

    TaxiPath
    |> ThistleTea.DBC.all()
    |> Enum.map(fn row ->
      nodes =
        nodes_by_path
        |> Map.get(row.id, [])
        |> Enum.map(fn node ->
          %PathNode{
            index: node.node_index,
            map_id: node.map,
            position: {node.location_x, node.location_y, node.location_z},
            flags: node.flags,
            delay_ms: node.delay
          }
        end)

      %Path{
        id: row.id,
        source_node_id: row.source_taxi_node,
        destination_node_id: row.destination_taxi_node,
        cost: row.cost,
        nodes: nodes
      }
    end)
  end

  def load_transitions do
    Mangos.TaxiPathTransition
    |> where([transition], transition.build_min <= @client_build)
    |> Mangos.Repo.all()
    |> Map.new(&{{&1.in_path, &1.out_path}, {&1.in_node, &1.out_node}})
  end

  def load_spell_path_ids do
    from(spell in Spell,
      where:
        spell.effect_0 == @send_taxi_effect or spell.effect_1 == @send_taxi_effect or
          spell.effect_2 == @send_taxi_effect,
      select:
        {spell.effect_0, spell.effect_misc_value_0, spell.effect_1, spell.effect_misc_value_1, spell.effect_2,
         spell.effect_misc_value_2}
    )
    |> ThistleTea.DBC.all()
    |> Enum.flat_map(fn row ->
      row
      |> Tuple.to_list()
      |> Enum.chunk_every(2)
      |> Enum.flat_map(fn
        [@send_taxi_effect, path_id] when path_id > 0 -> [path_id]
        _other -> []
      end)
    end)
    |> Enum.uniq()
  end

  defp load_mount_display_ids([]), do: %{}

  defp load_mount_display_ids(entries) do
    from(template in Mangos.CreatureTemplate, where: template.entry in ^Enum.uniq(entries))
    |> Mangos.Repo.all()
    |> Map.new(fn template ->
      display_id =
        Enum.find(
          [template.model_id1, template.model_id2, template.model_id3, template.model_id4],
          0,
          &(&1 > 0)
        )

      {template.entry, display_id}
    end)
  end
end
