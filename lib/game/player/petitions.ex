defmodule ThistleTea.Game.Player.Petitions do
  @moduledoc """
  Player-owner charter requests. The petition system owns signatures, the
  guild system owns membership, and inventory changes commit through one plan.
  """

  import Bitwise, only: [&&&: 2, |||: 2]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet.Placement
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Guild
  alias ThistleTea.Game.Guild.Petitions, as: PetitionLogic
  alias ThistleTea.Game.Guild.Petitions.Petition
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgGuildCommandResult
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Player.Guilds
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Guild, as: GuildSystem
  alias ThistleTea.Game.World.System.Petition, as: PetitionSystem

  @charter_entry 5863
  @charter_cost 1000
  @petitioner_flag 0x200
  @tabard_designer_flag 0x400

  def show_list(%{ready: true, character: %Character{} = character} = state, npc_guid) do
    if petitioner?(character, npc_guid) do
      Network.send_packet(%Message.SmsgPetitionShowlist{npc_guid: npc_guid})
    end

    state
  end

  def show_list(state, _npc_guid), do: state

  def buy(%{ready: true, guid: guid, character: %Character{} = character} = state, npc_guid, name)
      when is_binary(name) do
    name = String.trim(name)
    existing = PetitionSystem.by_owner(guid)

    if existing && not owner_has_charter?(existing) do
      PetitionSystem.delete(existing.item_guid)
    end

    if petitioner?(character, npc_guid, @petitioner_flag ||| @tabard_designer_flag) do
      buy_at_vendor(state, guid, character, npc_guid, name)
    else
      state
    end
  end

  def buy(state, _npc_guid, _name), do: state

  defp buy_at_vendor(state, guid, character, npc_guid, name) do
    cond do
      GuildSystem.group_of(guid) != nil -> state
      PetitionSystem.by_owner(guid) != nil -> state
      not Guild.valid_name?(name) -> guild_error(name, :invalid_name, state)
      GuildSystem.group_by_name(name) != nil -> guild_error(name, :name_exists, state)
      character.player.coinage < @charter_cost -> buy_error(npc_guid, :not_enough_money, state)
      true -> buy_charter(state, npc_guid, name)
    end
  end

  defp buy_charter(state, npc_guid, name) do
    case ItemLoader.get_template(@charter_entry) do
      %ItemTemplate{} = template -> plan_charter(state, name, template)
      nil -> buy_error(npc_guid, :cant_find_item, state)
    end
  end

  defp plan_charter(state, name, template) do
    item = ItemStore.prepare(template, owner: state.guid)
    petition_id = Guid.low_guid(item.object.guid)
    item = %{item | item: %{item.item | enchantment: petition_id}}
    player = %{state.character.player | coinage: state.character.player.coinage - @charter_cost}
    batch = Batch.new(player) |> Batch.add(item)

    case Inventory.plan(batch, &ItemStore.get/1) do
      {:ok, changes} ->
        commit_charter(state, name, item, changes)

      {:error, reason} ->
        InventoryUpdate.send_failure(reason, 0, 0)
        state
    end
  end

  defp commit_charter(state, name, item, changes) do
    account_id = state.character.account_id || Guid.low_guid(state.guid)

    case PetitionSystem.create(
           Guilds.member(state.character),
           account_id,
           item.object.guid,
           Guid.low_guid(item.object.guid),
           name
         ) do
      {:ok, _petition} ->
        %Placement{position: position} = ChangeSet.placement(changes, item.object.guid)
        state = InventoryUpdate.apply(state, {:ok, changes})
        Items.send_push_result(state, @charter_entry, 1, position, 1)
        state

      {:error, reason} ->
        guild_error(name, reason, state)
    end
  end

  def show_signatures(%{ready: true} = state, item_guid) do
    case PetitionSystem.by_item(item_guid) do
      %Petition{} = petition ->
        if owns_charter?(state.character, item_guid) do
          Network.send_packet(%Message.SmsgPetitionShowSignatures{petition: petition})
        end

      nil ->
        :ok
    end

    state
  end

  def show_signatures(state, _item_guid), do: state

  def query(state, petition_id, item_guid) do
    case PetitionSystem.by_id(petition_id) do
      %Petition{item_guid: ^item_guid} = petition ->
        Network.send_packet(%Message.SmsgPetitionQueryResponse{petition: petition})

      _ ->
        :ok
    end

    state
  end

  def offer(%{ready: true, guid: guid, character: %Character{} = character} = state, item_guid, target_guid) do
    with %Petition{owner: %{guid: ^guid}} = petition <- PetitionSystem.by_item(item_guid),
         true <- owns_charter?(character, item_guid),
         true <- Entity.online?(target_guid),
         %Character{} = target <- CharacterStore.get(Guid.low_guid(target_guid)),
         true <- Party.same_team?(character.unit.race, target.unit.race),
         nil <- GuildSystem.group_of(target_guid),
         false <- GuildSystem.invited?(target_guid) do
      Network.send_packet(%Message.SmsgPetitionShowSignatures{petition: petition}, target_guid)
    end

    state
  end

  def offer(state, _item_guid, _target_guid), do: state

  def sign(%{ready: true, guid: guid, character: %Character{} = character} = state, item_guid) do
    case PetitionSystem.by_item(item_guid) do
      %Petition{} = petition ->
        sign_known_petition(state, character, guid, petition)

      nil ->
        state
    end
  end

  def sign(state, _item_guid), do: state

  defp sign_known_petition(state, character, guid, petition) do
    cond do
      not owner_has_charter?(petition) ->
        PetitionSystem.delete(petition.item_guid)
        state

      GuildSystem.group_of(guid) != nil ->
        sign_result(state, petition.item_guid, guid, :already_in_guild)

      GuildSystem.invited?(guid) ->
        Network.send_packet(%SmsgGuildCommandResult{
          command: :invite,
          name: character.internal.name,
          result: :already_invited
        })

        state

      true ->
        sign_valid_petition(state, character, guid, petition)
    end
  end

  defp sign_valid_petition(state, character, guid, petition) do
    account_id = character.account_id || Guid.low_guid(guid)

    case PetitionSystem.sign(petition.item_guid, Guilds.member(character), account_id) do
      {:ok, _petition} ->
        Network.send_packet(
          %Message.SmsgPetitionSignResults{item_guid: petition.item_guid, signer_guid: guid, result: :ok},
          petition.owner.guid
        )

        sign_result(state, petition.item_guid, guid, :ok)

      {:error, :wrong_faction} ->
        guild_error("", :wrong_faction, state)

      {:error, :complete} ->
        sign_result(state, petition.item_guid, guid, :already_signed)

      {:error, reason} when reason in [:cant_sign_own, :already_signed] ->
        sign_result(state, petition.item_guid, guid, reason)

      {:error, _reason} ->
        state
    end
  end

  defp sign_result(state, item_guid, signer_guid, result) do
    Network.send_packet(%Message.SmsgPetitionSignResults{
      item_guid: item_guid,
      signer_guid: signer_guid,
      result: result
    })

    state
  end

  def decline(%{ready: true, guid: guid} = state, item_guid) do
    case PetitionSystem.by_item(item_guid) do
      %Petition{} = petition ->
        Network.send_packet(%Message.MsgPetitionDeclineServer{signer_guid: guid}, petition.owner.guid)

      nil ->
        :ok
    end

    state
  end

  def decline(state, _item_guid), do: state

  def rename(%{ready: true, guid: guid, character: %Character{} = character} = state, item_guid, name) do
    if owns_charter?(character, item_guid) do
      case GuildSystem.group_by_name(name) do
        nil -> rename_available(state, item_guid, guid, name)
        _ -> guild_error(name, :name_exists, state)
      end
    else
      state
    end
  end

  def rename(state, _item_guid, _name), do: state

  defp rename_available(state, item_guid, guid, name) do
    case PetitionSystem.rename(item_guid, guid, name) do
      {:ok, petition} ->
        Network.send_packet(%Message.MsgPetitionRenameServer{item_guid: item_guid, name: petition.name})
        state

      {:error, :invalid_name} ->
        guild_error(name, :invalid_name, state)

      {:error, _reason} ->
        state
    end
  end

  def turn_in(%{ready: true, guid: guid, character: %Character{} = character} = state, item_guid) do
    with %Petition{owner: %{guid: ^guid}} = petition <- PetitionSystem.by_item(item_guid),
         true <- owns_charter?(character, item_guid) do
      turn_in_owned(state, petition)
    else
      _ -> state
    end
  end

  def turn_in(state, _item_guid), do: state

  defp turn_in_owned(state, petition) do
    cond do
      GuildSystem.group_of(state.guid) != nil -> turn_in_result(state, :already_in_guild)
      not PetitionLogic.complete?(petition) -> turn_in_result(state, :need_more)
      true -> create_guild_from_petition(state, petition)
    end
  end

  defp create_guild_from_petition(state, petition) do
    batch = Batch.new(state.character.player) |> Batch.consume_item(petition.item_guid, 1)

    with {:ok, changes} <- Inventory.plan(batch, &ItemStore.get/1),
         {:ok, group} <-
           GuildSystem.create_from_petition(
             Guilds.member(state.character),
             PetitionLogic.signers(petition),
             petition.name
           ) do
      state = InventoryUpdate.apply(state, {:ok, changes})
      {:ok, _petition} = PetitionSystem.delete(petition.item_guid)
      state = Guilds.charter_created(state, group)
      turn_in_result(state, :ok)
    else
      {:error, :need_more} -> turn_in_result(state, :need_more)
      {:error, :already_in_guild} -> turn_in_result(state, :already_in_guild)
      {:error, :name_exists} -> guild_error(petition.name, :name_exists, state)
      {:error, _reason} -> state
    end
  end

  defp turn_in_result(state, result) do
    Network.send_packet(%Message.SmsgTurnInPetitionResults{result: result})
    state
  end

  defp owns_charter?(%Character{} = character, item_guid) do
    case ItemStore.get(item_guid) do
      %Item{object: %{entry: @charter_entry}, item: %{owner: owner}} when owner == character.object.guid ->
        Inventory.find_position(character.player, item_guid, &ItemStore.get/1) != nil

      _ ->
        false
    end
  end

  defp owner_has_charter?(%Petition{} = petition) do
    case CharacterStore.get(Guid.low_guid(petition.owner.guid)) do
      %Character{} = character -> owns_charter?(character, petition.item_guid)
      _ -> false
    end
  end

  defp petitioner?(character, npc_guid, required_flags \\ @petitioner_flag) do
    with true <- Death.alive?(character),
         :mob <- Guid.entity_type(npc_guid),
         %{alive?: true, npc_flags: flags} when is_integer(flags) <- Metadata.query(npc_guid, [:alive?, :npc_flags]),
         true <- (flags &&& required_flags) == required_flags,
         true <- Reputation.can_interact?(character, npc_guid),
         world = character.internal.world,
         {^world, _x, _y, _z} <- World.position(npc_guid),
         distance when is_number(distance) and distance <= 5.0 <- World.distance_between(character, npc_guid) do
      true
    else
      _ -> false
    end
  end

  defp guild_error(name, reason, state) do
    Network.send_packet(%SmsgGuildCommandResult{command: :create, name: name, result: reason})
    state
  end

  defp buy_error(npc_guid, reason, state) do
    Network.send_packet(%Message.SmsgBuyFailed{vendor_guid: npc_guid, item_id: @charter_entry, error: reason})
    state
  end
end
