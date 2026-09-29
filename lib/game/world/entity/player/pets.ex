defmodule ThistleTea.Game.World.Entity.Player.Pets do
  @moduledoc "Owner-serialized naming, abandonment, and name queries for controlled companions."

  alias ThistleTea.Game.Core.Entity, as: EntityCore
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Pet.Companion.EntityRef
  alias ThistleTea.Game.Core.Pet.PetName
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.CompanionOwner
  alias ThistleTea.Game.World.Entity.Player.CompanionVisibility
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility

  def rename(%{ready: true, character: %Character{} = character} = state, guid, name) do
    with %Companion{kind: :hunter_pet, status: {:active, %EntityRef{guid: ^guid}}, name: nil} <-
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

  def abandon(
        %State{
          ready: true,
          character:
            %Character{
              internal: %{
                companion: %Companion{kind: :possession, status: {:active, %EntityRef{guid: guid, spell_id: spell}}}
              }
            } = character
        } = state,
        guid
      ) do
    case Entity.pid(guid) do
      pid when is_pid(pid) -> send(pid, {:release_control, character.object.guid, spell})
      _missing -> :ok
    end

    state
  end

  def abandon(%State{ready: true, character: %Character{} = character} = state, guid) do
    if Companion.controls?(character, guid) do
      state = state |> CompanionOwner.suspend() |> CompanionVisibility.clear()
      character = state.character |> Companion.clear() |> EntityCore.mark_broadcast_update()
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
