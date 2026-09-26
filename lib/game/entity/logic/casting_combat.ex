defmodule ThistleTea.Game.Entity.Logic.CastingCombat do
  @moduledoc "Melee timer and attack-intent transitions at spell launch and successful completion."

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.CombatWeapon
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast

  def launch(%{internal: %Internal{}} = entity, %Cast{spell: %Spell{} = spell, triggered?: false}, now)
      when is_integer(now) do
    if (spell.interrupt_flags &&& 0x08) != 0 and not Spell.attribute?(spell, :do_not_reset_combat_timers) do
      reset_swings(entity, now)
    else
      entity
    end
  end

  def launch(entity, %Cast{}, _now), do: entity

  def finish(entity, %Spell{} = spell) do
    if Spell.attribute?(spell, :cancels_auto_attack_combat), do: stop_attacks(entity), else: entity
  end

  defp reset_swings(entity, now) do
    blackboard =
      entity.internal.blackboard
      |> Blackboard.ensure()
      |> Blackboard.put_next_at(:next_attack_at, Combat.attack_speed_ms(entity), now)

    blackboard =
      if CombatWeapon.usable(entity, :offhand) do
        Blackboard.put_next_at(
          blackboard,
          :next_offhand_attack_at,
          Combat.offhand_attack_speed_ms(entity) || 2_000,
          now
        )
      else
        blackboard
      end

    %{entity | internal: %{entity.internal | blackboard: blackboard}}
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
