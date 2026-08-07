defmodule ThistleTea.Game.Player.Bank do
  @moduledoc """
  Owner-local banker authorization and bank inventory orchestration.

  The stored banker GUID is only a capability hint. Every bank operation
  revalidates the live banker metadata, reputation, world, and distance before
  applying a pure inventory transition.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.BankBagSlotPrice
  alias ThistleTea.Game.World.Metadata

  @banker_flag 0x00000100
  @interaction_distance 5.0

  def activate(%State{ready: true, character: %Character{} = character} = state, banker_guid) do
    if valid_banker?(character, banker_guid) do
      Network.send_packet(%Message.SmsgShowBank{banker_guid: banker_guid})
      %{state | active_banker_guid: banker_guid}
    else
      %{state | active_banker_guid: nil}
    end
  end

  def activate(%State{} = state, _banker_guid), do: %{state | active_banker_guid: nil}

  def authorize(%State{ready: true, character: %Character{} = character, active_banker_guid: banker_guid} = state) do
    if valid_banker?(character, banker_guid) do
      {:ok, state}
    else
      {:error, %{state | active_banker_guid: nil}}
    end
  end

  def authorize(%State{} = state), do: {:error, %{state | active_banker_guid: nil}}

  def authorize(%State{} = state, banker_guid) do
    case activate_capability(state, banker_guid) do
      {:ok, state} -> {:ok, state}
      :error -> {:error, %{state | active_banker_guid: nil}}
    end
  end

  def authorize_positions(state, positions) when is_map(state) and is_list(positions) do
    if Inventory.touches_bank?(positions) do
      case state do
        %State{} -> authorize(state)
        _map -> {:error, Map.put(state, :active_banker_guid, nil)}
      end
    else
      {:ok, state}
    end
  end

  def auto_bank(%State{} = state, source_position) do
    auto_store(state, source_position, :bank)
  end

  def auto_store_bank(%State{} = state, source_position) do
    scope = if Inventory.bank_position?(source_position), do: :carried, else: :bank
    auto_store(state, source_position, scope)
  end

  def buy_slot(%State{} = state, banker_guid, opts \\ []) do
    price_lookup = Keyword.get(opts, :price_lookup, &BankBagSlotPrice.cost/1)

    case authorize(state, banker_guid) do
      {:ok, state} -> buy_authorized_slot(state, price_lookup)
      {:error, state} -> send_purchase_failure(state, 2)
    end
  end

  def valid_banker?(%Character{} = character, banker_guid) do
    with false <- Core.dead?(character),
         :mob <- Guid.entity_type(banker_guid),
         %{alive?: true, npc_flags: npc_flags} <- Metadata.query(banker_guid, [:alive?, :npc_flags]),
         true <- (npc_flags &&& @banker_flag) != 0,
         true <- Reputation.can_interact?(character, banker_guid),
         %{internal: %{world: world}} <- character,
         {^world, _x, _y, _z} <- World.position(banker_guid),
         distance when is_number(distance) and distance <= @interaction_distance <-
           World.distance_between(character, banker_guid) do
      true
    else
      _invalid -> false
    end
  end

  defp activate_capability(%State{ready: true, character: %Character{} = character} = state, banker_guid) do
    if valid_banker?(character, banker_guid) do
      {:ok, %{state | active_banker_guid: banker_guid}}
    else
      :error
    end
  end

  defp activate_capability(%State{}, _banker_guid), do: :error

  defp auto_store(%State{} = state, source_position, scope) do
    case authorize(state) do
      {:ok, state} ->
        state.character.player
        |> Inventory.auto_store(state.guid, source_position, scope, &ItemStore.get/1)
        |> then(&InventoryUpdate.apply(state, &1))

      {:error, state} ->
        InventoryUpdate.send_failure(:too_far_away_from_bank, 0, 0)
        state
    end
  end

  defp buy_authorized_slot(%State{} = state, price_lookup) do
    player = state.character.player
    slot = min(max(player.bank_bag_slots || 0, 0), 6) + 1

    case price_lookup.(slot) do
      nil ->
        send_purchase_failure(state, 0)

      price when player.coinage < price ->
        send_purchase_failure(state, 1)

      price ->
        player = %{player | bank_bag_slots: slot, coinage: player.coinage - price}
        InventoryUpdate.apply(state, {:ok, player})
    end
  end

  defp send_purchase_failure(state, result) do
    Network.send_packet(%Message.SmsgBuyBankSlotResult{result: result})
    state
  end
end
