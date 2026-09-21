defmodule ThistleTea.Game.Player.GameObjectQuestsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.GameObject
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.QuestDialogStatus
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Server.Player.PacketSink
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Player.Gossip
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: TemplateLoader
  alias ThistleTea.Game.World.Loader.Gossip, as: GossipLoader
  alias ThistleTea.Game.World.Loader.Gossip.Menu
  alias ThistleTea.Game.World.Loader.Gossip.Option
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility
  alias ThistleTea.Game.World.Visibility.QuestGivers
  alias ThistleTea.Game.WorldRef

  setup [:questgiver]

  describe "quest object activation" do
    test "personalizes create and values packets without changing shared flags", context do
      update = object_update(context)
      state = %{context.state | connection_pid: self()}
      eligible = PacketSink.send(state, update)
      expected = %{update | game_object: %{update.game_object | dyn_flags: 1}}
      packet = UpdateObject.to_packet([expected], state.guid)
      assert_received {:"$gen_cast", {:write_packet, ^packet}}
      assert eligible.quest_object_flags == %{context.object_guid => 1}

      character = state.character
      character = %{character | player: %{character.player | rewarded_quests: MapSet.new([context.quest.id])}}
      ineligible = PacketSink.send(%{state | character: character}, update)
      assert ineligible.quest_object_flags == %{context.object_guid => 0}
      packet = UpdateObject.to_packet([%{update | game_object: %{update.game_object | dyn_flags: 0}}], state.guid)
      assert_received {:"$gen_cast", {:write_packet, ^packet}}

      values = %{update | update_type: :values, game_object: %GameObject{state: 1}}
      assert QuestGivers.personalize(values, state.character).game_object.dyn_flags == 1
      assert update.game_object.flags == 4
      assert update.game_object.dyn_flags == nil
    end

    test "refreshes accepted and abandoned quests and forgets objects that leave view", context do
      :ets.delete(QuestLoader, {:ender, :game_object, context.template.entry})
      state = PacketSink.send(%{context.state | connection_pid: self()}, object_update(context))
      assert_received {:"$gen_cast", {:write_packet, _}}
      QuestGivers.refresh(state)
      refute_received {:"$gen_cast", {:send_packet, _, _}}

      {:ok, quest_log} = QuestLog.add(state.character.player.quest_log, context.quest, 0, 0)
      character = %{state.character | player: %{state.character.player | quest_log: quest_log}}
      state = QuestGivers.refresh(%{state | character: character})
      assert_received {:"$gen_cast", {:send_packet, %UpdateObject{game_object: %{dyn_flags: 0}} = update, opts}}
      state = PacketSink.send(state, update, opts)
      assert_received {:"$gen_cast", {:write_packet, _}}
      assert state.quest_object_flags == %{context.object_guid => 0}
      QuestGivers.refresh(state)
      refute_received {:"$gen_cast", {:send_packet, _, _}}

      state = QuestGivers.refresh(%{state | character: context.state.character})
      assert_received {:"$gen_cast", {:send_packet, %UpdateObject{game_object: %{dyn_flags: 1}}, _}}
      state = Visibility.untrack_entity(state, context.object_guid)
      assert state.quest_object_flags == %{}
      QuestGivers.refresh(state)
      refute_received {:"$gen_cast", {:send_packet, _, _}}
      assert PacketSink.ensure_created(state, object_update(context)).quest_object_flags == %{context.object_guid => 1}
    end

    test "keeps incomplete and complete turn-ins active but excludes failed quests", context do
      :ets.delete(QuestLoader, {:giver, :game_object, context.template.entry})
      {:ok, log} = QuestLog.add(context.state.character.player.quest_log, context.quest, 0, 0)

      for status <- [:incomplete, :complete, :failed] do
        log = Map.new(log, fn {slot, entry} -> {slot, %{entry | status: status}} end)
        character = context.state.character
        character = %{character | player: %{character.player | quest_log: log}}
        flags = QuestGivers.personalize(object_update(context), character).game_object.dyn_flags
        assert flags == if(status == :failed, do: 0, else: 1)
      end
    end

    test "respects minimum levels and live required conditions", context do
      character = context.state.character
      quest = %{context.quest | min_level: 51}
      put_quest(quest)
      assert QuestGivers.personalize(object_update(context), character).game_object.dyn_flags == 0

      put_quest(%{
        quest
        | min_level: 1,
          required_condition_id: 1,
          required_condition: %Condition{entry: 1, type: :level, value1: 51, value2: 1}
      })

      assert QuestGivers.personalize(object_update(context), character).game_object.dyn_flags == 0
      character = %{character | unit: %{character.unit | level: 51}}
      assert QuestGivers.personalize(object_update(context), character).game_object.dyn_flags == 1
    end
  end

  defp object_update(context) do
    %UpdateObject{
      update_type: :create_object2,
      object_type: :game_object,
      object: %Object{guid: context.object_guid, entry: context.template.entry},
      game_object: %GameObject{flags: 4, type_id: 2},
      movement_block: %MovementBlock{update_flag: 0}
    }
  end

  describe "use_object/2" do
    test "opens the native details through the game-object use codec", context do
      guid = context.object_guid
      message = Message.CmsgGameobjUse.from_binary(<<guid::little-size(64)>>)
      assert Message.CmsgGameobjUse.handle(message, context.state) == context.state

      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgQuestgiverQuestDetails{npc_guid: ^guid, quest: quest}}}
      assert quest.id == context.quest.id
      assert Quests.dialog_status(guid, context.state.character) == QuestDialogStatus.available()
    end

    test "keeps creature and game-object relation namespaces separate", context do
      other = put_quest(%Quest{id: context.quest.id + 1, title: "Creature Quest"})
      :ets.insert(QuestLoader, {{:giver, context.template.entry}, [other.id]})
      npc = Guid.from_low_guid(:mob, context.template.entry, 1)
      assert {[%Quest{id: id}], []} = Quests.npc_quests(npc)
      assert id == other.id
      assert {[quest], [quest]} = Quests.npc_quests(context.object_guid)
      assert quest.id == context.quest.id
      assert Quests.accept(context.state, context.object_guid, other.id) == context.state
      refute_received {:"$gen_cast", {:start_script, _, _}}
    end

    test "uses expanded display bounds beyond origin distance", context do
      template = %{context.template | bounds: {{-1.0, -1.0, -1.0}, {10.0, 1.0, 1.0}}}
      :ets.insert(TemplateLoader, {template.entry, template})
      state = position(context.state, {12.0, 0.0, 0.0, 0.0})
      accepted = Quests.accept(state, context.object_guid, context.quest.id)
      assert QuestLog.active?(accepted.character.player.quest_log, context.quest.id)
    end
  end

  describe "accept/3" do
    test "grants the source item and dispatches the start script to the object owner", context do
      state = Quests.accept(context.state, context.object_guid, context.quest.id)
      assert count(state, context.source.entry) == 1
      assert QuestLog.get(state.character.player.quest_log, context.quest.id).status == :complete
      assert_received {:"$gen_cast", {:start_script, [%ScriptStep{command: :talk}], guid}}
      assert guid == state.guid
    end

    test "rejects absent, despawned, distant, wrong-type, and cross-instance sources", context do
      for state <- [position(context.state, {20.0, 0.0, 0.0, 0.0}), world(context.state, WorldRef.instance(0, 99))] do
        assert Quests.accept(state, context.object_guid, context.quest.id) == state
      end

      Metadata.update(context.object_guid, %{go_spawned?: false})
      assert Quests.accept(context.state, context.object_guid, context.quest.id) == context.state
      Metadata.update(context.object_guid, %{go_spawned?: true, go_type: 3})
      assert Quests.accept(context.state, context.object_guid, context.quest.id) == context.state
      Metadata.update(context.object_guid, %{go_type: 2})
      Entity.unregister(context.object_guid)
      assert Quests.accept(context.state, context.object_guid, context.quest.id) == context.state
      assert count(context.state, context.source.entry) == 0
      refute_received {:"$gen_cast", {:start_script, _, _}}
    end

    test "rechecks distance after presenting details", context do
      Quests.query_quest(context.state, context.object_guid, context.quest.id)
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgQuestgiverQuestDetails{}}}
      far = position(context.state, {20.0, 0.0, 0.0, 0.0})
      assert Quests.accept(far, context.object_guid, context.quest.id) == far
      assert count(far, context.source.entry) == 0
    end

    test "rejects dead, ghost, and taxi passengers", context do
      character = context.state.character

      for character <- [
            %{character | unit: %{character.unit | health: 0}},
            %{character | player: %{character.player | flags: 0x10}},
            %{character | internal: %{character.internal | taxi_flight: %{}}}
          ] do
        state = %{context.state | character: character}
        assert Quests.accept(state, context.object_guid, context.quest.id) == state
      end
    end

    test "applies the same live and distance validation to creature acceptance", context do
      npc_guid = Guid.from_low_guid(:mob, context.template.entry, 1)
      npc = %{context.object | object: %{context.object.object | guid: npc_guid}}
      :ets.insert(QuestLoader, {{:giver, context.template.entry}, [context.quest.id]})
      Entity.register(npc_guid)
      World.update_position(npc, :mobs)
      Metadata.put(npc_guid, %{alive?: true, npc_flags: 2})

      on_exit(fn ->
        Metadata.delete(npc_guid)
        World.remove_position(npc, :mobs)
      end)

      far = position(context.state, {20.0, 0.0, 0.0, 0.0})
      assert Quests.accept(far, npc_guid, context.quest.id) == far
      Metadata.update(npc_guid, %{npc_flags: 0})
      assert Quests.accept(context.state, npc_guid, context.quest.id) == context.state
      Metadata.update(npc_guid, %{npc_flags: 2, alive?: false})
      assert Quests.accept(context.state, npc_guid, context.quest.id) == context.state
      Metadata.update(npc_guid, %{alive?: true})
      accepted = Quests.accept(context.state, npc_guid, context.quest.id)
      assert QuestLog.active?(accepted.character.player.quest_log, context.quest.id)
    end
  end

  describe "choose_reward/4" do
    test "consumes objectives, grants rewards, runs the end script, and offers the object chain", context do
      next = put_quest(%Quest{id: context.quest.id + 1, title: "Next", prev_quest_id: context.quest.id})
      quest = put_quest(%{context.quest | next_quest_in_chain: next.id})
      :ets.insert(QuestLoader, {{:giver, :game_object, context.template.entry}, [quest.id, next.id]})
      state = Quests.accept(context.state, context.object_guid, quest.id)
      Quests.complete_quest(state, context.object_guid, quest.id)
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgQuestgiverRequestItems{completable: true}}}
      Quests.request_reward(state, context.object_guid, quest.id)
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgQuestgiverOfferReward{}}}

      rewarded = Quests.choose_reward(state, context.object_guid, quest.id, 0)
      assert rewarded.character.player.coinage == 125
      assert MapSet.member?(rewarded.character.player.rewarded_quests, quest.id)
      refute QuestLog.active?(rewarded.character.player.quest_log, quest.id)
      assert count(rewarded, context.source.entry) == 0
      assert count(rewarded, context.reward.entry) == 1
      assert_received {:"$gen_cast", {:start_script, [%ScriptStep{command: :emote}], _}}
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgQuestgiverQuestDetails{quest: ^next}}}
      assert Quests.choose_reward(rewarded, context.object_guid, quest.id, 0) == rewarded
    end

    test "rejects a stale source and rewards while dead", context do
      accepted = Quests.accept(context.state, context.object_guid, context.quest.id)
      character = accepted.character
      dead = %{accepted | character: %{character | unit: %{character.unit | health: 0}}}
      assert Quests.choose_reward(dead, context.object_guid, context.quest.id, 0) == dead
      elsewhere = world(accepted, WorldRef.instance(0, 1))
      assert Quests.choose_reward(elsewhere, context.object_guid, context.quest.id, 0) == elsewhere
      Entity.unregister(context.object_guid)
      assert Quests.choose_reward(accepted, context.object_guid, context.quest.id, 0) == accepted
      assert count(accepted, context.reward.entry) == 0
    end
  end

  describe "hello_game_object/2" do
    test "dismounts through the shared aura lifecycle unless the template permits mounts", context do
      mount = %Spell{id: 1, effects: [%Effect{index: 0, type: :apply_aura, aura: :mounted, misc_value: 2404}]}
      {character, _effects} = Aura.apply_spell(context.state.character, context.state.guid, 50, mount, 1000)
      state = %{context.state | character: character}
      assert character.unit.mount_display_id == 2404
      dismounted = Gossip.hello_game_object(state, context.object_guid)
      assert dismounted.character.unit.mount_display_id == 0
      refute Aura.has_spell?(dismounted.character, 1)

      template = %{context.template | data: [0, 0, 0, 0, 0, 0, 0, 0, 1]}
      :ets.insert(TemplateLoader, {template.entry, template})
      assert Gossip.hello_game_object(state, context.object_guid).character.unit.mount_display_id == 2404
    end

    test "rejects disabled objects without granting use credit or opening a dialog", context do
      Metadata.update(context.object_guid, %{go_flags: 0x10})
      assert Gossip.hello_game_object(context.state, context.object_guid) == context.state
      refute_received {:"$gen_cast", {:send_packet, _}}
    end

    test "shows conditioned object gossip, excludes NPC services, and binds selections to the source", context do
      steps = [%ScriptStep{command: :talk}]
      option = %Option{id: 0, option_id: 1, npc_flag: 1, text: "Read", action_menu_id: -1, action_steps: steps}
      vendor = %Option{id: 1, option_id: 3, npc_flag: 0, text: "Vendor"}
      menu = %Menu{menu_id: context.template.entry, text_id: 68, options: [option, vendor]}
      put_menu(context, menu)

      state = Gossip.hello_game_object(context.state, context.object_guid)
      assert state.gossip_menu_guid == context.object_guid
      assert state.gossip_menu_options == [option]
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgGossipMessage{quests: [_], gossips: [_]}}}
      assert Gossip.select(state, context.object_guid + 1, 0) == state
      refute_received {:"$gen_cast", {:start_script, _, _}}
      assert %{gossip_menu_options: []} = Gossip.select(state, context.object_guid, 0)
      assert_received {:"$gen_cast", {:start_script, ^steps, _}}
    end

    test "revalidates distance and option conditions before executing object gossip", context do
      option = %Option{
        id: 0,
        option_id: 1,
        npc_flag: 1,
        text: "Read",
        action_menu_id: -1,
        action_steps: [%ScriptStep{command: :talk}],
        condition: %Condition{entry: 1, type: :level, value1: 50, value2: 1}
      }

      put_menu(context, %Menu{menu_id: context.template.entry, text_id: 68, options: [option]})
      state = Gossip.hello_game_object(context.state, context.object_guid)
      far = position(state, {20.0, 0.0, 0.0, 0.0})
      assert Gossip.select(far, context.object_guid, 0) == far
      character = state.character
      low = %{state | character: %{character | unit: %{character.unit | level: 1}}}
      assert Gossip.select(low, context.object_guid, 0) == low
      refute_received {:"$gen_cast", {:start_script, _, _}}
    end
  end

  defp put_menu(context, menu) do
    template = %{context.template | data: [0, 0, 0, menu.menu_id]}
    :ets.insert(TemplateLoader, {template.entry, template})
    :ets.insert(GossipLoader, {{:menu, menu.menu_id}, menu})
  end

  defp put_quest(quest) do
    :ets.insert(QuestLoader, {{:quest, quest.id}, quest})
    quest
  end

  defp position(state, position) do
    character = state.character
    %{state | character: %{character | movement_block: %{character.movement_block | position: position}}}
  end

  defp world(state, world) do
    character = state.character
    %{state | character: %{character | internal: %{character.internal | world: world}}}
  end

  defp count(state, entry), do: Inventory.count_entry(state.character.player, entry, &ItemStore.get/1)

  defp questgiver(_context) do
    guid = System.unique_integer([:positive, :monotonic])
    entry = 3_000_000 + guid * 10
    template = %GameObjectTemplate{entry: entry, type: 2, size: 1.0, data: [0, 0, 0, 0]}
    object_guid = Guid.from_low_guid(:game_object, entry, 1)
    source = %ItemTemplate{entry: entry + 3, name: "Source"}
    reward = %ItemTemplate{entry: entry + 4, name: "Reward"}
    :ets.insert(TemplateLoader, {entry, template})
    Enum.each([source, reward], &:ets.insert(ItemLoader, {&1.entry, &1}))

    quest =
      put_quest(%Quest{
        id: entry,
        title: "Object Quest",
        src_item_id: source.entry,
        src_item_count: 1,
        required_items: [{0, source.entry, 1}],
        request_items_text: "Bring the source",
        reward_money: 125,
        reward_items: [{reward.entry, 1}],
        start_script_steps: [%ScriptStep{command: :talk}],
        complete_script_steps: [%ScriptStep{command: :emote}]
      })

    :ets.insert(QuestLoader, {{:giver, :game_object, entry}, [quest.id]})
    :ets.insert(QuestLoader, {{:ender, :game_object, entry}, [quest.id]})

    character = %Character{
      id: guid,
      object: %Object{guid: guid},
      unit: %Unit{race: 1, class: 1, level: 50, health: 100, max_health: 100},
      player: %Player{coinage: 0, xp: 0, next_level_xp: 0},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    object = %{
      object: %Object{guid: object_guid},
      internal: character.internal,
      movement_block: character.movement_block
    }

    Entity.register(object_guid)
    World.update_position(object, :game_objects)
    Metadata.put(object_guid, %{go_type: 2, go_spawned?: true, go_rotation: {0.0, 0.0, 0.0, 1.0}, go_scale: 1.0})
    CharacterStore.put(character)

    on_exit(fn ->
      :ets.delete(TemplateLoader, entry)
      :ets.delete(GossipLoader, {:menu, entry})
      Enum.each([source, reward], &:ets.delete(ItemLoader, &1.entry))
      Enum.each([entry, entry + 1], &:ets.delete(QuestLoader, {:quest, &1}))

      for role <- [:giver, :ender] do
        :ets.delete(QuestLoader, {role, :game_object, entry})
        :ets.delete(QuestLoader, {role, entry})
      end

      :ets.delete(CharacterStore, guid)
      Metadata.delete(guid)
      Metadata.delete(object_guid)
      World.remove_position(object, :game_objects)
      for {item_guid, %{item: %{owner: ^guid}}} <- :ets.tab2list(ItemStore), do: ItemStore.delete(item_guid)
    end)

    %{
      state: %State{guid: guid, character: character, ready: true},
      object: object,
      object_guid: object_guid,
      template: template,
      quest: quest,
      source: source,
      reward: reward
    }
  end
end
