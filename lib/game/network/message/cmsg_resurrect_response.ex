defmodule ThistleTea.Game.Network.Message.CmsgResurrectResponse do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_RESURRECT_RESPONSE

  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Network.Server
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Visibility

  defstruct [:guid, :status]

  @impl ClientMessage
  def handle(%__MODULE__{status: 0}, %{ready: true, character: %Character{} = character} = state) do
    %{state | character: clear_pending(character)}
  end

  def handle(%__MODULE__{guid: guid}, %{ready: true, character: %Character{} = character} = state) do
    pending = pending_resurrect(character)

    if is_map(pending) and pending.caster_guid == guid and not Death.alive?(character) do
      accept(state, character, pending)
    else
      state
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), status::little-size(8), _rest::binary>> = payload

    %__MODULE__{
      guid: guid,
      status: status
    }
  end

  defp accept(state, character, pending) do
    now = Time.now()
    World.stop_entity(Corpse.guid_for(state.guid))

    character = clear_pending(character)
    {character, events} = Death.resurrect_with(character, pending.health, pending.mana, now)
    character = EventSink.emit(character, events)

    state = Server.maybe_broadcast_update(%{state | character: character})

    Visibility.notify_visibility_changed(state.character)
    state = Visibility.resync_player(state)

    teleport_to_caster(state, pending.position)
  end

  defp teleport_to_caster(state, {map, x, y, z}) do
    GenServer.cast(self(), {:start_teleport, x, y, z, map})
    state
  end

  defp teleport_to_caster(state, _position), do: state

  defp pending_resurrect(%Character{internal: internal}), do: internal.pending_resurrect

  defp clear_pending(%Character{internal: internal} = character) do
    %{character | internal: %{internal | pending_resurrect: nil}}
  end
end
