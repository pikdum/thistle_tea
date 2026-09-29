defmodule ThistleTea.Game.Core.Spell.CastingCombat do
  @moduledoc "Melee timer and attack-intent transitions at spell launch and successful completion."

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.Combat.AttackTimers
  alias ThistleTea.Game.Core.Combat.CombatWeapon
  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Combat.PlayerCombat
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cast

  def launch(%{internal: %Internal{}} = entity, %Cast{spell: %Spell{} = spell, triggered?: false}, now)
      when is_integer(now) do
    if (spell.interrupt_flags &&& 0x08) != 0 and not Spell.attribute?(spell, :do_not_reset_combat_timers) do
      reset_swings(entity, now)
    else
      entity
    end
  end

  def launch(entity, %Cast{}, _now), do: entity

  def finish(entity, %Spell{} = spell, target_guid \\ nil) do
    cond do
      Spell.attribute?(spell, :cancels_auto_attack_combat) -> stop_attacks(entity)
      initiates_attack?(spell) -> command_pet_attack(entity, target_guid)
      true -> entity
    end
  end

  defp initiates_attack?(spell) do
    Spell.attribute?(spell, :initiates_combat) or Spell.attribute?(spell, :initiate_combat_post_cast)
  end

  defp command_pet_attack(%Mob{internal: %Internal{pet: %Pet{kind: kind, possessed?: false}}} = entity, target_guid)
       when kind in [:hunter, :summon] and is_integer(target_guid) and target_guid > 0 do
    Effects.enqueue(entity, %Effects.PetSpellAttack{target_guid: target_guid})
  end

  defp command_pet_attack(entity, _target_guid), do: entity

  defp reset_swings(entity, now) do
    entity = AttackTimers.reset(entity, :mainhand, now)

    if CombatWeapon.usable(entity, :offhand),
      do: AttackTimers.reset(entity, :offhand, now),
      else: entity
  end

  defp stop_attacks(%Character{} = character) do
    {character, events} = PlayerCombat.stop_attack(character)
    Effects.enqueue(character, events)
  end

  defp stop_attacks(%Mob{} = entity) do
    %Engagement.Result{entity: entity} = Engagement.stop_attack(entity)
    entity
  end

  defp stop_attacks(entity), do: entity
end
