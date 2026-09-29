defmodule ThistleTea.Game.Core.AI.BT.Acquisition do
  @moduledoc "Selects proximity targets from the same immutable observations for pets and ordinary creatures."

  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Detection
  alias ThistleTea.Game.Core.AI.BT.Pet.Targeting
  alias ThistleTea.Game.Core.Combat.Aggro
  alias ThistleTea.Game.Core.Combat.CombatControl
  alias ThistleTea.Game.Core.Combat.Hostility
  alias ThistleTea.Game.Core.Creature.CreatureMovement
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob

  @vertical_range 3.0

  def nearest(%Mob{} = entity, %Context{perception: perception} = context) do
    source = Perception.actor(perception, entity.object.guid)
    radius = Aggro.search_radius(entity)

    if radius > 0 and Mob.proximity_aggro?(entity) and Hostility.can_initiate_attack?(source) and
         not CombatControl.auto_attack_blocked?(entity) do
      (Perception.nearby(perception, :players, radius) ++ Perception.nearby(perception, :mobs, radius))
      |> Enum.sort_by(fn {guid, distance} -> {distance, guid} end)
      |> Enum.find_value(fn {guid, distance} ->
        eligible?(entity, source, guid, distance, context) && guid
      end)
    end
  end

  def radius(%Mob{} = entity, guid, %Perception{} = perception) do
    Aggro.radius(entity, Perception.aggro_level(perception, guid))
  end

  defp eligible?(entity, source, guid, distance, %Context{perception: perception} = context) do
    target = Perception.actor(perception, guid)

    Hostility.valid_hostile_target?(source, target) and
      distance <= radius(entity, guid, perception) and
      civilian_allowed?(entity, target) and
      Targeting.proximity_allowed?(entity, guid, context) and
      vertically_accessible?(entity, guid, perception) and
      CreatureMovement.accessible?(entity, Perception.swimmable?(perception, guid)) and
      Detection.detectable?(entity, guid, context) and
      Perception.line_of_sight?(perception, guid)
  end

  defp civilian_allowed?(%Mob{internal: %{pet: %Pet{}}}, %{civilian?: true}), do: false
  defp civilian_allowed?(_entity, _target), do: true

  defp vertically_accessible?(%Mob{movement_block: %{position: {_x, _y, z, _orientation}}} = entity, guid, perception) do
    case Perception.position(perception, guid) do
      {_world, _tx, _ty, target_z} ->
        target = Perception.metadata(perception, guid) || %{}
        margin = bounding_radius(entity.unit.bounding_radius) + bounding_radius(Map.get(target, :bounding_radius))
        CreatureMovement.can_fly?(entity) or abs(target_z - z) <= @vertical_range + margin

      _ ->
        false
    end
  end

  defp bounding_radius(radius) when is_number(radius), do: max(radius, 0.0)
  defp bounding_radius(_radius), do: Unit.default_bounding_radius()
end
