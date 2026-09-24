defmodule ThistleTea.Game.World.Loader.CreatureArchetype do
  @moduledoc "Loads weighted level and display choices for in-place creature entry changes."

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.CreatureArchetype
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.World.Loader.Mob.Batch

  @tables ~w(creature_ai_scripts creature_movement_scripts generic_scripts quest_start_scripts quest_end_scripts
    gossip_scripts spell_scripts event_scripts gameobject_scripts areatrigger_scripts creature_spells_scripts)
  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init do
    case :ets.whereis(__MODULE__) do
      :undefined -> :ets.new(__MODULE__, @table_options)
      table -> table
    end
  end

  def load_all do
    entries =
      Enum.flat_map(@tables, fn table ->
        Mangos.Repo.all(
          from(step in table, where: field(step, :command) == 27, distinct: true, select: field(step, :datalong))
        )
      end)

    :ets.insert(__MODULE__, entries |> Enum.uniq() |> load() |> Map.to_list())
    :ok
  end

  def get_many(entries) do
    entries |> Enum.uniq() |> Enum.flat_map(&:ets.lookup(__MODULE__, &1)) |> Map.new()
  end

  def load([]), do: %{}

  def load(entries) when is_list(entries) do
    variants =
      Mangos.Repo.all(from(template in Mangos.CreatureTemplate, where: template.entry in ^entries))
      |> Enum.flat_map(&variants/1)
      |> Enum.with_index(1)
      |> Enum.map(fn {{weight, creature}, index} -> {weight, %{creature | guid: -index}} end)

    weights = Map.new(variants, fn {weight, creature} -> {creature.guid, weight} end)

    variants
    |> Enum.map(&elem(&1, 1))
    |> Batch.load_definitions()
    |> Enum.group_by(& &1.id, fn creature ->
      template = creature |> Mob.build(apply_addon_auras?: false) |> CreatureArchetype.from_mob()
      {Map.fetch!(weights, creature.guid), template}
    end)
  end

  defp variants(%Mangos.CreatureTemplate{} = template) do
    displays = displays(template)
    weighted? = Enum.any?(displays, fn {_display, _scale, weight} -> weight > 0 end)

    for level <- template.min_level..template.max_level,
        {display, scale, weight} <- displays,
        not weighted? or weight > 0 do
      creature = %Mangos.Creature{
        id: template.entry,
        creature_template: template,
        creature_movement: [],
        selected_level: level,
        modelid: display,
        display_scale: scale
      }

      {if(weighted?, do: weight, else: 1), creature}
    end
  end

  defp displays(template) do
    [
      {template.model_id1, template.display_scale1, template.display_probability1 || 0},
      {template.model_id2, template.display_scale2, template.display_probability2 || 0},
      {template.model_id3, template.display_scale3, template.display_probability3 || 0},
      {template.model_id4, template.display_scale4, template.display_probability4 || 0}
    ]
    |> Enum.filter(fn {display, _scale, _weight} -> is_integer(display) and display > 0 end)
  end
end
