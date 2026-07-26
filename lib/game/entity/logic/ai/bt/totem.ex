defmodule ThistleTea.Game.Entity.Logic.AI.BT.Totem do
  @moduledoc """
  Stationary totem behavior: maintain periodic auras and cast the template's
  VMangos-defined totem spell without entering ordinary mob melee or movement.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob.Spells, as: MobSpells
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Spell

  @target_radius 30.0
  @idle_delay_ms 200

  def tree do
    BT.selector([
      SpellBT.casting_sequence(),
      BT.action(&select_hostile_target/3),
      MobSpells.step(),
      BT.action(&idle/2)
    ])
  end

  defp select_hostile_target(
         %Mob{internal: %Internal{spellbook: spellbook, creature: %Creature{spells: [entry | _]}}} = state,
         %Blackboard{} = blackboard,
         %Context{} = context
       ) do
    case Map.get(spellbook, entry.spell_id) do
      %Spell{} = spell -> {:failure, put_target(state, spell, context), blackboard}
      _ -> {:failure, state, blackboard}
    end
  end

  defp select_hostile_target(state, blackboard, %Context{}), do: {:failure, state, blackboard}

  defp put_target(%Mob{} = state, %Spell{} = spell, %Context{} = context) do
    if Spell.requires_hostile_target?(spell) do
      %Engagement.Result{entity: state} = Engagement.focus(state, nearest_hostile(state, context), :totem_target)
      state
    else
      state
    end
  end

  defp nearest_hostile(%Mob{} = state, %Context{perception: perception}) do
    (Perception.nearby(perception, :mobs, @target_radius) ++
       Perception.nearby(perception, :players, @target_radius))
    |> Enum.map(&elem(&1, 0))
    |> Enum.reject(&(&1 == state.object.guid))
    |> Enum.find(fn guid ->
      source = Perception.actor(perception, state.object.guid)
      target = Perception.actor(perception, guid)
      Hostility.valid_attack_target?(source, target)
    end)
  end

  defp idle(state, blackboard), do: {BT.running(@idle_delay_ms, :totem), state, blackboard}
end
