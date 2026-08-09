defmodule ThistleTea.Game.InstanceAuriusTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Data.Reputation
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context, as: SinkContext
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Condition, as: Evaluator
  alias ThistleTea.Game.Entity.Logic.QuestDialogStatus
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.QuestRequirements
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.InstanceScript.Effects, as: InstanceEffects
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.ConditionContext
  alias ThistleTea.Game.Player.Gossip, as: PlayerGossip
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World.InstanceData
  alias ThistleTea.Game.World.Loader.Gossip.Menu
  alias ThistleTea.Game.World.Loader.Gossip.Text
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem

  setup do
    id = System.unique_integer([:positive, :monotonic])
    server = :"aurius_instance_#{id}"
    owner = self()

    start_supervised!(
      {InstanceSystem,
       name: server,
       projection_table: InstanceData,
       script_name: fn 329 -> "instance_stratholme" end,
       owner: fn guid -> {:player, guid} end,
       effect_sink: fn world, effect -> send(owner, {:instance_effect, world, effect}) end}
    )

    first_guid = Guid.from_low_guid(:player, id)
    second_guid = Guid.from_low_guid(:player, id + 1)
    {:ok, first_world} = InstanceSystem.enter(329, first_guid, server)
    {:ok, second_world} = InstanceSystem.enter(329, second_guid, server)

    quest_5122 = quest(5_122, condition(3_755, 7, 0), complete_script_steps: [command_step(5_122, 7, 1)])
    quest_5125 = quest(5_125, condition(3_757, 7, 2))
    npc_entry = 10_917
    npc_guid = Guid.from_low_guid(:mob, npc_entry, id)

    :ets.insert(QuestLoader, [{{:quest, 5_122}, quest_5122}, {{:quest, 5_125}, quest_5125}])
    :ets.insert(QuestLoader, {{:giver, npc_entry}, [5_122, 5_125]})
    :ets.insert(QuestLoader, {{:ender, npc_entry}, [5_122, 5_125]})

    on_exit(fn ->
      InstanceData.remove(first_world)
      InstanceData.remove(second_world)
      :ets.delete(QuestLoader, {:quest, 5_122})
      :ets.delete(QuestLoader, {:quest, 5_125})
      :ets.delete(QuestLoader, {:giver, npc_entry})
      :ets.delete(QuestLoader, {:ender, npc_entry})
    end)

    {:ok,
     server: server,
     first_world: first_world,
     second_world: second_world,
     first: character(first_guid, first_world),
     second: character(second_guid, second_world),
     npc_guid: npc_guid,
     quest_5122: quest_5122,
     quest_5125: quest_5125,
     menu: aurius_menu()}
  end

  test "quest, gossip, and scripts share isolated Aurius state from zero through two", context do
    zero = Quests.availability(context.first, [context.quest_5122, context.quest_5125])
    assert zero.condition_results == %{5_122 => :met, 5_125 => :unmet}
    assert QuestRequirements.can_take(context.quest_5122, zero.quest_context, :met) == :ok
    assert QuestRequirements.can_take(context.quest_5125, zero.quest_context, :unmet) == {:error, :required_condition}
    assert [{%Quest{id: 5_122}, _icon}] = Quests.quest_menu(context.npc_guid, context.first)
    assert PlayerGossip.title_text_id(context.menu, context.first, context.npc_guid) == 3_755

    npc = %Mob{object: %Object{guid: context.npc_guid}, internal: %Internal{world: context.first_world}}
    npc = execute(npc, command_step(5_122, 7, 1), context.server)

    one = Quests.availability(context.first, [context.quest_5122, context.quest_5125])
    assert one.condition_results == %{5_122 => :unmet, 5_125 => :unmet}
    assert PlayerGossip.title_text_id(context.menu, context.first, context.npc_guid) == 3_756
    assert PlayerGossip.title_text_id(context.menu, context.second, context.npc_guid) == 3_755

    npc = execute(npc, command_step(1_091_703, 7, 2), context.server)
    assert npc.internal.world == context.first_world

    two = Quests.availability(context.first, [context.quest_5122, context.quest_5125])
    assert two.condition_results == %{5_122 => :unmet, 5_125 => :met}
    assert QuestRequirements.can_take(context.quest_5125, two.quest_context, :met) == :ok
    assert PlayerGossip.title_text_id(context.menu, context.first, context.npc_guid) == 3_757
    assert PlayerGossip.title_text_id(context.menu, context.second, context.npc_guid) == 3_755

    field_five = condition(3_758, 5, 3)
    field_five_context = ConditionContext.build(context.first, [field_five], source: nil)
    assert Evaluator.evaluate(field_five_context, field_five) == :unmet

    npc = execute(npc, command_step(1_044_001, 5, 1), context.server)
    assert_receive {:instance_effect, first_world, %InstanceEffects.OperateGameObject{action: :close}}
    assert first_world == context.first_world

    _npc = execute(npc, command_step(1_044_003, 5, 3), context.server)
    field_five_context = ConditionContext.build(context.first, [field_five], source: nil)
    other_copy_context = ConditionContext.build(context.second, [field_five], source: nil)

    assert Evaluator.evaluate(field_five_context, field_five) == :met
    assert Evaluator.evaluate(other_copy_context, field_five) == :unmet
    assert_receive {:instance_effect, ^first_world, %InstanceEffects.OperateGameObject{action: :open}}
  end

  test "fresh acceptance rejects a stale state-two menu and active enders ignore later field changes", context do
    npc = %Mob{object: %Object{guid: context.npc_guid}, internal: %Internal{world: context.first_world}}
    npc = execute(npc, command_step(1_091_703, 7, 2), context.server)

    assert Enum.any?(Quests.quest_menu(context.npc_guid, context.first), fn {quest, _icon} -> quest.id == 5_125 end)

    _npc = execute(npc, command_step(5_122, 7, 1), context.server)
    state = %{guid: context.first.object.guid, character: context.first, gossip_menu_options: []}

    assert Quests.accept(state, context.npc_guid, 5_125) == state
    refute QuestLog.active?(state.character.player.quest_log, 5_125)
    assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgQuestgiverQuestInvalid{reason: 0}}}

    completed = completed_character(context.first, context.quest_5122)
    assert [{%Quest{id: 5_122}, icon} | _entries] = Quests.quest_menu(context.npc_guid, completed)
    assert icon == QuestDialogStatus.reward_rep()
  end

  defp execute(entity, step, server) do
    {entity, blackboard} = Script.run(entity, Blackboard.new(), [step], nil, 1_000)
    assert blackboard == Blackboard.new()
    EventSink.emit_pending(entity, SinkContext.new(self(), instance_system: server))
  end

  defp completed_character(character, quest) do
    {:ok, quest_log} = QuestLog.add(%{}, quest.id)
    {:ok, quest_log} = QuestLog.update(quest_log, quest.id, &%{&1 | status: :complete})
    %{character | player: %{character.player | quest_log: quest_log}}
  end

  defp character(guid, world) do
    %Character{
      object: %Object{guid: guid},
      unit: %Unit{level: 60, race: 1, class: 1, health: 100, max_health: 100, power1: 100, max_power1: 100, auras: []},
      player: %Player{skills: %{}, quest_log: %{}, rewarded_quests: MapSet.new(), reputation: %Reputation{}},
      movement_block: %MovementBlock{position: {3_680.53, -3_643.8, 140.03, 0.0}},
      internal: %Internal{world: world, spellbook: %{}}
    }
  end

  defp quest(id, required_condition, options \\ []) do
    %Quest{
      id: id,
      title: "Aurius fixture #{id}",
      min_level: 55,
      level: 60,
      required_condition_id: required_condition.entry,
      required_condition: required_condition,
      complete_script_steps: Keyword.get(options, :complete_script_steps, [])
    }
  end

  defp condition(entry, field, expected) do
    %Condition{entry: entry, type: :instance_data, value1: field, value2: expected, value3: 0}
  end

  defp aurius_menu do
    %Menu{
      menu_id: 3_043,
      text_id: 3_755,
      texts: [
        %Text{text_id: 3_755, condition_id: 0},
        %Text{text_id: 3_756, condition_id: 3_756, condition: condition(3_756, 7, 1)},
        %Text{text_id: 3_757, condition_id: 3_757, condition: condition(3_757, 7, 2)}
      ]
    }
  end

  defp command_step(script_id, field, value) do
    ScriptStep.build(%{
      id: script_id,
      delay: 0,
      priority: 0,
      command: 37,
      datalong: field,
      datalong2: value,
      datalong3: 0,
      datalong4: 0,
      target_param1: 0,
      target_param2: 0,
      target_type: 0,
      data_flags: 0,
      dataint: 0,
      dataint2: 0,
      dataint3: 0,
      dataint4: 0,
      x: 0.0,
      y: 0.0,
      z: 0.0,
      o: 0.0,
      condition_id: 0
    })
  end
end
