defmodule ThistleTea.Game.Player.AreaTriggersConditionTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.AreaTriggerTeleport
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.Reputation
  alias ThistleTea.Game.Network.Message.SmsgAreaTriggerMessage
  alias ThistleTea.Game.Player.AreaTriggers
  alias ThistleTea.Game.World.Loader.AreaTrigger, as: AreaTriggerLoader
  alias ThistleTea.Game.WorldRef

  describe "condition policy" do
    test "accepts or rejects a cached conditioned teleport" do
      trigger_id = System.unique_integer([:positive, :monotonic])
      condition = %Condition{entry: 1, type: :level, value1: 10, value2: 1}
      cache_trigger(trigger_id, condition)

      AreaTriggers.handle(state(10), trigger_id)

      assert_receive {:"$gen_cast", {:start_teleport, 10.0, 20.0, 30.0, 1.0, %WorldRef{map_id: 0}}}

      AreaTriggers.handle(state(9), trigger_id)

      assert_receive {:"$gen_cast", {:send_packet, %SmsgAreaTriggerMessage{message: "Condition not met"}}}
      refute_receive {:"$gen_cast", {:start_teleport, _, _, _, _, _}}

      clear_trigger(trigger_id)
    end

    test "rejects an unknown cached condition" do
      trigger_id = System.unique_integer([:positive, :monotonic])
      condition = %Condition{entry: 2, type: :item_with_bank, value1: 100, value2: 1}
      cache_trigger(trigger_id, condition)

      AreaTriggers.handle(state(60), trigger_id)

      assert_receive {:"$gen_cast", {:send_packet, %SmsgAreaTriggerMessage{message: "Condition not met"}}}
      refute_receive {:"$gen_cast", {:start_teleport, _, _, _, _, _}}

      clear_trigger(trigger_id)
    end
  end

  defp cache_trigger(trigger_id, condition) do
    :ets.insert(AreaTriggerLoader, [
      {{:trigger, trigger_id},
       %{
         id: trigger_id,
         map: 1,
         x: 0.0,
         y: 0.0,
         z: 0.0,
         radius: 5.0,
         box_x: 0.0,
         box_y: 0.0,
         box_z: 0.0,
         box_orientation: 0.0
       }},
      {{:quest, trigger_id}, nil},
      {{:tavern, trigger_id}, false},
      {{:teleport, trigger_id},
       %AreaTriggerTeleport{
         id: trigger_id,
         message: "Condition not met",
         required_level: 1,
         condition: condition,
         target_map: 0,
         x: 10.0,
         y: 20.0,
         z: 30.0,
         orientation: 1.0
       }}
    ])
  end

  defp clear_trigger(trigger_id) do
    Enum.each([:trigger, :quest, :tavern, :teleport], fn kind ->
      :ets.delete(AreaTriggerLoader, {kind, trigger_id})
    end)
  end

  defp state(level) do
    %{
      ready: true,
      guid: 1,
      character: %Character{
        object: %Object{guid: 1},
        unit: %Unit{
          level: level,
          race: 1,
          class: 1,
          health: 100,
          max_health: 100,
          power1: 0,
          max_power1: 0,
          auras: []
        },
        player: %Player{
          skills: %{},
          quest_log: %{},
          rewarded_quests: MapSet.new(),
          reputation: %Reputation{}
        },
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: WorldRef.open(1), spellbook: %{}}
      }
    }
  end
end
