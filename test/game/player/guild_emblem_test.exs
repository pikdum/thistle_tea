defmodule ThistleTea.Game.Player.GuildEmblemTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Reputation
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Guilds
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.Guild, as: GuildSystem
  alias ThistleTea.Game.WorldRef

  describe "activate_tabard/2" do
    test "opens only at a nearby tabard designer", %{founder: founder, vendor: vendor} do
      assert Guilds.activate_tabard(founder, vendor) == founder
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgTabardvendorActivateServer{vendor_guid: ^vendor}}}

      SpatialHash.update(:mobs, vendor, WorldRef.open(1), 40.0, 0.0, 0.0)
      assert Guilds.activate_tabard(founder, vendor) == founder
      refute_receive {:"$gen_cast", {:send_packet, %Message.MsgTabardvendorActivateServer{}}}
    end
  end

  describe "save_emblem/3" do
    test "charges the leader and publishes the updated guild", %{founder: founder, vendor: vendor, name: name} do
      emblem = {3, 4, 5, 6, 7}
      founder = Guilds.create(founder, name)
      saved = Guilds.save_emblem(founder, vendor, emblem)
      group = GuildSystem.group_of(founder.guid)

      assert group.emblem == emblem
      assert saved.character.player.coinage == 100_000
      assert CharacterStore.get(founder.character.id).player.coinage == 100_000
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgSaveGuildEmblemServer{result: :ok}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGuildQueryResponse{guild: ^group}}}
    end

    test "rejects nonleaders, invalid vendors, colors, and insufficient money", %{
      founder: founder,
      vendor: vendor,
      name: name
    } do
      emblem = {3, 4, 5, 6, 7}
      assert Guilds.save_emblem(founder, vendor, emblem) == founder
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgSaveGuildEmblemServer{result: :not_in_guild}}}

      founder = Guilds.create(founder, name)
      target = state(System.unique_integer([:positive]), "Member", 200_000)
      {:ok, _group} = GuildSystem.invite(founder.guid, Guilds.member(target.character))
      {:ok, _group} = GuildSystem.accept(Guilds.member(target.character))
      on_exit(fn -> :ets.delete(CharacterStore, target.character.id) end)

      assert Guilds.save_emblem(target, vendor, emblem) == target
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgSaveGuildEmblemServer{result: :not_leader}}}

      SpatialHash.update(:mobs, vendor, WorldRef.open(1), 40.0, 0.0, 0.0)
      assert Guilds.save_emblem(founder, vendor, emblem) == founder
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgSaveGuildEmblemServer{result: :invalid_vendor}}}
      SpatialHash.update(:mobs, vendor, WorldRef.open(1), 2.0, 0.0, 0.0)

      assert Guilds.save_emblem(founder, vendor, {300, 4, 5, 6, 7}) == founder
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgSaveGuildEmblemServer{result: :invalid_emblem}}}

      poor = %{founder | character: %{founder.character | player: %{founder.character.player | coinage: 99_999}}}
      assert Guilds.save_emblem(poor, vendor, emblem) == poor
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgSaveGuildEmblemServer{result: :not_enough_money}}}
      assert GuildSystem.group_of(founder.guid).emblem == {0, 0, 0, 0, 0}
    end
  end

  setup do
    id = System.unique_integer([:positive])
    vendor = Guid.from_low_guid(:mob, id, id)
    founder = state(id, "Founder#{id}", 200_000)
    name = "Guild#{id}"
    Metadata.put(vendor, %{alive?: true, npc_flags: 0x400})
    SpatialHash.update(:mobs, vendor, WorldRef.open(1), 2.0, 0.0, 0.0)
    {:ok, _} = Entity.register(founder.guid)

    on_exit(fn ->
      GuildSystem.disband(founder.guid)
      Entity.unregister(founder.guid)
      Metadata.delete(vendor)
      SpatialHash.remove(:mobs, vendor)
      :ets.delete(CharacterStore, id)
    end)

    %{founder: founder, vendor: vendor, name: name}
  end

  defp state(id, name, coinage) do
    character =
      CharacterStore.put(%Character{
        id: id,
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

    %State{guid: character.object.guid, character: character, ready: true}
  end
end
