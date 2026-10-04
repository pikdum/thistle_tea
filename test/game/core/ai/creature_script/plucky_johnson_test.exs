defmodule ThistleTea.Game.Core.AI.CreatureScript.PluckyJohnsonTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Gossip
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  @plucky 6_626
  @beckon 7
  @chicken_emote 22
  @plucky_faction 189
  @friendly 35
  @gossip 0x1
  @on_the_quest %Condition{type: :quest_taken, value1: 1_950, value2: 1}

  setup do
    %{plucky: plucky(), player: Guid.from_low_guid(:player, Unique.integer())}
  end

  describe "events/1" do
    test "a /beckon from a player on the quest turns him back and lets him talk", %{plucky: plucky, player: player} do
      {plucky, blackboard} = emote(plucky, Blackboard.new(), player, @beckon, :met)

      assert blackboard.event_ai.phase == 1
      assert plucky.unit.faction_template == @friendly
      assert gossip?(plucky)
      assert Enum.any?(plucky.internal.events, &match?(%Effects.TriggerSpell{spell_id: 9_192}, &1))

      assert %Effects.ScriptSteps{duration_ms: 120_000, steps: steps} =
               Enum.find(plucky.internal.events, &match?(%Effects.ScriptSteps{}, &1))

      assert [
               %ScriptStep{command: :modify_flags, datalong2: @gossip, datalong3: 2},
               %ScriptStep{command: :set_faction, datalong: 0},
               %ScriptStep{command: :cast_spell, datalong: 9_220},
               %ScriptStep{command: :set_phase, datalong: 0}
             ] = steps
    end

    test "a /beckon from anyone else leaves him a chicken", %{plucky: plucky, player: player} do
      {plucky, blackboard} = emote(plucky, Blackboard.new(), player, @beckon, :unmet)

      assert blackboard.event_ai.phase == 0
      assert plucky.unit.faction_template == @plucky_faction
      refute gossip?(plucky)
    end

    test "a /chicken from anyone turns him back, and he waves", %{plucky: plucky, player: player} do
      {plucky, _blackboard} = emote(plucky, Blackboard.new(), player, @chicken_emote, :unmet)

      assert gossip?(plucky)
      assert %Effects.Emote{emote_id: 3} in plucky.internal.events
    end

    test "emotes while he is himself change nothing", %{plucky: plucky, player: player} do
      {plucky, blackboard} = emote(plucky, Blackboard.new(), player, @chicken_emote, :met)
      plucky = %{plucky | internal: %{plucky.internal | events: []}}

      {plucky, _blackboard} = emote(plucky, blackboard, player, @beckon, :met)
      assert plucky.internal.events == []
    end
  end

  describe "gossip/0" do
    test "asking for the phrase completes Get the Scoop and shows his answer" do
      assert %{@plucky => %Gossip{texts: [%Gossip.Text{text_id: 720}], options: [option]}} = CreatureScript.gossip()

      assert %Gossip.Option{condition: @on_the_quest, reply_text_id: 738} = option
      assert [%ScriptStep{command: :quest_explored, datalong: 1_950}] = option.steps
    end
  end

  defp emote(plucky, blackboard, player, emote_id, quest) do
    context = Context.new(0, script_conditions: %{@on_the_quest => quest})
    EventAI.on_receive_emote(plucky, blackboard, player, emote_id, 0, context)
  end

  defp gossip?(%Mob{unit: %Unit{npc_flags: flags}}), do: Bitwise.band(flags, @gossip) != 0

  defp plucky do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, @plucky, Unique.integer()), entry: @plucky},
      unit: %Unit{
        health: 100,
        max_health: 100,
        level: 30,
        auras: [],
        flags: 0,
        npc_flags: 0,
        faction_template: @plucky_faction
      },
      movement_block: %MovementBlock{position: {-6_185.0, -3_936.0, -58.6, 0.0}},
      internal: %Internal{
        world: WorldRef.open(1),
        name: "\"Plucky\" Johnson",
        creature: %Creature{ai_events: CreatureScript.events(@plucky)}
      }
    }
  end
end
