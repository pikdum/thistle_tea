defmodule ThistleTea.Game.World.Entity.Player.MeetingStones do
  @moduledoc "Validates native Meeting Stone interactions and routes scripted queue requests to the party owner."

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Entity, as: EntityCore
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Movement.ControlMovement
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Pet.PlayerPossession
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.GameObjects
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
    not EntityCore.dead?(character) and not PlayerPossession.active?(character) and
      not ControlMovement.active?(character) and
      not Aura.has_aura?(character, :mod_stun) and not Aura.has_aura?(character, :feign_death) and
      character.internal.taxi_flight == nil and Companion.possession_guid(character) == nil
  end
end
