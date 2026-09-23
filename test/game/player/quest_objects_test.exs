defmodule ThistleTea.Game.Player.QuestObjectsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Loot.Actor
  alias ThistleTea.Game.Entity.Logic.OpenLock
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Server.GameObject, as: GameObjectServer
  alias ThistleTea.Game.Entity.Server.GameObject.Goober, as: GooberServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Player.GameObjects
  alias ThistleTea.Game.Player.Gossip
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.EventScript, as: EventLoader
  alias ThistleTea.Game.World.Loader.GameObjectScript, as: ObjectScriptLoader
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: TemplateLoader
  alias ThistleTea.Game.World.Loader.Gossip, as: GossipLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility.QuestGivers
  alias ThistleTea.Game.WorldRef

  setup [:player]

  describe "use_object/2" do
    test "linked traps wait for quest admission after Opening", context do
      {guid, pid, quest} = spawn_object(context, %{0 => 99, 1 => 1})
      template = TemplateLoader.cached(quest.id)
      trap_template = %GameObjectTemplate{entry: quest.id + 1, type: 6, flags: 0, size: 1.0, data: [0, 0, 0, 0]}
      TemplateLoader.put(%{template | data: List.replace_at(template.data, 12, trap_template.entry)})
      trap = GameObject.build_summoned(trap_template, context.world, {1.1, 0.0, 0.0, 0.0})
      trap_pid = start_supervised!({GameObjectServer, trap}, id: trap.object.guid)
      ready_at = :sys.get_state(trap_pid).internal.trap.ready_at
      actor = %Actor{guid: context.state.guid, group_id: nil, needed_items: MapSet.new(), distance: 1.0}
      assert {:ok, :activate, false} = Entity.call(guid, {:open_lock, actor, %OpenLock{lock_id: 99}, false})
      assert :sys.get_state(trap_pid).internal.trap.ready_at == ready_at
      assert GameObjects.open_object(context.state, guid) == context.state
      assert :sys.get_state(trap_pid).internal.trap.ready_at == ready_at
      GameObjects.open_object(accept(context.state, quest), guid)
      assert :sys.get_state(pid).internal.object_action.active?
      assert :sys.get_state(trap_pid).internal.trap.ready_at > ready_at
    end

    test "reads a plain world text object", context do
      {guid, pid, _quest} = spawn_object(context, %{})
      object = :sys.get_state(pid)
      template = %{TemplateLoader.cached(Guid.entry(guid)) | type: 9, data: [731, 7, 2, 1]}
      TemplateLoader.put(template)
      assert GameObjects.use_object(context.state, guid) == context.state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGameobjectPagetext{guid: ^guid}}}
      assert :sys.get_state(pid).internal.object_action == object.internal.object_action
    end

    test "shows a page without granting inactive quest credit", context do
      {guid, pid, quest} = spawn_object(context, %{1 => 1, 7 => 12, 19 => 15})
      state = context.state
      assert GameObjects.use_object(state, guid) == state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGameobjectPagetext{guid: ^guid}}}
      refute :sys.get_state(pid).internal.object_action.active?
      refute_receive {:"$gen_cast", {:start_script, _, _}}, 10
      refute QuestLog.active?(state.character.player.quest_log, quest.id)
    end

    test "credits admitted use once and restores the object", context do
      {guid, pid, quest} = spawn_object(context, %{1 => 1, 2 => 1, 7 => 12})
      steps = [%ScriptStep{command: :emote, datalong: 1}]
      :ets.insert(EventLoader, {quest.id, steps})
      on_exit(fn -> :ets.delete(EventLoader, quest.id) end)
      state = accept(context.state, quest)
      updated = GameObjects.use_object(state, guid)
      assert QuestLog.get(updated.character.player.quest_log, quest.id).counts == %{0 => 1}
      assert_receive {:"$gen_cast", {:start_script, ^steps, ^guid}}
      entry = Bitwise.bor(Guid.entry(guid), 0x80000000)

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %Message.SmsgQuestupdateAddKill{creature_entry: ^entry, count: 1, victim_guid: ^guid} = packet}}

      assert <<_quest::little-32, ^entry::little-32, 1::little-32, 2::little-32, ^guid::little-64>> =
               Message.SmsgQuestupdateAddKill.to_binary(packet)

      assert :sys.get_state(pid).internal.object_action.active?
      assert Metadata.query(guid, [:go_state]) == %{go_state: 0}
      assert GameObjects.use_object(updated, guid) == updated
      revision = :sys.get_state(pid).internal.object_action.revision
      send(pid, {:finish_game_object_use, revision})
      refute :sys.get_state(pid).internal.object_action.active?
      assert Metadata.query(guid, [:go_state]) == %{go_state: 1}
    end

    test "rejects dead, distant, and foreign-instance users", context do
      {guid, pid, _} = spawn_object(context, %{7 => 12})
      state = context.state
      character = state.character

      for character <- [
            %{character | unit: %{character.unit | health: 0}},
            %{character | movement_block: %{character.movement_block | position: {99.0, 0.0, 0.0, 0.0}}},
            %{character | internal: %{character.internal | world: WorldRef.instance(999, 7)}}
          ] do
        state = %{state | character: character}
        assert GameObjects.use_object(state, guid) == state
      end

      refute :sys.get_state(pid).internal.object_action.active?
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgGameobjectPagetext{}}}, 10
      assert Entity.call(guid, {:use_goober, state.guid, WorldRef.instance(999, 7), true}) == :unavailable
    end

    test "casts object spells on the user with object attribution", context do
      {guid, pid, quest} = spawn_object(context, %{10 => 1})
      spell = %Spell{id: quest.id, effects: [%Effect{type: :heal, implicit_target_a: :any_unit, base_points: 10}]}
      :ets.insert(SpellLoader, {{:spell, quest.id}, spell})
      on_exit(fn -> :ets.delete(SpellLoader, {:spell, quest.id}) end)
      GameObjects.use_object(context.state, guid)
      assert :sys.get_state(pid).internal.object_action.active?
      user = context.state.guid
      assert_receive {:"$gen_cast", {:receive_spell, %{caster_guid: ^guid, target_guid: ^user}, ^spell}}
    end

    test "delayed object spells do not follow a user into another copy", context do
      {_guid, pid, _quest} = spawn_object(context, %{})
      object = :sys.get_state(pid)
      spell = %Spell{id: 1, effects: [%Effect{type: :heal, implicit_target_a: :any_unit}]}
      current = GooberServer.finish_spell(object, spell, context.state.guid)
      assert Enum.any?(current.internal.events, &match?(%Effects.DeliverSpell{}, &1))
      character = context.state.character
      World.update_position(%{character | internal: %{character.internal | world: WorldRef.instance(999, 7)}})
      assert GooberServer.finish_spell(object, spell, context.state.guid) == object
    end

    test "spell activation routes through the player quest checks", context do
      {guid, pid, _quest} = spawn_object(context, %{1 => 1, 7 => 12})
      send(pid, {:script_activate_object, context.state.guid})
      world = context.world
      assert_receive {:"$gen_cast", {:use_quest_object, ^guid, ^world}}
      assert GameObjects.use_quest_object(context.state, guid, world) == context.state
      refute :sys.get_state(pid).internal.object_action.active?
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGameobjectPagetext{guid: ^guid}}}
    end

    test "gossip selection validates object range and page text takes precedence", context do
      {guid, _pid, quest} = spawn_object(context, %{19 => 1})

      menu = %GossipLoader.Menu{
        menu_id: quest.id,
        text_id: 68,
        options: [%GossipLoader.Option{id: 0, option_id: 1, text: "Read", action_menu_id: -1}]
      }

      :ets.insert(GossipLoader, {{:menu, quest.id}, menu})
      on_exit(fn -> :ets.delete(GossipLoader, {:menu, quest.id}) end)
      state = GameObjects.use_object(context.state, guid)
      assert state.gossip_menu_guid == guid
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGossipMessage{guid: ^guid}}}
      far = %{state.character | movement_block: %{state.character.movement_block | position: {99.0, 0.0, 0.0, 0.0}}}
      far_state = %{state | character: far}
      assert Gossip.select(far_state, guid, 0) == far_state
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgGossipComplete{}}}, 10
      Gossip.select(state, guid, 0)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGossipComplete{}}}
    end
  end

  describe "quest activation projection" do
    test "tracks incomplete quests per viewer and clears after completion", context do
      {guid, pid, quest} = spawn_object(context, %{1 => 1})
      entity = :sys.get_state(pid)
      update = %UpdateObject{object: entity.object, game_object: entity.game_object}
      assert QuestGivers.personalize(update, context.state.character).game_object.dyn_flags == 0
      state = accept(context.state, quest)
      assert QuestGivers.personalize(update, state.character).game_object.dyn_flags == 1
      {:ok, log} = QuestLog.update(state.character.player.quest_log, quest.id, &%{&1 | status: :complete})
      complete = %{state.character | player: %{state.character.player | quest_log: log}}
      assert QuestGivers.personalize(update, complete).game_object.dyn_flags == 0
      assert guid == entity.object.guid
    end
  end

  describe "start_script/2" do
    test "uses the spawn identity in an instance and excludes wild summons", context do
      {_guid, pid, quest} = spawn_object(context, %{})
      object = :sys.get_state(pid)
      steps = [%ScriptStep{command: :emote, datalong: 1}]
      :ets.insert(ObjectScriptLoader, {quest.id, steps})
      on_exit(fn -> :ets.delete(ObjectScriptLoader, quest.id) end)

      pooled = %{
        object
        | internal: %{object.internal | summon: nil, spawn: %Internal.Spawn{pool_member: {:game_object, quest.id}}}
      }

      GooberServer.start_script(pooled, context.state.guid)
      assert_receive {:"$gen_cast", {:start_script, ^steps, _}}
      GooberServer.start_script(object, context.state.guid)
      assert_receive {:"$gen_cast", {:start_script, [], _}}
    end
  end

  describe "credit_game_object_member/2" do
    test "credits only nearby shareable quests", context do
      {guid, _pid, quest} = spawn_object(context, %{})
      state = accept(context.state, quest)
      assert Quests.credit_game_object_member(state, guid) == state
      :ets.insert(QuestLoader, {{:quest, quest.id}, %{quest | flags: 8}})
      updated = Quests.credit_game_object_member(state, guid)
      assert QuestLog.get(updated.character.player.quest_log, quest.id).counts == %{0 => 1}
      far = %{state.character | movement_block: %{state.character.movement_block | position: {999.0, 0.0, 0.0, 0.0}}}
      far_state = %{state | character: far}
      assert Quests.credit_game_object_member(far_state, guid) == far_state
    end
  end

  defp player(_context) do
    guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
    world = WorldRef.instance(999, guid)

    character = %Character{
      id: guid,
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, level: 50, flags: 0},
      player: %Player{quest_log: %{}},
      internal: %Internal{world: world},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0}
    }

    Entity.register(guid)
    World.update_position(character)
    Metadata.update(guid, %{alive?: true, level: 50})

    on_exit(fn ->
      World.remove_position(character)
      Metadata.delete(guid)
      :ets.delete(CharacterStore, guid)
    end)

    %{state: %State{guid: guid, character: character}, world: world}
  end

  defp spawn_object(context, data) do
    entry = 8_000_000 + System.unique_integer([:positive, :monotonic])

    data =
      Map.new(data, fn {index, value} -> {index, if(value == 1 and index in [1, 2, 10, 19], do: entry, else: value)} end)

    data = Enum.map(0..23, &Map.get(data, &1, 0)) |> List.replace_at(3, 10 * 65_536)
    template = %GameObjectTemplate{entry: entry, type: 10, size: 1.0, flags: 4, faction: 0, data: data}
    TemplateLoader.put(template)
    quest = %Quest{id: entry, required_entity_objectives: [{0, :game_object, entry, 0, 2}]}
    :ets.insert(QuestLoader, {{:quest, entry}, quest})
    object = GameObject.build_summoned(template, context.world, {1.0, 0.0, 0.0, 0.0})
    pid = start_supervised!({GameObjectServer, object}, id: entry)

    on_exit(fn ->
      :ets.delete(TemplateLoader, entry)
      :ets.delete(QuestLoader, {:quest, entry})
    end)

    {object.object.guid, pid, quest}
  end

  defp accept(state, quest) do
    {:ok, log} = QuestLog.add(state.character.player.quest_log, quest.id)
    character = %{state.character | player: %{state.character.player | quest_log: log}}
    %{state | character: character}
  end
end
