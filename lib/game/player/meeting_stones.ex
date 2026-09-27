defmodule ThistleTea.Game.Player.MeetingStones do
  @moduledoc "Validates native Meeting Stone interactions and routes scripted queue requests to the party owner."

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.ControlMovement
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.PlayerPossession
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Player.GameObjects
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: TemplateLoader
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.World.Visibility

  def join(%{ready: true} = state, guid) do
    with true <- can_interact?(state.character),
         :game_object <- Guid.entity_type(guid),
         %GameObjectTemplate{type: 23, data: [_min, _max, area | _]} <- TemplateLoader.cached(Guid.entry(guid)),
         true <- Entity.online?(guid) and Visibility.can_see?(state, guid),
         true <- GameObjects.interactable?(state.character, guid) do
      queue(state, area)
    else
      _ -> state
    end
  end

  def join(state, _guid), do: state

  def queue(%{ready: true, guid: guid} = state, area) when is_integer(area) and area > 0 do
    PartySystem.meeting_stone(:join, guid, area)
    state
  end

  def queue(state, _area), do: state

  def request(%{ready: true, guid: guid} = state, action) when action in [:info, :leave] do
    PartySystem.meeting_stone(action, guid)
    state
  end

  def request(state, _action), do: state

  defp can_interact?(character) do
    not Core.dead?(character) and not PlayerPossession.active?(character) and not ControlMovement.active?(character) and
      not Aura.has_aura?(character, :mod_stun) and not Aura.has_aura?(character, :feign_death) and
      character.internal.taxi_flight == nil and Companion.possession_guid(character) == nil
  end
end
