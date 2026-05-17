defmodule ThistleTea.Game.World.Loader.ClassSpell do
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.CreatureTemplate
  alias ThistleTea.DB.Mangos.NpcTrainer
  alias ThistleTea.DB.Mangos.NpcTrainerTemplate
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  def trainable_spell_ids(class, level) when is_integer(class) and is_integer(level) do
    class
    |> trainer_spell_ids(level)
    |> SpellLoader.learned_spell_ids()
  end

  def trainable_spell_ids(_class, _level), do: []

  defp trainer_spell_ids(class, level) do
    direct_trainer_spell_ids(class, level)
    |> Enum.concat(template_trainer_spell_ids(class, level))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp direct_trainer_spell_ids(class, level) do
    Mangos.Repo.all(
      from(t in NpcTrainer,
        join: c in CreatureTemplate,
        on: c.entry == t.entry,
        where: c.trainer_class == ^class and t.req_level <= ^level and t.spell > 0,
        select: t.spell,
        distinct: true
      )
    )
  end

  defp template_trainer_spell_ids(class, level) do
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
            where: t.entry in ^template_ids and t.req_level <= ^level and t.spell > 0,
            select: t.spell,
            distinct: true
          )
        )
    end
  end
end
