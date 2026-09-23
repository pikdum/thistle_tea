defmodule ThistleTea.Game.Player.PetitionsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Reputation
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Guilds
  alias ThistleTea.Game.Player.Petitions
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.Guild, as: GuildSystem
  alias ThistleTea.Game.World.System.Petition, as: PetitionSystem
  alias ThistleTea.Game.WorldRef

  describe "buy/3" do
    test "purchases a named charter through one inventory plan", %{founder: founder, npc: npc, name: name} do
      assert Petitions.show_list(founder, npc) == founder
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetitionShowlist{npc_guid: ^npc}}}

      bought = Petitions.buy(founder, npc, name)
      assert bought.character.player.coinage == 4000
      [item] = Inventory.owned_items(bought.character.player, &ItemStore.get/1)
      assert item.object.entry == 5863
      petition = PetitionSystem.by_item(item.object.guid)
      assert petition.name == name
      assert item.item.enchantment == petition.id
      assert CharacterStore.get(founder.character.id).player.coinage == 4000
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgItemPushResult{item_id: 5863}}}

      assert Petitions.query(bought, petition.id, item.object.guid) == bought
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetitionQueryResponse{petition: ^petition}}}
      assert Petitions.show_signatures(bought, item.object.guid) == bought
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetitionShowSignatures{petition: ^petition}}}

      assert Petitions.buy(bought, npc, "Another Guild") == bought
      assert PetitionSystem.by_owner(founder.guid) == petition
    end

    test "rejects remote purchase and insufficient funds", %{founder: founder, npc: npc, name: name} do
      SpatialHash.update(:mobs, npc, WorldRef.open(1), 40.0, 0.0, 0.0)
      assert Petitions.buy(founder, npc, name) == founder
      assert PetitionSystem.by_owner(founder.guid) == nil

      SpatialHash.update(:mobs, npc, WorldRef.open(1), 2.0, 0.0, 0.0)
      poor = %{founder | character: %{founder.character | player: %{founder.character.player | coinage: 999}}}
      assert Petitions.buy(poor, npc, name) == poor
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgBuyFailed{error: :not_enough_money}}}
      assert PetitionSystem.by_owner(founder.guid) == nil
    end
  end

  describe "turn_in/2" do
    test "requires nine signatures and creates all guild members", %{founder: founder, npc: npc, name: name} do
      founder = Petitions.buy(founder, npc, name)
      [item] = Inventory.owned_items(founder.character.player, &ItemStore.get/1)

      assert Petitions.turn_in(founder, item.object.guid) == founder
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgTurnInPetitionResults{result: :need_more}}}

      signers = Enum.map(1..9, &signer/1)
      on_exit(fn -> Enum.each(signers, &:ets.delete(CharacterStore, &1.character.id)) end)

      Enum.each(signers, fn signer ->
        Petitions.sign(signer, item.object.guid)
        assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetitionSignResults{result: :ok}}}
      end)

      formed = Petitions.turn_in(founder, item.object.guid)
      group = GuildSystem.group_of(founder.guid)
      assert group.name == name
      assert map_size(group.members) == 10
      assert formed.character.player.guild_id == group.id
      assert formed.character.player.guild_rank == 0
      assert ItemStore.get(item.object.guid) == nil
      assert PetitionSystem.by_item(item.object.guid) == nil
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgTurnInPetitionResults{result: :ok}}}

      Enum.each(signers, fn signer ->
        assert GuildSystem.group_of(signer.guid) == group
        assert CharacterStore.get(signer.character.id).player.guild_id == group.id
        assert CharacterStore.get(signer.character.id).player.guild_rank == 4
      end)
    end
  end

  describe "sign/2" do
    test "refuses a signer with a pending guild invitation", %{founder: founder, npc: npc, name: name} do
      founder = Petitions.buy(founder, npc, name)
      [item] = Inventory.owned_items(founder.character.player, &ItemStore.get/1)
      inviter = signer(99)
      invitee = signer(100)

      on_exit(fn ->
        GuildSystem.disband(inviter.guid)
        :ets.delete(CharacterStore, inviter.character.id)
        :ets.delete(CharacterStore, invitee.character.id)
      end)

      assert {:ok, _group} = GuildSystem.create(Guilds.member(inviter.character), "Invitation#{inviter.character.id}")
      assert {:ok, _group} = GuildSystem.invite(inviter.guid, Guilds.member(invitee.character))
      assert Petitions.sign(invitee, item.object.guid) == invitee
      assert PetitionSystem.by_item(item.object.guid).signatures == %{}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGuildCommandResult{result: :already_invited}}}
    end
  end

  setup do
    suffix = System.unique_integer([:positive])
    id = System.unique_integer([:positive])
    npc = Guid.from_low_guid(:mob, id, id)
    character = character(id, "Founder#{suffix}", id, 5000)
    founder = %State{guid: character.object.guid, character: character, ready: true}
    name = "Charter#{suffix}"
    old_template = :ets.lookup(ItemLoader, 5863)
    :ets.insert(ItemLoader, {5863, %ItemTemplate{entry: 5863, stackable: 1}})
    Metadata.put(npc, %{alive?: true, npc_flags: 0x600})
    SpatialHash.update(:mobs, npc, WorldRef.open(1), 2.0, 0.0, 0.0)
    {:ok, _} = Entity.register(founder.guid)

    on_exit(fn ->
      case PetitionSystem.by_owner(founder.guid) do
        %{item_guid: item_guid} ->
          PetitionSystem.delete(item_guid)
          ItemStore.delete(item_guid)

        nil ->
          :ok
      end

      GuildSystem.disband(founder.guid)
      Entity.unregister(founder.guid)
      Metadata.delete(npc)
      SpatialHash.remove(:mobs, npc)
      :ets.delete(CharacterStore, id)
      :ets.delete(ItemLoader, 5863)
      Enum.each(old_template, &:ets.insert(ItemLoader, &1))
    end)

    %{founder: founder, npc: npc, name: name}
  end

  defp signer(index) do
    id = System.unique_integer([:positive])
    character = character(id, "Signer#{index}#{id}", id, 0)
    %State{guid: character.object.guid, character: character, ready: true}
  end

  defp character(id, name, account_id, coinage) do
    CharacterStore.put(%Character{
      id: id,
      account_id: account_id,
      object: %Object{guid: Guid.from_low_guid(:player, id)},
      unit: %Unit{race: 1, class: 1, level: 20, health: 100, max_health: 100},
      player: %Player{
        coinage: coinage,
        skills: %{},
        quest_log: %{},
        rewarded_quests: MapSet.new(),
        reputation: %Reputation{}
      },
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{name: name, world: WorldRef.open(1), spellbook: %{}}
    })
  end
end
