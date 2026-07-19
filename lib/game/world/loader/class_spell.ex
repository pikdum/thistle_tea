defmodule ThistleTea.Game.World.Loader.ClassSpell do
  @moduledoc """
  Looks up trainable class spells by class and level from trainer data and
  class quest rewards so the debug learn command can grant them. Trained
  talent ranks require an already known spell from the same talent family.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.CreatureTemplate
  alias ThistleTea.DB.Mangos.NpcTrainer
  alias ThistleTea.DB.Mangos.NpcTrainerTemplate
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain, as: SpellChainLoader
  alias ThistleTea.Game.World.Loader.Talent, as: TalentLoader

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  @warrior 1
  @hunter 3
  @shaman 7
  @warlock 9
  @druid 11
  @defensive_stance {71, 10}
  @berserker_stance {2458, 30}
  @quest_reward_spells %{
    @warrior => [@defensive_stance, @berserker_stance],
    @hunter => [{1515, 10}, {883, 10}, {2641, 10}, {6991, 10}, {982, 10}, {136, 12}],
    @shaman => [{8071, 4}, {3599, 10}, {5394, 20}, {8512, 30}],
    @warlock => [{688, 1}, {697, 10}, {712, 20}, {691, 30}, {1122, 50}, {18_540, 60}],
    @druid => [{5487, 10}, {1066, 16}, {768, 20}]
  }

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def trainable_spell_ids(class, level), do: trainable_spell_ids(class, level, [])

  def trainable_spell_ids(class, level, known_spell_ids)
      when is_integer(class) and is_integer(level) and is_list(known_spell_ids) do
    class
    |> class_spells()
    |> Kernel.++(Map.get(@quest_reward_spells, class, []))
    |> Enum.filter(fn {_spell, req_level} -> is_integer(req_level) and req_level <= level end)
    |> Enum.map(fn {spell, _req_level} -> spell end)
    |> Enum.uniq()
    |> Enum.sort()
    |> SpellLoader.learned_spell_ids()
    |> grantable_spell_ids(known_spell_ids)
  end

  def trainable_spell_ids(_class, _level, _known_spell_ids), do: []

  def grantable_spell_ids(spell_ids, known_spell_ids) when is_list(spell_ids) and is_list(known_spell_ids) do
    SpellChainLoader.get_many(spell_ids ++ known_spell_ids)

    known_talent_ids =
      known_spell_ids
      |> Enum.flat_map(fn spell_id ->
        case TalentLoader.by_spell(spell_id) do
          {talent_id, _tab_id, _rank_index} -> [talent_id]
          _not_talent -> []
        end
      end)
      |> MapSet.new()

    Enum.filter(spell_ids, fn spell_id ->
      case TalentLoader.by_spell(spell_id) do
        {talent_id, _tab_id, _rank_index} -> MapSet.member?(known_talent_ids, talent_id)
        _not_talent -> true
      end
    end)
  end

  def grantable_spell_ids(_spell_ids, _known_spell_ids), do: []

  defp class_spells(class) do
    case :ets.lookup(__MODULE__, class) do
      [{^class, spells}] -> spells
      _ -> cache(class, direct_trainer_spells(class) ++ template_trainer_spells(class))
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
