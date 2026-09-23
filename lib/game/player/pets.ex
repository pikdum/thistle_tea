defmodule ThistleTea.Game.Player.Pets do
  @moduledoc "Owner-serialized naming, abandonment, and name queries for controlled companions."

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion, as: CompanionData
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.PetName
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.CompanionVisibility
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility

  def rename(%{ready: true, character: %Character{} = character} = state, guid, name) do
    with %CompanionData{kind: :hunter_pet, status: {:active, %EntityRef{guid: ^guid}}, name: nil} <-
           Companion.relationship(character),
         {:ok, %PetName{} = identity} <- Entity.call(guid, {:rename_pet, character.object.guid, name}) do
      character = Companion.remember_name(character, guid, identity)
      CharacterStore.put(character)
      %{state | character: character}
    else
      {:error, :invalid_name} ->
        Network.send_packet(%Message.SmsgPetNameInvalid{})
        state

      _ ->
        state
    end
  end

  def rename(state, _guid, _name), do: state

  def abandon(%State{ready: true, character: %Character{} = character} = state, guid) do
    if Companion.controls?(character, guid) do
      state = state |> CompanionOwner.suspend() |> CompanionVisibility.clear()
      character = state.character |> Companion.clear() |> Core.mark_broadcast_update()
      CharacterStore.put(character)
      %{state | character: character}
    else
      state
    end
  end

  def abandon(state, _guid), do: state

  def query(%{ready: true, character: %Character{internal: %{world: world}}} = state, guid, number) do
    with {^world, _x, _y, _z} <- World.position(guid),
         true <- Visibility.can_see?(state, guid),
         %{name: name, pet_number: ^number, pet_name_timestamp: timestamp} <-
           Metadata.query(guid, [:name, :pet_number, :pet_name_timestamp]),
         true <- is_binary(name) and is_integer(timestamp) and number > 0 do
      Network.send_packet(%Message.SmsgPetNameQueryResponse{pet_number: number, name: name, timestamp: timestamp})
    end

    state
  end

  def query(state, _guid, _number), do: state
end
