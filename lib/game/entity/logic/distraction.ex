defmodule ThistleTea.Game.Entity.Logic.Distraction do
  @moduledoc """
  Turns responsive, idle units toward a distraction and pauses creature navigation.
  Combat cancels the pause; expiry leaves the existing patrol destination intact.
  """

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Fear
  alias ThistleTea.Game.Entity.Logic.Movement

  def apply(entity, {x, y, _z}, duration_ms, now) when duration_ms > 0 do
    if responsive?(entity) do
      {entity, events} = Movement.stop_with_effects(entity, now)
      entity = entity |> Movement.face_towards({x, y}) |> pause(duration_ms, now)
      {_, _, _, orientation} = entity.movement_block.position
      {entity, events ++ [Effects.set_facing({:angle, orientation})]}
    else
      {entity, []}
    end
  end

  def apply(entity, _destination, _duration_ms, _now), do: {entity, []}

  def tick(entity, %Blackboard{navigation: navigation} = blackboard, %Context{now: now}) do
    case navigation.distracted_until do
      until when is_integer(until) and until > now ->
        if responsive?(entity) do
          {BT.running(min(until - now, 500), :distracted), entity, blackboard}
        else
          {:failure, entity, clear(blackboard)}
        end

      _ ->
        {:failure, entity, clear(blackboard)}
    end
  end

  def clear(%Blackboard{navigation: navigation} = blackboard) do
    %{blackboard | navigation: %{navigation | distracted_until: nil}}
  end

  defp pause(%Mob{internal: internal} = entity, duration_ms, now) do
    blackboard = Blackboard.ensure(internal.blackboard)
    navigation = %{blackboard.navigation | distracted_until: now + duration_ms, move_target: nil}
    %{entity | internal: %{internal | blackboard: %{blackboard | navigation: navigation}}}
  end

  defp pause(entity, _duration_ms, _now), do: entity

  defp responsive?(entity) do
    not Core.dead?(entity) and entity.internal.in_combat != true and not Fear.active?(entity) and
      not Enum.any?([:mod_stun, :mod_confuse, :feign_death], &Aura.has_aura?(entity, &1))
  end
end
