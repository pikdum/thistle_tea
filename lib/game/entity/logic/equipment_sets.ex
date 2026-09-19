defmodule ThistleTea.Game.Entity.Logic.EquipmentSets do
  @moduledoc """
  Derives set bonus sources from equipped templates, including broken pieces.
  Each set grants each eligible spell once, independently of other sources.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.ItemSet
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Skills

  def sources(%Character{} = character, templates, get_set) do
    counts = Enum.frequencies_by(templates, fn %ItemTemplate{item_set: id} -> id end)

    for {id, count} <- Enum.sort(counts),
        id > 0,
        %ItemSet{} = set <- [get_set.(id)],
        qualified?(character, set),
        {required, spell_id} <- set.bonuses,
        count >= required,
        uniq: true,
        do: {:item_set, id, spell_id}
  end

  defp qualified?(_character, %ItemSet{required_skill: 0}), do: true

  defp qualified?(%Character{player: player} = character, %ItemSet{} = set) do
    {temporary, permanent} = Map.get(Skills.bonuses(character), set.required_skill, {0, 0})

    Skills.known?(player.skills, set.required_skill) and
      Skills.value(player.skills, set.required_skill) + temporary + permanent >= set.required_skill_rank
  end
end
