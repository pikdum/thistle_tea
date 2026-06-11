defmodule ThistleTea.Game.Network.Message.CmsgReclaimCorpse do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_RECLAIM_CORPSE

  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility

  @restore_percent 0.5

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, character: %Character{} = character} = state) do
    corpse_guid = Corpse.guid_for(state.guid)
    now = Time.now()

    if reclaimable?(character, corpse_guid, now) do
      resurrect(state, character, corpse_guid, now)
    else
      state
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end

  def resurrect(state, character, corpse_guid, now, restore_percent \\ @restore_percent) do
    World.stop_entity(corpse_guid)

    {character, events} = Death.resurrect(character, restore_percent, now)
    character = EventSink.emit(character, events)

    update = Core.update_object(character, :values)
    Network.send_packet(update)
    World.broadcast_packet(update, character, include_self?: false)
    Metadata.update(state.guid, %{alive?: true, ghost?: false})

    state = %{state | character: clear_broadcast_flag(character)}

    Visibility.notify_visibility_changed(character)
    Visibility.resync_player(state)
  end

  defp reclaimable?(character, corpse_guid, now) do
    Death.ghost?(character) and
      corpse_in_range?(character, corpse_guid) and
      reclaim_delay_elapsed?(corpse_guid, now)
  end

  defp corpse_in_range?(character, corpse_guid) do
    case World.distance_to_guid(character, corpse_guid) do
      distance when is_number(distance) -> distance <= Death.corpse_reclaim_radius()
      _ -> false
    end
  end

  defp reclaim_delay_elapsed?(corpse_guid, now) do
    case Metadata.query(corpse_guid, [:ghost_time]) do
      %{ghost_time: ghost_time} when is_integer(ghost_time) -> now >= ghost_time + Death.reclaim_delay_ms()
      _ -> false
    end
  end

  defp clear_broadcast_flag(%Character{internal: internal} = character) do
    %{character | internal: %{internal | broadcast_update?: false}}
  end
end
