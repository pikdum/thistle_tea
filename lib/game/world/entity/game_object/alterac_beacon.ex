defmodule ThistleTea.Game.World.Entity.GameObject.AlteracBeacon do
  @moduledoc "Runs an Alterac beacon's summon timer and revalidates enemy disarming at spell completion."

  alias ThistleTea.Game.Core.Battleground.AlteracValley.Beacon
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Loot.Actor
  alias ThistleTea.Game.Core.Profession.OpenLock
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context
  alias ThistleTea.Game.World.Entity.GameObject.OpenLock, as: ObjectOpenLock
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Battleground, as: BattlegroundSystem

  def start(%GameObject{internal: %{beacon: %Beacon{ready_at: at}}} = state) do
    Process.send_after(self(), :alterac_beacon_summon, max(at - Time.now(), 0))
    state
  end

  def start(%GameObject{} = state), do: state

  def summon(%GameObject{internal: %{beacon: %Beacon{status: :waiting}}} = state) do
    state = Beacon.summon(state, Time.now())

    case state.internal.beacon.status do
      :summoned ->
        state = EventSink.emit_pending(state, Context.new(self()))
        send(self(), :despawn)
        state

      :waiting ->
        start(state)
    end
  end

  def summon(%GameObject{} = state), do: state

  def open(%GameObject{} = state, %Actor{} = actor, %OpenLock{lock_type: 14} = opened) do
    world = state.internal.world

    with {^world, _, _, _} <- World.position(actor.guid),
         distance when is_number(distance) and distance <= 5.0 <- World.distance_between(state, actor.guid),
         %{alive?: true} <- Metadata.get(actor.guid),
         %{map_id: 30, phase: :active, team: team} <- BattlegroundSystem.spell_context(world, actor.guid),
         {{:ok, :activate, _}, opened_state} <- ObjectOpenLock.open(state, actor, opened, false),
         {:ok, disabled} <- Beacon.disable(opened_state, team, Time.now()) do
      send(self(), :despawn)
      {{:ok, :disarmed, false}, disabled}
    else
      _invalid -> {{:error, :bad_targets}, state}
    end
  end

  def open(%GameObject{} = state, _actor, _opened), do: {{:error, :bad_targets}, state}
end
