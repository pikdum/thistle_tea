defmodule ThistleTea.Game.World.Loader.CreatureTemplate do
  @moduledoc """
  ETS cache of slim creature-template query info, preloaded at boot so
  gameplay queries answer from running state instead of the Mangos seed.
  """
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.Creature.CreatureFlags
  alias ThistleTea.Game.Core.Entity.CreatureTemplate

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    Mangos.CreatureTemplate
    |> Mangos.Repo.all()
    |> Enum.each(&cache/1)
  end

  def get(entry) when is_integer(entry) and entry > 0 do
    case :ets.lookup(__MODULE__, entry) do
      [{^entry, %CreatureTemplate{} = template}] -> template
      _ -> load(entry)
    end
  end

  def get(_entry), do: nil

  defp load(entry) do
    case Mangos.Repo.get(Mangos.CreatureTemplate, entry) do
      %Mangos.CreatureTemplate{} = row -> cache(row)
      _ -> nil
    end
  end

  defp cache(%Mangos.CreatureTemplate{} = row) do
    template = build(row)
    :ets.insert(__MODULE__, {template.entry, template})
    template
  end

  defp build(%Mangos.CreatureTemplate{} = ct) do
    %CreatureTemplate{
      entry: ct.entry,
      name: ct.name,
      sub_name: ct.sub_name,
      type_flags: CreatureFlags.type_flags(ct.creature_type_flags, ct.static_flags2),
      creature_type: ct.creature_type,
      family: ct.family,
      rank: ct.rank,
      display_id: ct.model_id1,
      display_ids: [ct.model_id1, ct.model_id2, ct.model_id3, ct.model_id4],
      display_scales: [ct.display_scale1, ct.display_scale2, ct.display_scale3, ct.display_scale4],
      equipment_id: ct.equipment_template_id,
      civilian: ct.civilian,
      racial_leader: ct.racial_leader
    }
  end
end
