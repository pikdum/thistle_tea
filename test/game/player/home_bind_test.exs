defmodule ThistleTea.Game.Player.HomeBindTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.HomeBind, as: Home
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Player.HomeBind
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Gossip.Option
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  setup [:home_and_innkeeper]

  describe "confirm/2" do
    test "gossip requests confirmation without changing the home", %{state: state, guid: guid} do
      state = %{state | gossip_menu_options: [%Option{id: 2, option_id: 8}], gossip_menu_guid: guid}
      message = %Message.CmsgGossipSelectOption{guid: guid, gossip_list_id: 2}
      result = Message.CmsgGossipSelectOption.handle(message, state)

      assert result.character == state.character
      assert result.gossip_menu_options == []
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGossipComplete{}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgBinderConfirm{guid: ^guid} = packet}}
      assert Message.SmsgBinderConfirm.to_binary(packet) == <<guid::little-size(64)>>
      refute_received {:"$gen_cast", {:trigger_spell, _, _, _}}
      refute_received {:"$gen_cast", {:send_packet, %Message.SmsgBindpointupdate{}}}
    end
  end

  describe "activate/2" do
    test "dispatches the client confirmation to the innkeeper's bind spell", %{state: state, guid: guid} do
      message = Dispatch.to_message(Packet.build(<<guid::little-size(64)>>, 0x1B5))
      assert message == %Message.CmsgBinderActivate{guid: guid}
      assert Message.CmsgBinderActivate.handle(message, state).character == state.character
      player_guid = state.guid
      assert_receive {:"$gen_cast", {:trigger_spell, 3286, ^player_guid, []}}
    end

    test "revalidates the innkeeper after the confirmation dialog", %{state: state, guid: guid} do
      state = HomeBind.confirm(state, guid)
      SpatialHash.update(:mobs, guid, WorldRef.open(0), 5.01, 0.0, 0.0)
      assert HomeBind.activate(state, guid) == state
      refute_received {:"$gen_cast", {:trigger_spell, _, _, _}}
    end

    test "rejects a player who has not entered the world", %{state: state, guid: guid} do
      state = %{state | ready: false}
      assert HomeBind.activate(state, guid) == state
      assert HomeBind.confirm(state, guid) == state
      refute_received {:"$gen_cast", {:trigger_spell, _, _, _}}
      refute_received {:"$gen_cast", {:send_packet, _}}
    end
  end

  describe "complete/3" do
    test "stores the player's location and terrain area and sends both updates", %{state: state, guid: guid} do
      result = HomeBind.complete(state, guid, area_lookup: fn 0, {+0.0, +0.0, +0.0} -> {12, 87} end)
      home = %Home{map_id: 0, area_id: 87, position: {0.0, 0.0, 0.0}}

      assert result.character.internal.home_bind == home
      assert CharacterStore.get(state.character.id).internal.home_bind == home
      assert result.character.movement_block == state.character.movement_block

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgBindpointupdate{map: 0, area: 87, x: +0.0, y: +0.0, z: +0.0}}}

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPlayerbound{guid: ^guid, area: 87} = packet}}
      assert Message.SmsgPlayerbound.to_binary(packet) == <<guid::little-size(64), 87::little-size(32)>>
    end

    test "replaces the old home and falls back to the known area without terrain", %{state: state, guid: guid} do
      result = HomeBind.complete(state, guid, area_lookup: fn _, _ -> nil end)
      assert result.character.internal.home_bind == %Home{map_id: 0, area_id: 12, position: {0.0, 0.0, 0.0}}
    end

    test "rejects a delayed bind after the player dies or the innkeeper disappears", %{state: state, guid: guid} do
      dead = put_in(state.character.unit.health, 0)
      assert HomeBind.complete(dead, guid) == dead
      Metadata.delete(guid)
      assert HomeBind.complete(state, guid) == state
      refute_received {:"$gen_cast", {:send_packet, %Message.SmsgPlayerbound{}}}
    end
  end

  describe "valid_innkeeper?/2" do
    test "rejects dead or ghost players and dead or unflagged innkeepers", %{state: state, guid: guid} do
      character = state.character
      refute HomeBind.valid_innkeeper?(put_in(character.unit.health, 0), guid)
      refute HomeBind.valid_innkeeper?(put_in(character.player.flags, 0x10), guid)
      refute HomeBind.valid_innkeeper?(state.character, state.guid)
      Metadata.update(guid, %{alive?: false})
      refute HomeBind.valid_innkeeper?(state.character, guid)
      Metadata.update(guid, %{alive?: true, npc_flags: 0})
      refute HomeBind.valid_innkeeper?(state.character, guid)
    end

    test "rejects other maps and instance copies", %{state: state, guid: guid} do
      SpatialHash.update(:mobs, guid, WorldRef.open(1), 2.0, 0.0, 0.0)
      refute HomeBind.valid_innkeeper?(state.character, guid)
      world = WorldRef.instance(0, 1)
      SpatialHash.update(:mobs, guid, world, 2.0, 0.0, 0.0)
      character = state.character
      refute HomeBind.valid_innkeeper?(put_in(character.internal.world, world), guid)
    end

    test "rejects dungeon and battleground maps even without an instance id", %{state: state, guid: guid} do
      map_id = System.unique_integer([:positive, :monotonic]) + 100_000
      world = WorldRef.open(map_id)
      character = state.character
      character = put_in(character.internal.world, world)
      SpatialHash.update(:mobs, guid, world, 2.0, 0.0, 0.0)
      SpatialHash.update(:players, state.guid, world, 0.0, 0.0, 0.0)
      on_exit(fn -> :ets.delete(MapTemplate, map_id) end)

      for type <- [1, 2, 3] do
        :ets.insert(MapTemplate, {map_id, type, nil})
        refute HomeBind.valid_innkeeper?(character, guid)
      end
    end
  end

  describe "send_update/1" do
    test "projects the retained home while the character is elsewhere", %{state: state} do
      home = state.character.internal.home_bind
      HomeBind.send_update(state.character)

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgBindpointupdate{map: 1, area: 1637, x: 10.0, y: 20.0, z: 30.0}}}

      assert state.character.internal.home_bind == home
    end
  end

  describe "spell effects" do
    test "bind returns through the explicit player owner", %{state: state, guid: guid} do
      spell = %Spell{id: 3286, effects: [%Effect{type: :bind}]}
      {character, events} = SpellEffect.receive(state.character, %CastContext{caster_guid: guid}, spell, 0)
      assert character == state.character
      assert [%Effects.BindHome{binder_guid: ^guid}] = events
      owner = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(owner, :kill) end)
      EventSink.emit(character, events, Context.new(owner))
      assert {:messages, [{:"$gen_cast", {:bind_home, ^guid}}]} = Process.info(owner, :messages)
      refute_received {:"$gen_cast", {:bind_home, _}}
    end

    test "home-target spells resolve to the retained home across maps", %{state: state} do
      for id <- [556, 8690] do
        spell = %Spell{
          id: id,
          effects: [%Effect{type: :teleport_units, implicit_target_a: :caster, implicit_target_b: :home_bind}]
        }

        {character, events} = SpellEffect.receive(state.character, state.guid, spell, 0)
        assert [%Effects.TeleportHome{}] = events
        EventSink.emit(character, events, Context.new(self()))
        assert_receive {:"$gen_cast", {:start_teleport, 10.0, 20.0, 30.0, 1}}
      end
    end
  end

  defp home_and_innkeeper(_context) do
    id = System.unique_integer([:positive, :monotonic])
    guid = Guid.from_low_guid(:mob, 295, id)
    player_guid = Guid.from_low_guid(:player, id)
    {:ok, _player} = Entity.register(player_guid)
    {:ok, _innkeeper} = Entity.register(guid)
    Metadata.put(guid, %{npc_flags: 0x80, alive?: true})
    SpatialHash.update(:mobs, guid, WorldRef.open(0), 2.0, 0.0, 0.0)
    SpatialHash.update(:players, player_guid, WorldRef.open(0), 0.0, 0.0, 0.0)

    character = %Character{
      id: id,
      object: %Object{guid: player_guid},
      unit: %Unit{health: 100, max_health: 100, level: 1, auras: []},
      player: %Player{flags: 0, skills: %{}, quest_log: %{}, rewarded_quests: MapSet.new()},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 1.0}},
      internal: %Internal{
        world: WorldRef.open(0),
        area: 12,
        home_bind: %Home{map_id: 1, area_id: 1637, position: {10.0, 20.0, 30.0}}
      }
    }

    on_exit(fn ->
      Metadata.delete(guid)
      SpatialHash.remove(:mobs, guid)
      SpatialHash.remove(:players, player_guid)
      :ets.delete(CharacterStore, id)
    end)

    %{state: %State{ready: true, guid: player_guid, character: character}, guid: guid}
  end
end
