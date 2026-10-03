defmodule ThistleTea.Game.Core.AI.BT.WaypointHold do
  @moduledoc """
  Holds a creature at its current waypoint until every creature it summoned
  is gone, the way vmangos escort scripts pause (`SetEscortPaused`) until
  their ambushers are dead. A creature counts its own summons from the
  moment each one spawns until that summon dies or despawns.

  A hold set at a waypoint never releases on the tick that set it, so the
  summons spawned beside it are counted first. It releases on a later tick
  once no summon is left, or when it runs out at `until`, and then runs its
  release steps.
  """

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Pet.SummonEvent

  @enforce_keys [:until, :ready_at]
  defstruct [:until, :ready_at, steps: []]

  @summon_endings [:summoned_just_died, :summoned_just_despawn]

  def track(%Mob{internal: %Internal{live_summons: summons} = internal} = mob, guid) when is_integer(guid),
    do: %{mob | internal: %{internal | live_summons: MapSet.put(summons, guid)}}

  def track(entity, _guid), do: entity

  def forget(%Mob{internal: %Internal{} = internal} = mob, %SummonEvent{event: event, observation: %{guid: guid}})
      when event in @summon_endings do
    %{mob | internal: %{internal | live_summons: MapSet.delete(internal.live_summons, guid)}}
  end

  def forget(entity, _event), do: entity

  def start(%Blackboard{navigation: navigation} = blackboard, now, duration_ms, steps)
      when is_integer(now) and is_integer(duration_ms) and is_list(steps) do
    hold = %__MODULE__{until: now + max(duration_ms, 0), ready_at: now + 1, steps: steps}
    %{blackboard | navigation: %{navigation | waypoint_hold: hold}}
  end

  def clear(%Blackboard{navigation: navigation} = blackboard),
    do: %{blackboard | navigation: %{navigation | waypoint_hold: nil}}

  def status(%Mob{internal: %Internal{live_summons: summons}}, %Blackboard{} = blackboard, now) when is_integer(now) do
    case blackboard.navigation.waypoint_hold do
      %__MODULE__{} = hold ->
        cond do
          now >= hold.until -> {:release, hold.steps}
          now < hold.ready_at -> {:hold, hold.ready_at - now}
          MapSet.size(summons) == 0 -> {:release, hold.steps}
          true -> {:hold, hold.until - now}
        end

      nil ->
        :none
    end
  end

  def status(_entity, _blackboard, _now), do: :none
end
