defmodule ThistleTea.Game.Core.Item.ItemEligibility do
  @moduledoc """
  Shared item-use requirements for equipment and Need Before Greed. Snapshots
  contain only the owner-provided facts needed to evaluate an item template.
  """
  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Honor.ItemRequirements
  alias ThistleTea.Game.Core.Item.Proficiency

  defstruct [:class, :race, :level, :highest_honor_rank, :proficiency]

  def from_character(%Character{unit: %Unit{} = unit, player: %Player{} = player, internal: %Internal{}} = character) do
    new(unit, Proficiency.from_character(character), player)
  end

  def from_character(_character), do: nil

  def new(%Unit{} = unit, %Proficiency{} = proficiency, %Player{} = player) do
    %__MODULE__{
      class: unit.class,
      race: unit.race,
      level: unit.level,
      highest_honor_rank: player.highest_honor_rank || 0,
      proficiency: proficiency
    }
  end

  def check(%__MODULE__{class: class, race: race, level: level} = eligibility, %ItemTemplate{} = template)
      when is_integer(class) and class > 0 and is_integer(race) and race > 0 and is_integer(level) do
    check_requirements(eligibility, template)
  end

  def check(_eligibility, _template), do: {:error, :item_not_found}

  defp check_requirements(%__MODULE__{class: class, race: race, level: level} = eligibility, template) do
    cond do
      (template.allowable_class &&& 1 <<< (class - 1)) == 0 -> {:error, :you_can_never_use_that_item}
      (template.allowable_race &&& 1 <<< (race - 1)) == 0 -> {:error, :you_can_never_use_that_item}
      not ItemRequirements.can_use?(eligibility.highest_honor_rank, template) -> {:error, :cant_equip_rank}
      is_integer(template.required_level) and level < template.required_level -> {:error, :cant_equip_level_i}
      true -> Proficiency.can_equip?(eligibility.proficiency, template)
    end
  end
end
