defmodule ThistleTea.Game.Player.PetUntraining.Offer do
  @moduledoc false
  @enforce_keys [:pet_guid, :cost]
  defstruct @enforce_keys
end

defmodule ThistleTea.Game.Player.PetUntraining do
  @moduledoc """
  Pet-trainer confirmation and owner-serialized payment for a live pet reset.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.PetUntraining.Offer
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Gossip
  alias ThistleTea.Game.World.Metadata

  def available?(%Character{unit: %{class: 3}} = character, trainer_guid) do
    Gossip.pet_trainer?(World.entry(trainer_guid)) and match?({:ok, _cost}, current_price(character))
  end

  def available?(_character, _trainer), do: false

  def confirm(%State{ready: true, character: %Character{unit: %{class: 3}} = character} = state, trainer_guid) do
    with true <- valid_trainer?(character, trainer_guid),
         {:ok, cost} <- current_price(character) do
      guid = Companion.summon_guid(character)
      Network.send_packet(%Message.SmsgGossipComplete{})
      Network.send_packet(%Message.SmsgPetUnlearnConfirm{pet_guid: guid, cost: cost})
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
          companion = %{Companion.relationship(character) | autocast: control.autocast}

          character = %{
            character
            | player: %{character.player | coinage: character.player.coinage - cost},
              internal: %{character.internal | companion: companion}
          }

          character = Core.mark_broadcast_update(character)
          CharacterStore.put(character)
          Network.send_packet(Message.SmsgPetSpells.for_pet(guid, spells, control))
          %{state | character: character}

        {:error, :not_enough_money} ->
          Network.send_packet(%Message.SmsgBuyFailed{vendor_guid: 0, item_id: 0, error: :not_enough_money})
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
    with false <- Core.dead?(character),
         :mob <- Guid.entity_type(guid),
         true <- Gossip.pet_trainer?(World.entry(guid)),
         %{alive?: true, npc_flags: flags} when is_integer(flags) <- Metadata.query(guid, [:alive?, :npc_flags]),
         true <- (flags &&& 0x10) != 0,
         true <- Reputation.can_interact?(character, guid),
         world = character.internal.world,
         {^world, _x, _y, _z} <- World.position(guid),
         distance when is_number(distance) and distance <= 5.0 <- World.distance_between(character, guid) do
      true
    else
      _ -> false
    end
  end
end
