defmodule ThistleTea.Game.Core.AI.BT.WaypointHold do
  @moduledoc """
  Holds a creature at its current waypoint, the way vmangos escort scripts
  pause (`SetEscortPaused`). A creature counts its own summons from the
  moment each one spawns until that summon dies or despawns.

  A `:summons` hold waits until the creature's summons are dead, as escorts
  pause until their ambushers die. It counts only the summons that spawned
  after the hold began, so a creature that leads summoned companions still
  stops for the next ambush. It never releases on the tick that set it, so
  the summons spawned beside it are counted first. A `:signal` hold waits
  until a script releases it, which also makes a timed pause when nothing
  does. Either hold releases once it runs out at `until`, and then runs its
  release steps.
  """

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Pet.SummonEvent

  @enforce_keys [:until, :ready_at]
  defstruct [:until, :ready_at, steps: [], mode: :summons, earlier_summons: MapSet.new()]

  @summon_endings [:summoned_just_died, :summoned_just_despawn]

  def track(%Mob{internal: %Internal{live_summons: summons} = internal} = mob, guid) when is_integer(guid),
    do: %{mob | internal: %{internal | live_summons: MapSet.put(summons, guid)}}

  def track(entity, _guid), do: entity

  def forget(%Mob{internal: %Internal{} = internal} = mob, %SummonEvent{event: event, observation: %{guid: guid}})
      when event in @summon_endings do
    %{mob | internal: %{internal | live_summons: MapSet.delete(internal.live_summons, guid)}}
  end

  def forget(entity, _event), do: entity

  def start(%Blackboard{navigation: navigation} = blackboard, now, duration_ms, steps, opts \\ [])
      when is_integer(now) and is_integer(duration_ms) and is_list(steps) do
    hold = %__MODULE__{
      until: now + max(duration_ms, 0),
      ready_at: now + 1,
      steps: steps,
      mode: Keyword.get(opts, :mode, :summons),
      earlier_summons: Keyword.get(opts, :earlier_summons, MapSet.new())
    }

    %{blackboard | navigation: %{navigation | waypoint_hold: hold}}
  end

  def release(%Blackboard{navigation: %{waypoint_hold: %__MODULE__{} = hold} = navigation} = blackboard, now)
      when is_integer(now) do
    %{blackboard | navigation: %{navigation | waypoint_hold: %{hold | until: min(hold.until, now)}}}
  end

  def release(%Blackboard{} = blackboard, _now), do: blackboard

  def clear(%Blackboard{navigation: navigation} = blackboard),
    do: %{blackboard | navigation: %{navigation | waypoint_hold: nil}}

  def status(%Mob{internal: %Internal{live_summons: summons}}, %Blackboard{} = blackboard, now) when is_integer(now) do
    case blackboard.navigation.waypoint_hold do
      %__MODULE__{} = hold ->
        cond do
          now >= hold.until -> {:release, hold.steps}
          hold.mode == :signal -> {:hold, hold.until - now}
          now < hold.ready_at -> {:hold, hold.ready_at - now}
          MapSet.subset?(summons, hold.earlier_summons) -> {:release, hold.steps}
          true -> {:hold, hold.until - now}
        end

      nil ->
        :none
    end
  end

  def status(_entity, _blackboard, _now), do: :none
end
