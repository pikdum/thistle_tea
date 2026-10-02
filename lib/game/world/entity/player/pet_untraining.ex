defmodule ThistleTea.Game.World.Entity.Player.PetUntraining.Offer do
  @moduledoc false
  @enforce_keys [:pet_guid, :cost]
  defstruct @enforce_keys
end

defmodule ThistleTea.Game.World.Entity.Player.PetUntraining do
  @moduledoc """
  Pet-trainer confirmation and owner-serialized payment for a live pet reset.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.Entity, as: EntityCore
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.NpcReach
  alias ThistleTea.Game.World.Entity.Player.PetUntraining.Offer
  alias ThistleTea.Game.World.Entity.Player.Reputation
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Loader.Gossip
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Outbound

  def available?(%Character{unit: %{class: 3}} = character, trainer_guid) do
    Gossip.pet_trainer?(World.entry(trainer_guid)) and match?({:ok, _cost}, current_price(character))
  end

  def available?(_character, _trainer), do: false

  def confirm(%State{ready: true, character: %Character{unit: %{class: 3}} = character} = state, trainer_guid) do
    with true <- valid_trainer?(character, trainer_guid),
         {:ok, cost} <- current_price(character) do
      guid = Companion.summon_guid(character)
      Outbound.send_packet(%Message.SmsgGossipComplete{})
      Outbound.send_packet(%Message.SmsgPetUnlearnConfirm{pet_guid: guid, cost: cost})
      %{state | pet_unlearn_offer: %Offer{pet_guid: guid, cost: cost}, gossip_menu_options: []}
    else
      _ -> %{state | pet_unlearn_offer: nil}
    end
  end

  def confirm(state, _trainer), do: state

  def complete(
        %State{
          ready: true,
          character: %Character{} = character,
          pet_unlearn_offer: %Offer{pet_guid: guid, cost: maximum_cost}
        } = state,
        guid
      ) do
    state = %{state | pet_unlearn_offer: nil}

    if Companion.summon_guid(character) == guid do
      case Entity.call(guid, {:unlearn_pet, character.object.guid, character.player.coinage, maximum_cost}) do
        {:ok, cost, progress, spells, control} ->
          character = Companion.capture_progress(character, progress)
          character = Companion.remember_controls(character, guid, control)

          character = %{
            character
            | player: %{character.player | coinage: character.player.coinage - cost}
          }

          character = EntityCore.mark_broadcast_update(character)
          CharacterStore.put(character)
          Outbound.send_packet(Message.SmsgPetSpells.for_pet(guid, spells, control))
          %{state | character: character}

        {:error, :not_enough_money} ->
          Outbound.send_packet(%Message.SmsgBuyFailed{vendor_guid: 0, item_id: 0, error: :not_enough_money})
          state

        _ ->
          state
      end
    else
      state
    end
  end

  def complete(%State{} = state, _guid), do: %{state | pet_unlearn_offer: nil}

  defp current_price(character) do
    case Companion.summon_guid(character) do
      guid when is_integer(guid) and guid > 0 -> Entity.call(guid, {:pet_unlearn_cost, character.object.guid})
      _ -> {:error, :no_pet}
    end
  end

  defp valid_trainer?(character, guid) do
    with false <- EntityCore.dead?(character),
         :mob <- Guid.entity_type(guid),
         true <- Gossip.pet_trainer?(World.entry(guid)),
         %{alive?: true, npc_flags: flags} when is_integer(flags) <- Metadata.query(guid, [:alive?, :npc_flags]),
         true <- (flags &&& 0x10) != 0,
         true <- Reputation.can_interact?(character, guid),
         true <- NpcReach.within?(character, guid) do
      true
    else
      _ -> false
    end
  end
end
