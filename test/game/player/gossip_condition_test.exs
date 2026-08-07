defmodule ThistleTea.Game.Player.GossipConditionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.Reputation
  alias ThistleTea.Game.Entity.Logic.Condition.Context
  alias ThistleTea.Game.Entity.Logic.Condition.Subject
  alias ThistleTea.Game.Player.Gossip
  alias ThistleTea.Game.Player.GossipCondition
  alias ThistleTea.Game.World.Loader.Gossip.Menu
  alias ThistleTea.Game.World.Loader.Gossip.Text
  alias ThistleTea.Game.WorldRef

  describe "allows?/3" do
    test "gates a Moonglade taxi option by faction and druid class" do
      condition = %Condition{
        type: :and,
        children: [
          %Condition{type: :team, value1: 469},
          %Condition{type: :race_class, value1: 0, value2: 1024}
        ]
      }

      assert GossipCondition.allows?(context(469, 1, 11), condition, :deny_unknown)
      refute GossipCondition.allows?(context(67, 2, 11), condition, :deny_unknown)
      refute GossipCondition.allows?(context(469, 1, 1), condition, :deny_unknown)
    end

    test "names legacy-open and action-deny unknown policies" do
      condition = %Condition{entry: 5, type: :item_with_bank, value1: 100, value2: 1}

      assert GossipCondition.allows?(context(469, 1, 11), condition, :legacy_open)
      refute GossipCondition.allows?(context(469, 1, 11), condition, :deny_unknown)
    end
  end

  describe "title_text_id/2" do
    test "chooses the highest satisfied row with an unconditional fallback" do
      menu = %Menu{
        texts: [
          %Text{text_id: 100, condition_id: 0},
          %Text{
            text_id: 200,
            condition_id: 10,
            condition: %Condition{entry: 10, type: :level, value1: 10, value2: 1}
          },
          %Text{
            text_id: 300,
            condition_id: 20,
            condition: %Condition{entry: 20, type: :level, value1: 20, value2: 1}
          }
        ]
      }

      assert Gossip.title_text_id(menu, character(15)) == 200
      assert Gossip.title_text_id(menu, character(5)) == 100
    end

    test "uses the unconditional fallback when a display condition is unknown" do
      menu = %Menu{
        texts: [
          %Text{text_id: 100, condition_id: 0},
          %Text{
            text_id: 200,
            condition_id: 10,
            condition: %Condition{entry: 10, type: :item_with_bank, value1: 1, value2: 1}
          }
        ]
      }

      assert Gossip.title_text_id(menu, character(15)) == 100
    end
  end

  defp context(team, race, class) do
    Context.new(target: Subject.new(team: team, race: race, class: class))
  end

  defp character(level) do
    %Character{
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
      internal: %Internal{world: WorldRef.open(0), spellbook: %{}}
    }
  end
end
