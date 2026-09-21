defmodule ThistleTea.Game.Player.Auction do
  @moduledoc """
  Authorizes live auctioneer interactions and projects committed auction
  receipts on the owning player. Login recovers any receipt left between the
  market commit and the owner's inventory projection.
  """
  import Bitwise, only: [band: 2]

  alias ThistleTea.Game.Entity.Data.Auction.House
  alias ThistleTea.Game.Entity.Data.Auction.Receipt
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Player.Auction.ClientProjection
  alias ThistleTea.Game.Player.Auction.Eligibility
  alias ThistleTea.Game.Player.ItemCosts
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.AuctionStore
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.AuctionHouse
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Auction, as: AuctionSystem

  @auctioneer_flag 0x00001000
  @interaction_distance 5.0

  def hello(%{ready: true, character: %Character{} = character} = state, guid) do
    case house(character, guid) do
      {:ok, house} ->
        {character, events} = Aura.remove_aura_types(character, [:feign_death], Time.now())
        character = character |> Effects.enqueue(events) |> EventSink.emit_pending()
        ClientProjection.hello(guid, house)
        %{state | character: character}

      :error ->
        state
    end
  end

  def hello(state, _guid), do: state

  def sell(state, message) do
    terms = %{start_bid: message.start_bid, buyout: message.buyout, duration_minutes: message.duration_minutes}
    transact(state, message.auctioneer, {:sell, message.item_guid, terms}, :started, 0)
  end

  def bid(state, message) do
    transact(state, message.auctioneer, {:bid, message.auction_id, message.price}, :bid_placed, message.auction_id)
  end

  def cancel(state, message) do
    transact(state, message.auctioneer, {:cancel, message.auction_id}, :removed, message.auction_id)
  end

  def search(%{ready: true, character: %Character{} = character} = state, message) do
    list(state, message.auctioneer, {:search, message.query, [usable: &Eligibility.usable?(character, &1)]}, :search)
  end

  def search(state, _message), do: state
  def owned(state, message), do: list(state, message.auctioneer, {:owned, state.guid, message.offset}, :owned)

  def bids(state, message),
    do: list(state, message.auctioneer, {:bids, state.guid, message.refresh_ids, message.offset}, :bids)

  def house(%Character{} = character, guid) do
    with true <- Death.alive?(character),
         :mob <- Guid.entity_type(guid),
         %{alive?: true, npc_flags: flags, faction_template: faction} <-
           Metadata.query(guid, [:alive?, :npc_flags, :faction_template]),
         true <- band(flags, @auctioneer_flag) != 0,
         true <- Reputation.can_interact?(character, guid),
         false <- Hostility.hostile?(character, guid),
         world = character.internal.world,
         {^world, _x, _y, _z} <- World.position(guid),
         distance when is_number(distance) and distance <= @interaction_distance <-
           World.distance_between(character, guid),
         %House{} = house <- AuctionHouse.for_faction(faction) do
      {:ok, house}
    else
      _ -> :error
    end
  end

  def recover(%Character{} = character) do
    case AuctionStore.pending(character.object.guid) do
      %Receipt{} = receipt -> character |> receipt_character(receipt) |> CharacterStore.put()
      nil -> character
    end
  end

  def finish_recovery(state) do
    case AuctionStore.pending(state.guid) do
      %Receipt{} = receipt -> acknowledge(state, receipt)
      nil -> state
    end
  end

  defp transact(%{ready: true, character: %Character{}} = state, guid, request, action, id) do
    state = state |> apply_pending() |> ItemCosts.settle()

    case house(state.character, guid) do
      {:ok, house} ->
        CharacterStore.put(state.character)
        result = request(state.character, house, request)

        case AuctionStore.pending(state.guid) do
          %Receipt{} ->
            apply_pending(state)

          nil ->
            ClientProjection.failure(id, action, result)
            state
        end

      :error ->
        state
    end
  end

  defp transact(state, _guid, _request, _action, _id), do: state

  defp request(character, house, request) do
    AuctionSystem.transact(character, house, request, Quests.quest_item_counts(character))
  catch
    :exit, _reason -> {:error, :database}
  end

  defp list(%{ready: true, character: %Character{} = character} = state, guid, request, kind) do
    case house(character, guid) do
      {:ok, house} -> ClientProjection.list(kind, AuctionSystem.list(house, request), Time.now())
      :error -> :ok
    end

    state
  end

  defp list(state, _guid, _request, _kind), do: state

  defp apply_pending(state) do
    case AuctionStore.pending(state.guid) do
      %Receipt{} = receipt ->
        state = project_receipt(state, receipt)
        CharacterStore.put(state.character)
        AuctionStore.acknowledge(receipt)
        ClientProjection.success(receipt)
        state

      nil ->
        state
    end
  end

  defp project_receipt(%{character: %{internal: %{last_auction_id: id}}} = state, %Receipt{id: id} = receipt) do
    Quests.on_inventory_changed(state, receipt.old_counts)
  end

  defp project_receipt(state, %Receipt{} = receipt) do
    state = %{state | character: receipt_character(state.character, receipt)}
    InventoryUpdate.apply_committed(state, receipt.changes, receipt.old_counts, receipt.outgoing)
  end

  defp acknowledge(state, %Receipt{} = receipt) do
    state = Quests.on_inventory_changed(state, receipt.old_counts)
    CharacterStore.put(state.character)
    AuctionStore.acknowledge(receipt)
    state
  end

  defp receipt_character(%Character{internal: %{last_auction_id: id}} = character, %Receipt{id: id}), do: character

  defp receipt_character(%Character{} = character, %Receipt{} = receipt) do
    %{character | player: receipt.changes.player, internal: %{character.internal | last_auction_id: receipt.id}}
  end
end
