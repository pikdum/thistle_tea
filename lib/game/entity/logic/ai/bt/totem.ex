defmodule ThistleTea.Game.Entity.Logic.AI.BT.Totem do
  @moduledoc """
  Stationary totem behavior: maintain periodic auras and cast the template's
  VMangos-defined totem spell without entering ordinary mob melee or movement.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Aura, as: AuraBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob.Spells, as: MobSpells
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World

  @target_radius 30.0
  @idle_delay_ms 200

  def tree do
    BT.selector([
      AuraBT.tick_step(),
      SpellBT.casting_sequence(),
      BT.action(&select_hostile_target/2),
      MobSpells.step(),
      BT.action(&idle/2)
    ])
  end

  defp select_hostile_target(
         %Mob{internal: %Internal{spellbook: spellbook, creature: %Creature{spells: [entry | _]}}} = state,
         %Blackboard{} = blackboard
       ) do
    case Map.get(spellbook, entry.spell_id) do
      %Spell{} = spell -> {:failure, put_target(state, spell), blackboard}
      _ -> {:failure, state, blackboard}
    end
  end

  defp select_hostile_target(state, blackboard), do: {:failure, state, blackboard}

  defp put_target(%Mob{} = state, %Spell{} = spell) do
    if Spell.requires_hostile_target?(spell) do
      %{state | unit: %{state.unit | target: nearest_hostile(state) || 0}}
    else
      state
    end
  end

  defp nearest_hostile(%Mob{internal: %{world: world}, movement_block: %{position: {x, y, z, _o}}} = state) do
    ((:mobs |> World.nearby_units_exact(world, {x, y, z}, @target_radius)) ++
       (:players |> World.nearby_units_exact(world, {x, y, z}, @target_radius)))
    |> Enum.map(&elem(&1, 0))
    |> Enum.reject(&(&1 == state.object.guid))
    |> Enum.find(&Hostility.valid_attack_target?(state, &1))
  end

  defp nearest_hostile(_state), do: nil

  defp idle(state, blackboard), do: {BT.running(@idle_delay_ms, :totem), state, blackboard}
end
