defmodule ThistleTea.Game.Core.AI.CreatureScript.ChickenCluckTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Random
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  @chicken 620
  @cheer 21
  @chicken_emote 22
  @questgiver 0x2
  @never_taken %Condition{type: :quest_none, value1: 3_861}
  @feed_in_hand %Condition{type: :quest_taken, value1: 3_861, value2: 2}

  setup do
    %{chicken: chicken(), player: Guid.from_low_guid(:player, Unique.integer())}
  end

  describe "events/1" do
    test "a respawned chicken offers no quest", %{chicken: chicken} do
      {chicken, _blackboard} = EventAI.on_spawned(chicken, Blackboard.new(), 0, Context.new(0))

      refute questgiver?(chicken)
    end

    test "a lucky /chicken from a newcomer offers CLUCK!", %{chicken: chicken, player: player} do
      chicken = %{chicken | unit: %{chicken.unit | npc_flags: 0}}
      context = Context.new(0, random: Random.fixed(0.5, 1), script_conditions: %{@never_taken => :met})

      {chicken, _blackboard} = EventAI.on_receive_emote(chicken, Blackboard.new(), player, @chicken_emote, 0, context)

      assert questgiver?(chicken)
    end

    test "an unlucky /chicken does nothing", %{chicken: chicken, player: player} do
      chicken = %{chicken | unit: %{chicken.unit | npc_flags: 0}}
      context = Context.new(0, random: Random.fixed(0.5, 4), script_conditions: %{@never_taken => :met})

      {chicken, _blackboard} = EventAI.on_receive_emote(chicken, Blackboard.new(), player, @chicken_emote, 0, context)

      refute questgiver?(chicken)
    end

    test "/chicken does nothing for a player who already took the quest", %{chicken: chicken, player: player} do
      chicken = %{chicken | unit: %{chicken.unit | npc_flags: 0}}
      context = Context.new(0, random: Random.fixed(0.5, 1), script_conditions: %{@never_taken => :unmet})

      {chicken, _blackboard} = EventAI.on_receive_emote(chicken, Blackboard.new(), player, @chicken_emote, 0, context)

      refute questgiver?(chicken)
    end

    test "/cheer with the feed in hand takes the quest back", %{chicken: chicken, player: player} do
      chicken = %{chicken | unit: %{chicken.unit | npc_flags: 0}}
      context = Context.new(0, script_conditions: %{@feed_in_hand => :met})

      {chicken, _blackboard} = EventAI.on_receive_emote(chicken, Blackboard.new(), player, @cheer, 0, context)

      assert questgiver?(chicken)
    end
  end

  defp questgiver?(%Mob{unit: %Unit{npc_flags: flags}}), do: Bitwise.band(flags, @questgiver) != 0

  defp chicken do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, @chicken, Unique.integer()), entry: @chicken},
      unit: %Unit{health: 10, max_health: 10, level: 1, auras: [], flags: 0, npc_flags: @questgiver},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: %WorldRef{map_id: 0},
        name: "Chicken",
        creature: %Creature{ai_events: CreatureScript.events(@chicken)}
      }
    }
  end
end
