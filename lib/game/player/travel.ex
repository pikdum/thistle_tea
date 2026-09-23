defmodule ThistleTea.Game.Player.Travel do
  @moduledoc """
  Completes acknowledged travel once, refreshes destination territory, and
  applies arrival protection without treating login or combat leaps as travel.
  """

  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.MovementControl
  alias ThistleTea.Game.Player.CompanionVisibility
  alias ThistleTea.Game.Player.Exploration
  alias ThistleTea.Game.Player.Instances
  alias ThistleTea.Game.Player.ItemLoot
  alias ThistleTea.Game.Player.Login
  alias ThistleTea.Game.Player.Pvp
  alias ThistleTea.Game.World.Visibility

  def worldport_ack(%State{pending_worldport?: true} = state) do
    character = Login.send_worldport_packets(state.character)
    state = State.complete_worldport(%{state | character: character})
    state = Visibility.enter_player(%{state | ready: true})

    state
    |> Instances.refresh()
    |> CompanionVisibility.defer_restoration()
    |> Exploration.check_current()
    |> Pvp.arrive()
    |> ItemLoot.open()
  end

  def worldport_ack(state), do: state

  def teleport_ack(%State{} = state, guid, counter) do
    case MovementControl.acknowledge_teleport(state, guid, counter) do
      {:ok, state, kind} ->
        state =
          state
          |> Visibility.refresh_player()
          |> MovementControl.maybe_finish_repop()
          |> Exploration.check_current()

        if kind == :teleport, do: state |> CompanionVisibility.defer_restoration() |> Pvp.arrive(), else: state

      {:error, state} ->
        state
    end
  end
end
