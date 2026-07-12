defmodule ThistleTea.Game.World.Loader.ClassSpell do
  @moduledoc """
  Looks up trainable class spells by class and level from the DBC, plus the
  non-passive rank-1 talent spells of the class's talent tabs so the debug
  learn command can grant abilities no trainer teaches.
  """
  import Bitwise, only: [<<<: 2, &&&: 2]
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.CreatureTemplate
  alias ThistleTea.DB.Mangos.NpcTrainer
  alias ThistleTea.DB.Mangos.NpcTrainerTemplate
  alias ThistleTea.DBC
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @spell_attr_passive 0x40

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  @warrior 1
  @warlock 9
  @defensive_stance {71, 10}
  @berserker_stance {2458, 30}
  @quest_reward_spells %{
    @warrior => [@defensive_stance, @berserker_stance],
    @warlock => [{688, 1}, {697, 10}, {712, 20}, {691, 30}, {1122, 50}, {18_540, 60}]
  }

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def trainable_spell_ids(class, level) when is_integer(class) and is_integer(level) do
    class
    |> class_spells()
    |> Kernel.++(Map.get(@quest_reward_spells, class, []))
    |> Enum.filter(fn {_spell, req_level} -> is_integer(req_level) and req_level <= level end)
    |> Enum.map(fn {spell, _req_level} -> spell end)
    |> Enum.uniq()
    |> Enum.sort()
    |> SpellLoader.learned_spell_ids()
  end

  def trainable_spell_ids(_class, _level), do: []

  defp class_spells(class) do
    case :ets.lookup(__MODULE__, class) do
      [{^class, spells}] -> spells
      _ -> cache(class, direct_trainer_spells(class) ++ template_trainer_spells(class) ++ talent_spells(class))
    end
  end

  defp talent_spells(class) do
    class_mask = 1 <<< (class - 1)

    rank_one_ids =
      DBC.all(
        from(t in Talent,
          join: tab in TalentTab,
          on: t.tab == tab.id,
          where: tab.class_mask == ^class_mask and t.spell_rank_0 > 0,
          select: t.spell_rank_0
        )
      )

    case rank_one_ids do
      [] ->
        []

      ids ->
        DBC.all(
          from(s in Spell,
            where: s.id in ^ids,
            select: {s.id, s.attributes, s.base_level}
          )
        )
        |> Enum.reject(fn {_id, attributes, _level} -> ((attributes || 0) &&& @spell_attr_passive) != 0 end)
        |> Enum.map(fn {id, _attributes, base_level} -> {id, max(base_level || 1, 1)} end)
    end
  end

  defp cache(class, spells) do
    :ets.insert(__MODULE__, {class, spells})
    spells
  end

  defp direct_trainer_spells(class) do
    Mangos.Repo.all(
      from(t in NpcTrainer,
        join: c in CreatureTemplate,
        on: c.entry == t.entry,
        where: c.trainer_class == ^class and t.spell > 0,
        select: {t.spell, t.req_level},
        distinct: true
      )
    )
  end

  defp template_trainer_spells(class) do
    template_ids =
      Mangos.Repo.all(
        from(c in CreatureTemplate,
          where: c.trainer_class == ^class and c.trainer_template_id > 0,
          select: c.trainer_template_id,
          distinct: true
        )
      )

    case template_ids do
      [] ->
        []

      _ ->
        Mangos.Repo.all(
          from(t in NpcTrainerTemplate,
            where: t.entry in ^template_ids and t.spell > 0,
            select: {t.spell, t.req_level},
            distinct: true
          )
        )
    end
  end
end
