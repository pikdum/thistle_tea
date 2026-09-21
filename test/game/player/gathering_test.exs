defmodule ThistleTea.Game.Player.GatheringTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Gathering, as: GatheringState
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot, as: InternalLoot
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Lock
  alias ThistleTea.Game.Entity.Data.Lock.Requirement
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.ItemLoot, as: PendingItemLoot
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.LootSession
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Server.GameObject, as: GameObjectServer
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.GameObjects
  alias ThistleTea.Game.Player.Gathering
  alias ThistleTea.Game.Player.Looting
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: TemplateLoader
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Lock, as: LockLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  @moduletag :namigator_maps

  @entry 999_881
  @lock 999_882
  @tool 999_883
  @ore 999_884
  @spell 999_885

  setup [:gathering_node]

  describe "complete/4" do
    test "settles an earlier item-loot window before planning the new inventory", %{
      state: state,
      node: node,
      spell: spell
    } do
      source = ItemStore.create(%ItemTemplate{entry: 999_887}, owner: state.guid)
      loot = %Loot{gold: 0, items: [%Loot.Item{slot: 0, item_id: @ore, count: 1, display_id: 1, quality: 1}]}

      character = %{
        state.character
        | internal: %{state.character.internal | item_loot: PendingItemLoot.new(source, loot)}
      }

      state = %{state | character: character, loot_guid: source.object.guid, loot_type: :item}
      opened = Gathering.complete(state, node, spell, nil)
      assert opened.loot_guid == node
      assert opened.character.internal.item_loot == nil
      assert Inventory.count_entry(opened.character.player, @ore, &ItemStore.get/1) == 1
      assert CharacterStore.get(state.guid).player.inv2 == opened.character.player.inv2
    end

    test "typed completion grants loot and one stored skill point", %{state: state, node: node, spell: spell} do
      assert Looting.open(state, node).loot_guid == nil
      assert GameObjects.use_object(state, node) == state
      EventSink.emit(state.character, [%Effects.OpenLock{target_guid: node, spell: spell}], Context.new(self()))
      assert_receive {:open_lock, ^node, ^spell, nil} = command
      assert {:noreply, opened} = PlayerServer.handle_info(command, state)
      assert opened.loot_guid == node
      assert opened.character.player.skills[186].value == 2
      assert CharacterStore.get(state.guid).player.skills == opened.character.player.skills
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgLootResponse{guid: ^node, loot_type: 2}}}
      closed = Looting.release(opened)
      assert Looting.open(closed, node).loot_guid == nil
      reopened = Gathering.complete(closed, node, spell, nil)
      assert reopened.character.player.skills[186].value == 2
      claimed = Looting.take_item(reopened, 0)
      assert Inventory.count_entry(claimed.character.player, @ore, &ItemStore.get/1) == 1
      assert Looting.take_item(claimed, 0).character.player == claimed.character.player
    end

    test "rechecks range, world, skill and tools at completion", %{state: state, node: node, spell: spell} do
      player = state.character.player

      :ets.insert(
        LockLoader,
        {@lock, %Lock{id: @lock, requirements: [%Requirement{type: :skill, index: 3, skill: 50}]}}
      )

      assert Gathering.complete(state, node, spell, nil) == state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{reason: 0x2C}}}
      :ets.insert(LockLoader, {@lock, lock()})

      for character <- [
            %{state.character | player: %{player | inv1: 0}},
            %{state.character | unit: %{state.character.unit | health: 0}},
            %{state.character | internal: %{state.character.internal | world: WorldRef.open(1)}},
            %{state.character | movement_block: %MovementBlock{position: {-8940.0, -132.493, 83.53, 0.0}}}
          ] do
        changed = %{state | character: character}
        assert Gathering.complete(changed, node, spell, nil) == changed
      end

      assert Looting.open(state, node).loot_guid == nil
    end

    test "item-based opening consumes a charge only after success and never grants skill", %{state: state, node: node} do
      key =
        ItemStore.create(%ItemTemplate{entry: 999_886, spellid_1: @spell, spelltrigger_1: 0, spellcharges_1: -1},
          owner: state.guid
        )

      player = %{state.character.player | inv2: key.object.guid}
      state = %{state | character: %{state.character | player: player}}
      spell = %Spell{id: @spell, effects: [%Effect{type: :open_lock, misc_value: 3, base_points: -1}]}
      :ets.insert(LockLoader, {@lock, %Lock{id: @lock, requirements: [%Requirement{type: :skill, index: 3, skill: 1}]}})
      assert Gathering.complete(state, node, spell, key.object.guid) == state
      assert ItemStore.get(key.object.guid) == key

      spell = %{spell | effects: [%Effect{type: :open_lock, misc_value: 3, base_points: 99}]}
      opened = Gathering.complete(state, node, spell, key.object.guid)
      assert opened.loot_guid == node
      assert ItemStore.get(key.object.guid) == nil
      assert opened.character.player.skills[186].value == 1
      assert Gathering.complete(opened, node, spell, key.object.guid) == opened
    end
  end

  describe "loot lifecycle" do
    test "movement and logout release node access without discarding remaining loot", %{
      state: state,
      node: node,
      spell: spell
    } do
      opened = Gathering.complete(state, node, spell, nil)
      moved = %{opened.character | movement_block: %MovementBlock{position: {-8940.0, -132.493, 83.53, 0.0}}}
      assert Looting.close_unavailable(%{opened | character: moved}).loot_guid == nil
      reopened = Gathering.complete(%{opened | loot_guid: nil, loot_type: nil}, node, spell, nil)
      assert reopened.loot_guid == node
      assert State.leave_world(reopened).character == nil
      object = :sys.get_state(Entity.pid(node))
      assert object.internal.gathering.opened_by == %{}
      assert LootSession.viewers(object.internal.loot.session) == []
      refute LootSession.finished?(object.internal.loot.session)
    end
  end

  describe "context/4" do
    test "feeds the same lock rules into pre-cast validation", %{state: state, node: node, spell: spell} do
      targets = Target.object(node, :locked)
      context = Gathering.context(state, spell, targets, nil)
      assert CastValidation.validate(state.character, spell, targets, nil, 0, lock_context: context) == :ok
      wrong = %{spell | effects: [%Effect{type: :open_lock, misc_value: 2, base_points: 24}]}

      assert CastValidation.validate(state.character, wrong, targets, nil, 0, lock_context: context) ==
               {:error, :bad_targets}

      assert CastValidation.validate(state.character, spell, targets, nil, 0) == {:error, :bad_targets}
    end
  end

  defp gathering_node(_context) do
    low = System.unique_integer([:positive, :monotonic])
    guid = Guid.from_low_guid(:game_object, @entry, low)
    position = {-8949.95, -132.493, 83.53, 0.0}
    tool = ItemStore.create(%ItemTemplate{entry: @tool}, owner: low)
    :ets.insert(TemplateLoader, {@entry, %GameObjectTemplate{entry: @entry, type: 3, data: [@lock]}})
    :ets.insert(LockLoader, {@lock, lock()})
    :ets.insert(ItemLoader, {@ore, %ItemTemplate{entry: @ore, stackable: 20}})

    object = %GameObject{
      object: %Object{guid: guid, entry: @entry},
      movement_block: %MovementBlock{position: position},
      internal: %Internal{
        gathering: %GatheringState{lock_id: @lock, min_uses: 2, max_uses: 4},
        loot: %InternalLoot{
          id: 1,
          session:
            LootSession.new(
              %Loot{gold: 0, items: [%Loot.Item{slot: 0, item_id: @ore, count: 1, display_id: 1, quality: 1}]},
              nil
            )
        }
      }
    }

    start_supervised!({GameObjectServer, object})

    character = %Character{
      id: low,
      object: %Object{guid: low},
      unit: %Unit{health: 100, max_health: 100, level: 10},
      movement_block: %MovementBlock{position: position},
      internal: %Internal{},
      player: %Player{inv1: tool.object.guid, skills: Skills.learn_rank(%{}, 186, 75)}
    }

    CharacterStore.put(character)

    on_exit(fn ->
      :ets.delete(TemplateLoader, @entry)
      :ets.delete(LockLoader, @lock)
      :ets.delete(ItemLoader, @ore)
      :ets.delete(CharacterStore, low)
      Metadata.delete(guid)
      Metadata.delete(low)
      SpatialHash.remove(:game_objects, guid)
      :ets.select_delete(ItemStore, [{{:_, :"$1"}, [{:==, {:map_get, :owner, {:map_get, :item, :"$1"}}, low}], [true]}])
    end)

    %{
      state: %State{guid: low, character: character},
      node: guid,
      spell: %Spell{id: @spell, tools: [@tool], effects: [%Effect{type: :open_lock, misc_value: 3, base_points: 24}]}
    }
  end

  defp lock, do: %Lock{id: @lock, requirements: [%Requirement{type: :skill, index: 3, skill: 0}]}
end
