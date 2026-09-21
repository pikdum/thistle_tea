defmodule ThistleTea.Game.Entity.Server.Player.PacketSink do
  @moduledoc """
  Interprets player outbound messages at the connection boundary.

  It owns viewer filtering, update-object batching, movement acknowledgement
  sequencing, and final packet encoding. Gameplay code only emits message or
  update structs.
  """
  use ThistleTea.Game.Network.Opcodes, [:SMSG_UPDATE_OBJECT]

  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.MovementControl
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Network.UpdateBatcher
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World.Visibility
  alias ThistleTea.Game.World.Visibility.QuestGivers
  alias ThistleTea.Game.World.Visibility.Tap

  def send(state, message, opts \\ [])

  def send(%State{} = state, %UpdateObject{update_type: :out_of_range_objects} = update, _opts) do
    state
    |> send_packet(UpdateObject.to_packet(update, state.guid))
    |> track_updates([update])
  end

  def send(%State{} = state, %UpdateObject{} = update, opts) do
    source_guid = Keyword.get(opts, :source_guid)

    cond do
      not source_tracked?(state, source_guid) -> state
      is_integer(source_guid) -> send_update(update, state)
      duplicate_create?(state, update) -> state
      true -> send_update(update, state)
    end
  end

  def send(%State{}, %Packet{opcode: @smsg_update_object}, _opts) do
    raise "SMSG_UPDATE_OBJECT packets must be sent as UpdateObject structs"
  end

  def send(%State{} = state, %Message.SmsgDestroyObject{guid: guid} = message, []) do
    if Visibility.tracked?(state, guid) do
      state
      |> send_message(message)
      |> Visibility.untrack_entity(guid)
    else
      state
    end
  end

  def send(%State{} = state, %Message.SmsgDestroyObject{guid: guid} = message, opts) do
    if Keyword.get(opts, :force, false) or source_tracked?(state, Keyword.get(opts, :source_guid)) do
      state
      |> send_message(message)
      |> Visibility.untrack_entity(guid)
    else
      state
    end
  end

  def send(%State{} = state, %Message.SmsgQuestgiverStatus{} = message, opts) do
    if source_tracked?(state, Keyword.get(opts, :source_guid)) do
      state |> send_message(message) |> QuestGivers.remember(message)
    else
      state
    end
  end

  def send(%State{} = state, message, opts) do
    if source_tracked?(state, Keyword.get(opts, :source_guid)) do
      send_message(state, message)
    else
      state
    end
  end

  def ensure_created(%State{} = state, %UpdateObject{} = update) do
    if duplicate_create?(state, update) or not visible_update?(state, update) do
      state
    else
      update = personalize(update, state)
      packet = UpdateObject.to_packet([update], state.guid)

      state
      |> send_packet(packet)
      |> track_updates([update])
    end
  end

  defp send_update(%UpdateObject{} = update, %State{} = state) do
    viewer = state.guid
    {packet, updates} = UpdateBatcher.batch(update, viewer, &personalize(&1, state), &visible_update?(state, &1))

    if updates == [] do
      state
    else
      state
      |> send_packet(packet)
      |> track_updates(updates)
    end
  end

  defp personalize(update, %State{} = state) do
    update
    |> Tap.personalize(state.guid)
    |> QuestGivers.personalize(state.character)
  end

  defp visible_update?(state, %UpdateObject{object: %{guid: guid}}) when is_integer(guid) do
    Guid.entity_type(guid) == :item or Visibility.can_see?(state, guid)
  end

  defp visible_update?(_state, _update), do: true

  defp send_message(%State{} = state, %Packet{} = packet), do: send_packet(state, packet)

  defp send_message(%State{} = state, message) do
    {message, state} = MovementControl.prepare(message, state)
    send_packet(state, Message.to_packet(message))
  end

  defp send_packet(%State{} = state, %Packet{} = packet) do
    GenServer.cast(state.connection_pid, {:write_packet, packet})
    state
  end

  defp create_update?(%UpdateObject{update_type: update_type, object: %{guid: guid}})
       when update_type in [:create_object, :create_object2] and is_integer(guid) do
    Guid.entity_type(guid) != :item
  end

  defp create_update?(%UpdateObject{}), do: false

  defp duplicate_create?(%State{} = state, %UpdateObject{object: %{guid: guid}} = update) do
    create_update?(update) and Visibility.tracked?(state, guid)
  end

  defp track_updates(%State{} = state, updates) do
    Enum.reduce(updates, state, &track_update/2)
  end

  defp track_update(%UpdateObject{update_type: :out_of_range_objects, out_of_range_guids: guids}, state) do
    Enum.reduce(guids, state, &Visibility.untrack_entity(&2, &1))
  end

  defp track_update(%UpdateObject{} = update, state) do
    state = QuestGivers.remember(state, update)
    if create_update?(update), do: Visibility.track_entities(state, MapSet.new([update.object.guid])), else: state
  end

  defp source_tracked?(_state, nil), do: true

  defp source_tracked?(%State{} = state, source_guid) when is_integer(source_guid) do
    Visibility.tracked?(state, source_guid)
  end

  defp source_tracked?(_state, _source_guid), do: false
end
