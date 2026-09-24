defmodule ThistleTea.Game.Player.CompanionVisibility do
  @moduledoc """
  Connection projection for companion visibility and client controls.

  It owns the protocol-sensitive create, pet-bar, clear, and post-teleport
  restoration ordering.
  """

  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner.Attachment
  alias ThistleTea.Game.Entity.Server.Player.PacketSink
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
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

  def finish_attachment(%State{} = state, %Attachment{entity_ref: entity_ref, pid: pid, spells: spells} = attachment) do
    autocast = Companion.autocast(state.character)
    if Guid.entity_type(entity_ref.guid) == :mob, do: send(pid, {:pet_restore_autocast, autocast})
    packet = Message.SmsgPetSpells.for_pet(entity_ref.guid, spells, autocast)
    reaction = Companion.relationship(state.character).reaction_state
    Network.send_packet(%{packet | reaction_state: reaction_code(reaction)})
    send_name_response(attachment.name_response)
    state
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

  defp reaction_code(:passive), do: 0
  defp reaction_code(:defensive), do: 1
  defp reaction_code(:aggressive), do: 2
end
