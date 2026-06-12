defmodule ThistleTea.Game.World.Loader.Trainer do
  @moduledoc """
  Loads the spells a trainer creature teaches from Mangos, resolving each
  teaching spell to the spell it grants plus the rank-chain, level, and
  class/race requirement metadata needed to offer it to a player.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.TrainerSpell
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def trainer_info(creature_entry) do
    case :ets.lookup(__MODULE__, creature_entry) do
      [{^creature_entry, info}] -> info
      _ -> cache(creature_entry, load_trainer_info(creature_entry))
    end
  end

  defp load_trainer_info(creature_entry) do
    template = Mangos.Repo.get(Mangos.CreatureTemplate, creature_entry)

    %{
      trainer_type: trainer_type(template),
      spells: spells(creature_entry, template)
    }
  end

  defp cache(creature_entry, info) do
    :ets.insert(__MODULE__, {creature_entry, info})
    info
  end

  defp trainer_type(%Mangos.CreatureTemplate{trainer_type: type}), do: type || 0
  defp trainer_type(_template), do: 0

  defp spells(_creature_entry, nil), do: []

  defp spells(creature_entry, %Mangos.CreatureTemplate{} = template) do
    rows = trainer_rows(creature_entry, template.trainer_template_id || 0)
    learned_map = SpellLoader.learned_spell_map(Enum.map(rows, & &1.spell))
    learned_ids = learned_map |> Map.values() |> Enum.reject(&is_nil/1)

    level_map = spell_level_map(learned_ids)
    chain_map = chain_map(learned_ids)
    masks_map = class_race_masks_map(learned_ids)

    rows
    |> Enum.map(&build_spell(&1, learned_map, level_map, chain_map, masks_map))
    |> Enum.reject(&is_nil(&1.learned_spell_id))
  end

  defp build_spell(row, learned_map, level_map, chain_map, masks_map) do
    learned_id = Map.get(learned_map, row.spell)
    chain = Map.get(chain_map, learned_id)

    %TrainerSpell{
      teach_spell_id: row.spell,
      learned_spell_id: learned_id,
      cost: row.spell_cost || 0,
      req_level: req_level(row, learned_id, level_map),
      req_skill: row.req_skill || 0,
      req_skill_value: row.req_skill_value || 0,
      prev_spell_id: chain && nonzero(chain.prev_spell),
      req_spell_id: chain && nonzero(chain.req_spell),
      class_race_masks: Map.get(masks_map, learned_id, [])
    }
  end

  defp trainer_rows(creature_entry, trainer_template_id) do
    direct =
      Mangos.Repo.all(from(t in Mangos.NpcTrainer, where: t.entry == ^creature_entry and t.spell > 0))

    template =
      case trainer_template_id do
        id when is_integer(id) and id > 0 ->
          Mangos.Repo.all(from(t in Mangos.NpcTrainerTemplate, where: t.entry == ^id and t.spell > 0))

        _ ->
          []
      end

    (direct ++ template)
    |> Enum.uniq_by(& &1.spell)
    |> Enum.sort_by(& &1.spell)
  end

  defp req_level(row, learned_id, level_map) do
    case row.req_level do
      level when is_integer(level) and level > 0 -> level
      _ -> Map.get(level_map, learned_id, 0)
    end
  end

  defp spell_level_map([]), do: %{}

  defp spell_level_map(learned_ids) do
    DBC.all(from(s in Spell, where: s.id in ^learned_ids, select: {s.id, s.spell_level}))
    |> Map.new(fn {id, level} -> {id, level || 0} end)
  end

  defp chain_map([]), do: %{}

  defp chain_map(learned_ids) do
    learned_ids
    |> Enum.map(&{&1, SpellLoader.chain(&1)})
    |> Enum.reject(fn {_id, chain} -> is_nil(chain) end)
    |> Map.new()
  end

  defp class_race_masks_map([]), do: %{}

  defp class_race_masks_map(learned_ids) do
    DBC.all(
      from(sla in SkillLineAbility,
        where: sla.spell in ^learned_ids,
        select: {sla.spell, sla.class_mask, sla.race_mask}
      )
    )
    |> Enum.group_by(
      fn {spell_id, _class_mask, _race_mask} -> spell_id end,
      fn {_spell_id, class_mask, race_mask} -> {class_mask || 0, race_mask || 0} end
    )
  end

  defp nonzero(value) when is_integer(value) and value > 0, do: value
  defp nonzero(_value), do: nil
end
