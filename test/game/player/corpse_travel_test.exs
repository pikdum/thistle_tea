defmodule ThistleTea.Game.Player.CorpseTravelTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.AreaTriggerTeleport
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Data.CorpseReclaim
  alias ThistleTea.Game.Entity.Data.Dungeon
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.AreaTriggers
  alias ThistleTea.Game.Player.Corpses
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.AreaTrigger
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.System.Instance
  alias ThistleTea.Game.WorldRef

  @dungeon 900_021
  @parent 900_022
  @other 900_023
  @trigger 900_024

  setup [:build_spirit_run]

  describe "location/2" do
    test "shows the entrance outside and the body inside", %{state: state} do
      height = fn 0, {10.0, 20.0} -> 42.0 end

      assert Corpses.location(state.character, height) == %Message.MsgCorpseQueryResponse{
               map: 0,
               position: {10.0, 20.0, 42.0},
               corpse_map: @dungeon
             }

      inside = put_in(state.character.internal.world, WorldRef.instance(@dungeon, 1))

      assert Corpses.location(inside.character, fn _, _ -> flunk("height queried inside") end) ==
               %Message.MsgCorpseQueryResponse{
                 map: @dungeon,
                 position: {5.0, 6.0, 7.0},
                 corpse_map: @dungeon
               }

      World.stop_entity(Corpse.guid_for(state.guid))
      assert Corpses.location(state.character, height) == %Message.MsgCorpseQueryResponse{}
    end
  end

  describe "portal_destination/2" do
    test "routes a parent portal to the inner entrance", %{state: state, teleport: teleport} do
      inner = %{teleport | target_map: @dungeon, x: 99.0}
      :ets.insert(AreaTrigger, {{:entrance, @dungeon}, inner})
      assert Corpses.portal_destination(state, %{teleport | target_map: @parent}) == {:ok, inner}
    end
  end

  describe "handle/2" do
    test "revives at the correct portal and returns to the original copy", %{state: state, world: original_world} do
      restored = AreaTriggers.handle(state, @trigger)
      refute Death.ghost?(restored.character)
      assert restored.character.unit.health == 50
      assert restored.character.internal.corpse_reclaim.released_at == nil
      assert Entity.pid(Corpse.guid_for(state.guid)) == nil
      assert_receive {:"$gen_cast", {:start_teleport, 1.0, 2.0, 3.0, +0.0, %WorldRef{map_id: @dungeon} = world}}
      assert Instance.info(state.guid).current == world
      assert world == original_world
    end

    test "rejects unrelated and missing corpses without changing admission", %{state: state, teleport: teleport} do
      :ets.insert(AreaTrigger, {{:teleport, @trigger}, %{teleport | target_map: @other}})
      assert AreaTriggers.handle(state, @trigger) == state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgAreaTriggerMessage{message: message}}}
      assert message == "You cannot enter Other Dungeon while in ghost form."
      assert Entity.pid(Corpse.guid_for(state.guid))
      World.stop_entity(Corpse.guid_for(state.guid))
      :ets.insert(AreaTrigger, {{:teleport, @trigger}, teleport})
      assert AreaTriggers.handle(state, @trigger) == state
      refute_receive {:"$gen_cast", {:start_teleport, _, _, _, _, _}}
      assert Instance.info(state.guid).current == nil
    end

    test "keeps the ghost when portal requirements fail", %{state: state, teleport: teleport} do
      :ets.insert(AreaTrigger, {{:teleport, @trigger}, %{teleport | required_level: 60, message: "Level 60 required"}})
      assert AreaTriggers.handle(state, @trigger) == state
      assert Entity.pid(Corpse.guid_for(state.guid))
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgAreaTriggerMessage{message: "Level 60 required"}}}
    end

    test "revives even if copy admission subsequently fails", %{state: state} do
      :ets.insert(MapTemplate, {@dungeon, 2, nil})
      restored = AreaTriggers.handle(state, @trigger)
      refute Death.ghost?(restored.character)
      assert restored.character.unit.health == 50
      assert Entity.pid(Corpse.guid_for(state.guid)) == nil
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgRaidGroupOnly{}}}
      refute_receive {:"$gen_cast", {:start_teleport, _, _, _, _, _}}
      assert Instance.info(state.guid).current == nil
    end
  end

  defp build_spirit_run(_context) do
    previous = :ets.lookup(MapTemplate, :dungeons)

    dungeons = %{
      @dungeon => %Dungeon{map_id: @dungeon, parent_map: @parent, ghost_entrance: {0, 10.0, 20.0}},
      @parent => %Dungeon{map_id: @parent},
      @other => %Dungeon{map_id: @other, name: "Other Dungeon"}
    }

    :ets.insert(MapTemplate, {:dungeons, dungeons})

    Enum.each([@dungeon, @parent, @other], fn map ->
      :ets.insert(MapTemplate, {map, 1, nil})
      :ets.insert(AreaTrigger, {{:instance_map, map}, true})
    end)

    teleport = %AreaTriggerTeleport{target_map: @dungeon, required_level: 1, x: 1.0, y: 2.0, z: 3.0, orientation: 0.0}
    trigger = %{map: 0, x: 0.0, y: 0.0, z: 0.0, radius: 5.0}

    :ets.insert(AreaTrigger, [
      {{:trigger, @trigger}, trigger},
      {{:quest, @trigger}, nil},
      {{:tavern, @trigger}, false},
      {{:teleport, @trigger}, teleport}
    ])

    guid = System.unique_integer([:positive]) + 30_000_000

    character = %Character{
      object: %Object{guid: guid},
      unit: %Unit{health: 1, max_health: 100, max_power1: 80, race: 1, gender: 0, level: 30, auras: []},
      player: %Player{flags: 0x10, skin: 0, face: 0, hair_style: 0, hair_color: 0, facial_hair: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{corpse_reclaim: %CorpseReclaim{expires_at: 600_000, released_at: 10_000}}
    }

    {:ok, world} = Instance.enter(@dungeon, guid)
    Instance.leave(guid, world)

    body = %{
      character
      | internal: %{character.internal | world: world},
        movement_block: %{character.movement_block | position: {5.0, 6.0, 7.0, 0.0}}
    }

    {:ok, _pid} = body |> Corpse.build([]) |> World.start_entity()
    on_exit(fn -> cleanup(character, previous) end)
    %{state: %State{guid: guid, ready: true, character: character}, teleport: teleport, world: world}
  end

  defp cleanup(character, previous) do
    guid = character.object.guid
    World.stop_entity(Corpse.guid_for(guid))
    World.remove_position(character)
    if world = Instance.info(guid).current, do: Instance.leave(guid, world)
    Instance.reset(guid)
    :ets.delete(MapTemplate, :dungeons)
    :ets.insert(MapTemplate, previous)

    Enum.each([@dungeon, @parent, @other], fn map ->
      :ets.delete(MapTemplate, map)
      :ets.delete(AreaTrigger, {:instance_map, map})
    end)

    Enum.each([:trigger, :quest, :tavern, :teleport], &:ets.delete(AreaTrigger, {&1, @trigger}))
    :ets.delete(AreaTrigger, {:entrance, @dungeon})
  end
end
