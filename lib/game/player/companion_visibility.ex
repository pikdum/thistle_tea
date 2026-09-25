defmodule ThistleTea.Game.Player.CompanionVisibility do
  @moduledoc """
  Connection projection for companion visibility and client controls.

  It owns the protocol-sensitive create, pet-bar, clear, and post-teleport
  restoration ordering.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner.Attachment
  alias ThistleTea.Game.Entity.Server.Player.PacketSink
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World.Visibility

  def prepare_attachment(%State{} = state, %Attachment{create: %UpdateObject{} = create}) do
    PacketSink.ensure_created(state, create)
  end

  def prepare_attachment(%State{} = state, %Attachment{}), do: state

  def finish_attachment(%State{} = state, %Attachment{kind: :possession, entity_ref: ref, spells: spells}) do
    Network.send_packet(Message.SmsgPetSpells.for_possession(ref.guid, spells))
    state
  end

  def finish_attachment(%State{} = state, %Attachment{entity_ref: ref, pid: pid} = attachment) do
    companion = Companion.relationship(state.character)
    request = {:restore, companion.action_bar, companion.autocast}

    case Entity.call(pid, {:pet_controls, state.guid, request}) do
      {:ok, spells, control} ->
        character = Companion.remember_controls(state.character, ref.guid, control)
        Network.send_packet(Message.SmsgPetSpells.for_pet(ref.guid, spells, control))
        send_name_response(attachment.name_response)
        %{state | character: character}

      _ ->
        state
    end
  end

  def clear(%State{} = state) do
    Network.send_packet(Message.SmsgPetSpells.clear())
    state
  end

  def release_control(%State{active_mover_guid: guid} = state, guid)
      when is_integer(guid) and guid > 0 and guid != state.guid do
    Network.send_packet(%Message.SmsgClientControlUpdate{guid: guid, allow_movement?: false})
    character = state.character
    character = %{character | player: %{character.player | farsight: 0}} |> Core.mark_broadcast_update()

    %{state | character: character, active_mover_guid: state.guid}
    |> Visibility.reset_viewpoint()
  end

  def release_control(%State{} = state, _guid), do: state

  def defer_restoration(%State{} = state) do
    send(self(), :restore_companion)
    state
  end

  defp send_name_response(%Message.SmsgPetNameQueryResponse{pet_number: number} = packet)
       when is_integer(number) and number > 0, do: Network.send_packet(packet)

  defp send_name_response(_missing), do: :ok
end
