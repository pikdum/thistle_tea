defmodule ThistleTea.Game.Player.Resurrection do
  @moduledoc "Accepts spell resurrection offers, admits their travel, and revives after arrival."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Data.ResurrectionOffer
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Resurrection, as: ResurrectionLogic
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Player.Instances
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.AreaTrigger
  alias ThistleTea.Game.World.System.Instance
  alias ThistleTea.Game.World.Visibility
  alias ThistleTea.Game.WorldRef

  def respond(%{ready: true, character: %Character{} = character} = state, guid, status) do
    updated = ResurrectionLogic.respond(character, guid, status)

    if updated != character and match?(%ResurrectionOffer{phase: :accepted}, updated.internal.pending_resurrect) do
      GenServer.cast(self(), {:accept_resurrection, updated.internal.pending_resurrect})
      %{state | character: updated, pending_repop: nil}
    else
      %{state | character: updated}
    end
  end

  def respond(state, _guid, _status), do: state

  def start(
        %{character: %Character{internal: %{pending_resurrect: offer}} = character} = state,
        %ResurrectionOffer{phase: :accepted} = offer
      ) do
    if Death.alive?(character), do: {:finished, clear(state)}, else: start_accepted(state, offer)
  end

  def start(state, _offer), do: {:finished, state}

  def transferring(%{character: character} = state, %ResurrectionOffer{} = offer) do
    %{state | character: ResurrectionLogic.put(character, %{offer | phase: :transferring, arrival: nil})}
  end

  def arrive(
        %{
          character: %Character{
            internal: %{pending_resurrect: %ResurrectionOffer{phase: :transferring, arrival: arrival} = offer}
          }
        } = state,
        arrival
      ) do
    if Death.alive?(state.character), do: clear(state), else: finish(state, offer)
  end

  def arrive(state, _arrival), do: state

  def cancel_transfer(%{character: %Character{} = character} = state) do
    %{state | character: ResurrectionLogic.cancel_transfer(character)}
  end

  def cancel_transfer(state), do: state

  def clear(%{character: %Character{} = character} = state),
    do: %{state | character: ResurrectionLogic.clear(character)}

  def clear(state), do: state

  defp start_accepted(state, %ResurrectionOffer{caster_guid: guid, position: {%WorldRef{} = world, x, y, z}} = offer) do
    if Guid.entity_type(guid) == :player do
      case Instance.destination(world.map_id, state.guid) do
        {:ok, ^world} ->
          {:teleport, {world, x, y, z, orientation(state, offer)}, state}

        {:ok, destination} ->
          changed_copy(state, offer, destination)

        {:error, reason} ->
          Instances.reject(reason)
          {:finished, finish(state, offer)}
      end
    else
      {:finished, finish(state, offer)}
    end
  end

  defp start_accepted(state, offer), do: {:finished, finish(state, offer)}

  defp changed_copy(state, offer, world) do
    case AreaTrigger.entrance(world.map_id) do
      %{x: x, y: y, z: z, orientation: orientation} ->
        {:teleport, {world, x, y, z, orientation}, state}

      nil ->
        Instance.leave(state.guid, world)
        {:finished, finish(state, offer)}
    end
  end

  defp orientation(_state, %ResurrectionOffer{orientation: value}) when is_number(value), do: value
  defp orientation(state, _offer), do: elem(state.character.movement_block.position, 3)

  defp finish(%{character: character} = state, offer) do
    {character, events} = Death.resurrect_with(character, offer.health, offer.mana, Time.now())
    World.stop_entity(Corpse.guid_for(state.guid))
    character = EventSink.emit(character, events)
    state = PlayerServer.maybe_broadcast_update(%{state | character: character, pending_repop: nil})
    Visibility.notify_visibility_changed(state.character)
    Visibility.resync_player(state)
  end
end
