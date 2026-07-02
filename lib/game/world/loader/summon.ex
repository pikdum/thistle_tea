defmodule ThistleTea.Game.World.Loader.Summon do
  @moduledoc """
  ETS cache of fully-loaded creature prototypes for script-driven temporary
  summons, keyed by entry: the first summon of an entry runs the normal mob
  loading pipeline against a synthetic spawn row and caches the result, so
  later summons build without touching the database. Summoned mob guids get
  a session-unique low guid offset far above the seed data's spawn guids.
  """
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]
  @low_guid_base 0x400000

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def build(entry, map, {x, y, z, o}, opts \\ []) when is_integer(entry) and is_list(opts) do
    case template(entry) do
      %Mangos.Creature{} = creature ->
        %{creature | guid: next_low_guid(), map: map, position_x: x, position_y: y, position_z: z, orientation: o}
        |> Mob.build()
        |> Mob.prepare_summon(opts)

      _ ->
        nil
    end
  end

  defp template(entry) do
    case :ets.lookup(__MODULE__, entry) do
      [{^entry, %Mangos.Creature{} = creature}] -> creature
      _ -> load(entry)
    end
  end

  defp load(entry) do
    creature =
      %Mangos.Creature{
        guid: 0,
        id: entry,
        map: 0,
        position_x: 0.0,
        position_y: 0.0,
        position_z: 0.0,
        orientation: 0.0,
        movement_type: 0
      }
      |> MobLoader.load_creature()

    case creature do
      %Mangos.Creature{} -> :ets.insert(__MODULE__, {entry, creature})
      _ -> nil
    end

    creature
  end

  defp next_low_guid do
    @low_guid_base + :erlang.unique_integer([:positive, :monotonic])
  end
end
