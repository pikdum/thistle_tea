defmodule ThistleTea.Game.Player.CompanionVisibility do
  @moduledoc """
  Connection projection for companion visibility and client controls.

  It owns the protocol-sensitive create, pet-bar, clear, and post-teleport
  restoration ordering.
  """

  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner.Attachment
  alias ThistleTea.Game.Entity.Server.Player.PacketSink
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.UpdateObject

  def prepare_attachment(%State{} = state, %Attachment{create: %UpdateObject{} = create}) do
    PacketSink.ensure_created(state, create)
  end

  def prepare_attachment(%State{} = state, %Attachment{}), do: state

  def finish_attachment(%State{} = state, %Attachment{entity_ref: entity_ref, spells: spells}) do
    Network.send_packet(Message.SmsgPetSpells.for_pet(entity_ref.guid, spells))
    state
  end

  def clear(%State{} = state) do
    Network.send_packet(Message.SmsgPetSpells.clear())
    state
  end

  def defer_restoration(%State{} = state) do
    send(self(), :restore_companion)
    state
  end
end
