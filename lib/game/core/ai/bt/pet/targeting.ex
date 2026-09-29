defmodule ThistleTea.Game.Core.AI.BT.Pet.Targeting do
  @moduledoc "Pet attack permissions for automatic acquisition, retaliation, and spell autocasting."

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Combat
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Detection
  alias ThistleTea.Game.Core.AI.BT.Navigation
  alias ThistleTea.Game.Core.Combat.CombatControl
  alias ThistleTea.Game.Core.Combat.Hostility
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell

  @unit_pvp 0x00001000

  def proximity_allowed?(%Mob{internal: %{pet: %Pet{}}} = pet, target, context) do
    not Blackboard.pet_returning?(pet.internal.blackboard) and automatic_allowed?(pet, target, context)
  end

  def proximity_allowed?(_entity, _target, _context), do: true

  def automatic_allowed?(%Mob{internal: %{pet: %Pet{} = control}} = pet, target, %Context{} = context) do
    metadata = Perception.metadata(context.perception, target) || %{}

    control.reaction_state != :passive and not control.broken? and not control.possessed? and
      not Blackboard.pet_recalled?(pet.internal.blackboard) and
      crowd_control_allowed?(control, metadata) and pvp_allowed?(pet, metadata) and
      within_stay_range?(pet, target, context)
  end

  def automatic_allowed?(_entity, _target, _context), do: true

  defp within_stay_range?(%Mob{internal: %{pet: %Pet{command_state: :stay}}} = pet, target, context) do
    Blackboard.pet_returning?(pet.internal.blackboard) or Combat.in_melee_range?(pet, target, context)
  end

  defp within_stay_range?(_pet, _target, _context), do: true

  def autocast_allowed?(pet, %Spell{} = spell, target, %Context{} = context) do
    not Spell.harmful?(spell) or commanded?(pet, target) or automatic_allowed?(pet, target, context)
  end

  def retaliation?(%Mob{} = pet, target, %Context{perception: perception} = context) do
    not Entity.dead?(pet) and not CombatControl.auto_attack_blocked?(pet) and
      not living_victim?(pet, context) and automatic_allowed?(pet, target, context) and
      Navigation.target_alive_same_map?(pet, target, context) and Detection.detectable?(pet, target, context) and
      Hostility.valid_attack_target?(
        Perception.actor(perception, pet.object.guid),
        Perception.actor(perception, target)
      )
  end

  defp commanded?(%Mob{unit: %{target: target}, internal: %{pet: %Pet{attack_command?: true}}}, target)
       when is_integer(target) and target > 0, do: true

  defp commanded?(_pet, _target), do: false

  defp living_victim?(%Mob{internal: %{in_combat: true}, unit: %{target: target}} = pet, context)
       when is_integer(target) and target > 0, do: Navigation.target_alive_same_map?(pet, target, context)

  defp living_victim?(_pet, _context), do: false

  defp crowd_control_allowed?(%Pet{kind: :guardian, reaction_state: :aggressive}, _target), do: true
  defp crowd_control_allowed?(_control, target), do: not Map.get(target, :breakable_crowd_control?, false)

  defp pvp_allowed?(%Mob{unit: %{flags: flags}, internal: %{pet: %Pet{owner_guid: owner}}}, target) do
    not player?(owner) or ((flags || 0) &&& @unit_pvp) != 0 or
      ((Map.get(target, :unit_flags) || 0) &&& @unit_pvp) == 0
  end

  defp player?(guid) when is_integer(guid) and guid > 0, do: Guid.entity_type(guid) == :player
  defp player?(_guid), do: false
end
