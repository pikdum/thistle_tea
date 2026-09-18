defmodule ThistleTea.Game.Entity.Logic.CreatureType do
  @moduledoc """
  Creature-type masks for combat bonuses, including player shapeshift forms.
  """
  import Bitwise, only: [<<<: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature

  def mask(%Character{} = character), do: type_mask(Character.creature_type(character))
  def mask(%{internal: %Internal{creature: %Creature{creature_type: type}}}), do: type_mask(type)
  def mask(%{creature_type: type}), do: type_mask(type)
  def mask(_entity), do: type_mask(7)

  defp type_mask(type) when is_integer(type) and type > 0, do: 1 <<< (type - 1)
  defp type_mask(_type), do: 0
end
