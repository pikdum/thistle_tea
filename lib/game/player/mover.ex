defmodule ThistleTea.Game.Player.Mover do
  @moduledoc "Tracks the mover acknowledged by a client separately from the unit it may currently control."

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.PlayerPossession
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Player.CompanionVisibility
  alias ThistleTea.Game.Player.Exploration
  alias ThistleTea.Game.Player.Instances
  alias ThistleTea.Game.Player.ItemLoot
  alias ThistleTea.Game.Player.Movement
  alias ThistleTea.Game.Player.Taxi
  alias ThistleTea.Game.World.Visibility

  def select(%State{ready: true} = state, 0), do: %{state | client_mover_guid: nil}

  def select(%State{} = state, guid) when is_integer(guid) and guid > 0 do
    if expected_guid(state) == guid do
      %{state | active_mover_guid: guid, client_mover_guid: guid} |> enter_world()
    else
      state
    end
  end

  def select(state, _guid), do: state

  def release(%State{ready: true, client_mover_guid: guid} = state, guid, payload) when is_integer(guid) and guid > 0 do
    if guid != state.guid and expected_guid(state) == guid do
      state
    else
      state = %{state | client_mover_guid: nil}

      if guid == state.guid do
        Movement.finish_input(state, state.guid, payload)
      else
        Entity.finish_movement(guid, state.guid, payload)
        state
      end
    end
  end

  def release(state, _guid, _payload), do: state

  defp expected_guid(%State{character: %Character{} = character, guid: guid}) do
    if not PlayerPossession.active?(character), do: Companion.possession_guid(character) || guid
  end

  defp expected_guid(%State{guid: guid}), do: guid

  defp enter_world(%State{ready: true} = state), do: state

  defp enter_world(%State{} = state) do
    state = Visibility.enter_player(%{state | ready: true})

    state
    |> Instances.refresh()
    |> Taxi.resume()
    |> CompanionVisibility.defer_restoration()
    |> Exploration.check_current()
    |> ItemLoot.open()
  end
end
