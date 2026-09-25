defmodule ThistleTea.Game.Entity.Logic.Assistance do
  @moduledoc "Pure helper eligibility shared by assistance calls and retreats toward nearby allies."

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.Aura

  @seek_radius 30.0
  @call_radius 10.0
  @delay_ms 1_500
  @unavailable_flags 0x02000000 + 0x00040000 + 0x00020000 + 0x2
  @no_assist 0x00010000

  def seek_radius, do: @seek_radius
  def call_radius, do: @call_radius
  def delay_ms, do: @delay_ms

  def available?(%Mob{unit: unit, internal: internal} = entity) do
    blackboard = Blackboard.ensure(internal.blackboard)
    flags = if internal.creature, do: internal.creature.extra_flags || 0, else: 0

    idle_creature?(entity) and
      ((unit.flags || 0) &&& @unavailable_flags) == 0 and (flags &&& @no_assist) == 0 and
      not blackboard.navigation.returning_home? and not Aura.has_aura?(entity, :mod_invisibility)
  end

  def available?(_entity), do: false

  defp idle_creature?(%Mob{unit: unit, internal: internal} = entity) do
    is_number(unit.health) and unit.health > 0 and internal.in_combat != true and
      uncontrolled?(entity) and not Mob.critter?(entity)
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
