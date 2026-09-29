defmodule ThistleTea.Game.World.Entity.Player.GameObjectsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.DBC
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.GameObjects
  alias ThistleTea.Game.World.Loader.Faction, as: FactionLoader
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Presence

  describe "open_object/2" do
    test "routes an open-lock completion through ordinary door use" do
      entry = System.unique_integer([:positive])
      guid = Guid.from_low_guid(:game_object, entry, System.unique_integer([:positive]))
      player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      template = %GameObjectTemplate{entry: entry, type: 0, size: 1.0, data: [0, 0]}
      :ets.insert(GameObjectTemplateLoader, {entry, template})
      Entity.register(player_guid)

      owner = start_game_object_owner(guid)

      on_exit(fn ->
        :ets.delete(GameObjectTemplateLoader, entry)
        Entity.unregister(player_guid)
        if Process.alive?(owner), do: Process.exit(owner, :kill)
      end)

      character = %Character{
        object: %Object{guid: player_guid},
        unit: %Unit{level: 10},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {1.0, 1.0, 3.0, 0.0}}
      }

      GameObjects.open_object(%{guid: player_guid, character: character}, guid)

      assert_receive {:"$gen_cast", {:gameobject_use, ^player_guid, 10}}
    end
  end

  describe "use_object/2" do
    test "sits the player in the seat returned by a chair game object" do
      entry = System.unique_integer([:positive])
      guid = Guid.from_low_guid(:game_object, entry, System.unique_integer([:positive]))
      player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      template = %GameObjectTemplate{entry: entry, type: 7, size: 1.0, data: [1, 1]}
      :ets.insert(GameObjectTemplateLoader, {entry, template})
      Entity.register(player_guid)

      owner = start_chair_owner(guid, {:ok, {1.0, 2.0, 3.0, 1.5}, 5})

      on_exit(fn ->
        :ets.delete(GameObjectTemplateLoader, entry)
        Entity.unregister(player_guid)
        if Process.alive?(owner), do: Process.exit(owner, :kill)
      end)

      character = %Character{
        object: %Object{guid: player_guid},
        unit: %Unit{level: 10, stand_state: 0},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {1.0, 1.0, 3.0, 0.0}}
      }

      state = GameObjects.use_object(%{guid: player_guid, character: character}, guid)

      assert state.character.unit.stand_state == 5
      assert_receive {:"$gen_cast", {:start_teleport, 1.0, 2.0, 3.0, 1.5, %WorldRef{map_id: 0}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgStandstateUpdate{stand_state: 5}}}
    end
  end

  describe "interactable?/2" do
    test "base and dropped flags require a nearby living player in the same world" do
      for type <- [24, 26] do
        entry = System.unique_integer([:positive])
        template = %GameObjectTemplate{entry: entry, type: type, size: 1.0, flags: 0}
        GameObjectTemplateLoader.put(template)
        world = WorldRef.instance(489, entry)
        object = GameObject.build_summoned(template, world, {0.0, 0.0, 0.0, 0.0})
        guid = object.object.guid
        World.update_position(object)
        Metadata.put(guid, %{go_spawned?: true, go_rotation: {0.0, 0.0, 0.0, 1.0}, go_scale: 1.0, go_flags: 0})

        on_exit(fn ->
          World.remove_position(object)
          Metadata.delete(guid)
          :ets.delete(GameObjectTemplateLoader, entry)
        end)

        character = %Character{
          object: %Object{guid: 1},
          unit: %Unit{health: 100, max_health: 100, auras: []},
          internal: %Internal{world: world},
          movement_block: %MovementBlock{position: {1.0, 0.0, 0.0, 0.0}}
        }

        assert GameObjects.interactable?(character, guid)
        refute GameObjects.interactable?(%{character | unit: %{character.unit | health: 0}}, guid)
        refute GameObjects.interactable?(%{character | unit: %{character.unit | mount_display_id: 1234}}, guid)

        refute GameObjects.interactable?(
                 %{character | internal: %{character.internal | world: %{world | instance_id: entry + 1}}},
                 guid
               )

        refute GameObjects.interactable?(
                 %{character | movement_block: %{character.movement_block | position: {100.0, 0.0, 0.0, 0.0}}},
                 guid
               )

        Metadata.update(guid, %{go_spawned?: false})
        refute GameObjects.interactable?(character, guid)
      end
    end

    test "spellcasting objects require a living nearby player and a nonhostile faction" do
      entry = System.unique_integer([:positive])
      template = %GameObjectTemplate{entry: entry, type: 22, size: 1.0, flags: 0, data: [30_238]}
      GameObjectTemplateLoader.put(template)
      object = GameObject.build_summoned(template, WorldRef.open(0), {0.0, 0.0, 0.0, 0.0})
      guid = object.object.guid
      World.update_position(object)
      alliance = %DBC.FactionTemplate{id: 1, faction: 1, faction_group: 3, friend_group: 2, enemy_group: 12}
      horde = %DBC.FactionTemplate{id: 2, faction: 2, faction_group: 5, friend_group: 4, enemy_group: 10}

      :ets.insert(
        FactionLoader,
        {entry, %{faction_template: alliance, faction_template_id: entry, faction_can_have_reputation?: false}}
      )

      Metadata.put(guid, %{
        go_spawned?: true,
        go_rotation: {0.0, 0.0, 0.0, 1.0},
        go_scale: 1.0,
        go_flags: 0,
        faction_template: alliance
      })

      character = %Character{
        object: %Object{guid: System.unique_integer([:positive])},
        player: %Player{},
        unit: %Unit{health: 100, max_health: 100, faction_template: entry},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {1.0, 0.0, 0.0, 0.0}}
      }

      Presence.enter(character, %{faction_template: alliance})

      on_exit(fn ->
        Presence.leave(character)
        World.remove_position(object)
        Metadata.delete(guid)
        :ets.delete(GameObjectTemplateLoader, entry)
        :ets.delete(FactionLoader, entry)
      end)

      assert GameObjects.interactable?(character, guid)
      refute GameObjects.interactable?(%{character | unit: %{character.unit | health: 0}}, guid)

      refute GameObjects.interactable?(
               %{character | movement_block: %{character.movement_block | position: {20.0, 0.0, 0.0, 0.0}}},
               guid
             )

      refute GameObjects.interactable?(%{character | internal: %{character.internal | world: WorldRef.open(1)}}, guid)
      Metadata.update(guid, %{faction_template: horde})
      refute GameObjects.interactable?(character, guid)
    end
  end

  defp start_game_object_owner(guid) do
    parent = self()

    spawn(fn ->
      {:ok, _owner} = Entity.register(guid)
      send(parent, :game_object_owner_ready)
      serve_game_object(parent)
    end)
    |> tap(fn _pid -> assert_receive :game_object_owner_ready end)
  end

  defp serve_game_object(parent) do
    receive do
      {:"$gen_cast", message} -> send(parent, {:"$gen_cast", message})
    end
  end

  defp start_chair_owner(guid, result) do
    parent = self()

    spawn(fn ->
      {:ok, _owner} = Entity.register(guid)
      send(parent, :chair_owner_ready)
      serve_chair(result)
    end)
    |> tap(fn _pid -> assert_receive :chair_owner_ready end)
  end

  defp serve_chair(result) do
    receive do
      {:"$gen_call", from, {:chair_seat, %WorldRef{map_id: 0}, {1.0, 1.0, 3.0}}} -> GenServer.reply(from, result)
    end
  end
end
