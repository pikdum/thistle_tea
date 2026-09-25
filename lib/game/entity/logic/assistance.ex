defmodule ThistleTea.Game.Entity.Logic.Assistance do
  @moduledoc "Pure assistance eligibility, retreats toward allies, and fleeing-faction help reactions."

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Distancing
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CreatureMovement
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Math

  @seek_radius 30.0
  @call_radius 10.0
  @delay_ms 1_500
  @unavailable_flags 0x02000000 + 0x00040000 + 0x2
  @no_assist 0x00010000

  def seek_radius, do: @seek_radius
  def call_radius, do: @call_radius
  def delay_ms, do: @delay_ms

  def available?(%Mob{unit: unit, internal: internal} = entity) do
    blackboard = Blackboard.ensure(internal.blackboard)
    flags = if internal.creature, do: internal.creature.extra_flags || 0, else: 0

    available_target?(entity) and not Mob.critter?(entity) and
      ((unit.flags || 0) &&& 0x00020000) == 0 and (flags &&& @no_assist) == 0 and
      not blackboard.navigation.returning_home?
  end

  def available?(_entity), do: false

  defp available_target?(%Mob{unit: unit, internal: internal} = entity) do
    is_number(unit.health) and unit.health > 0 and internal.in_combat != true and
      uncontrolled?(entity) and ((unit.flags || 0) &&& @unavailable_flags) == 0 and
      not Aura.has_aura?(entity, :mod_invisibility)
  end

  def flee_available?(%Mob{internal: internal} = entity) do
    blackboard = Blackboard.ensure(internal.blackboard)

    available_target?(entity) and CreatureMovement.random?(entity) and Distancing.allowed?(entity) and
      not Distancing.active?(entity) and not blackboard.navigation.returning_home? and
      is_nil(blackboard.navigation.distracted_until) and not scripted_movement?(entity)
  end

  def flee_available?(_entity), do: false

  defp scripted_movement?(entity) do
    is_integer(Movement.completion_at(entity)) or
      Enum.any?(entity.internal.navigation_intents, &Keyword.has_key?(&1.opts, :movement_inform))
  end

  def eligible_flee?(
        %{flee_from_help_available?: true, faction_template: %FactionTemplate{} = helper},
        %FactionTemplate{} = caller,
        %FactionTemplate{} = enemy
      ) do
    FactionTemplate.flees_from_call_for_help?(helper) and allied?(helper, caller, :friendly) and
      not FactionTemplate.friendly_to?(helper, enemy)
  end

  def eligible_flee?(_helper, _caller, _enemy), do: false

  def flee_from_help(%Mob{} = entity, caller_guid, enemy_guid, %Context{perception: perception} = context) do
    own = Perception.metadata(perception, entity.object.guid)
    caller = faction(Perception.metadata(perception, caller_guid))
    enemy = faction(Perception.metadata(perception, enemy_guid))

    if flee_available?(entity) and eligible_flee?(own, caller, enemy) and
         same_world?(entity, perception, caller_guid) and close_enemy?(entity, perception, enemy_guid) do
      {entity, _blackboard} =
        Distancing.start(entity, Blackboard.ensure(entity.internal.blackboard), enemy_guid, 10.0, context)

      entity
    else
      entity
    end
  end

  defp same_world?(entity, perception, guid) do
    match?({world, _, _, _} when world == entity.internal.world, Perception.position(perception, guid))
  end

  defp close_enemy?(entity, perception, guid) do
    {x, y, z, _} = entity.movement_block.position

    case Perception.position(perception, guid) do
      {world, tx, ty, tz} when world == entity.internal.world ->
        metadata = Perception.metadata(perception, guid) || %{}
        radius = (entity.unit.bounding_radius || 0) + (Map.get(metadata, :bounding_radius) || 0)
        Math.distance({x, y, z}, {tx, ty, tz}) - radius < 10.0

      _ ->
        false
    end
  end

  def visible_target(%Mob{internal: %{blackboard: %Blackboard{assistance: memory}}}) when not is_nil(memory), do: 0
  def visible_target(%Mob{unit: unit}), do: unit.target

  defp uncontrolled?(%Mob{unit: unit, internal: internal}) do
    is_nil(internal.pet) and is_nil(internal.totem) and unit.summoned_by in [nil, 0] and unit.charmed_by in [nil, 0]
  end

  def eligible?(
        %{assistance_available?: true, faction_template: %FactionTemplate{} = helper},
        %FactionTemplate{} = caller,
        %FactionTemplate{} = enemy,
        faction_check
      ) do
    FactionTemplate.responds_to_call_for_help?(helper) and allied?(helper, caller, faction_check) and
      not FactionTemplate.friendly_to?(helper, enemy)
  end

  def eligible?(_helper, _caller, _enemy, _faction_check), do: false

  def nearest(%Mob{} = entity, %Perception{} = perception) do
    caller = faction(Perception.metadata(perception, entity.object.guid))
    enemy = faction(Perception.metadata(perception, entity.unit.target))

    perception
    |> Perception.nearby(:mobs, @seek_radius)
    |> Enum.sort_by(fn {guid, distance} -> {distance, guid} end)
    |> Enum.find_value(fn {guid, _distance} ->
      if guid != entity.object.guid and eligible?(Perception.metadata(perception, guid), caller, enemy, :same_faction) and
           Perception.line_of_sight?(perception, guid),
         do: helper_position(entity, perception, guid)
    end)
  end

  def faction(%{faction_template: %FactionTemplate{} = faction}), do: faction
  def faction(_metadata), do: nil

  defp helper_position(entity, perception, guid) do
    case Perception.position(perception, guid) do
      {world, x, y, z} when world == entity.internal.world -> {guid, {x, y, z}}
      _ -> nil
    end
  end

  defp allied?(%FactionTemplate{id: id}, %FactionTemplate{id: id}, _check), do: true
  defp allied?(helper, caller, :friendly), do: FactionTemplate.friendly_to?(helper, caller)
  defp allied?(_helper, _caller, _check), do: false
end
