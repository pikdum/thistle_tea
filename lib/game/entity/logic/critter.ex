defmodule ThistleTea.Game.Entity.Logic.Critter do
  @moduledoc """
  Timed escape reactions for ordinary critters. Surviving damage and harmful
  non-damage spells refresh combat escape without restarting an active flee.
  """

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Critter, as: Memory
  alias ThistleTea.Game.Entity.Logic.ControlMovement
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Spell

  @escape_ms 30_000
  @direct_damage [
    :school_damage,
    :weapon_damage,
    :weapon_damage_noschool,
    :normalized_weapon_damage,
    :weapon_percent_damage,
    :health_leech,
    :power_burn,
    :instakill
  ]

  def react(%Mob{unit: %{health: health}, object: %{guid: guid}} = mob, source_guid, now)
      when health > 0 and is_integer(source_guid) and source_guid > 0 and source_guid != guid and is_integer(now) do
    if Mob.critter?(mob), do: start_escape(mob, source_guid, now), else: mob
  end

  def react(entity, _source_guid, _now), do: entity

  def spell_hit(entity, source_guid, %Spell{} = spell, now) do
    if Spell.harmful?(spell) and not Enum.any?(spell.effects, &(&1.type in @direct_damage)) do
      react(entity, source_guid, now)
    else
      entity
    end
  end

  def expired?(%Mob{internal: %{in_combat: true}} = mob, %Blackboard{} = blackboard, now) do
    Mob.critter?(mob) and (is_nil(blackboard.critter) or now >= blackboard.critter.escape_at)
  end

  def expired?(_entity, _blackboard, _now), do: false

  defp start_escape(mob, source_guid, now) do
    %Engagement.Result{entity: mob} = Engagement.enter(mob, source_guid, now, selection: :preserve)
    blackboard = Blackboard.ensure(mob.internal.blackboard)
    memory = blackboard.critter || %Memory{escape_at: now + @escape_ms, previous_running: mob.internal.running}
    blackboard = %{blackboard | critter: %{memory | escape_at: now + @escape_ms}}

    {mob, blackboard} =
      if is_integer(blackboard.combat.flee_until) and now < blackboard.combat.flee_until do
        {mob, blackboard}
      else
        {mob, events} = Movement.stop_with_effects(mob, now)
        mob = Effects.enqueue(mob, events)
        blackboard = blackboard |> Blackboard.clear_move_target() |> Blackboard.start_flee(source_guid, @escape_ms, now)
        {%{mob | internal: %{mob.internal | navigation_intents: []}}, blackboard}
      end

    %{mob | internal: %{mob.internal | blackboard: blackboard, broadcast_update?: true}}
    |> ControlMovement.sync_flags()
  end
end
