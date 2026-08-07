defmodule ThistleTea.Game.Player.GossipConditionTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Reputation
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.Condition.Context
  alias ThistleTea.Game.Entity.Logic.Condition.Subject
  alias ThistleTea.Game.Player.Gossip
  alias ThistleTea.Game.Player.GossipCondition
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Gossip.Menu
  alias ThistleTea.Game.World.Loader.Gossip.Option
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

  describe "bank item revalidation" do
    test "shows and selects an inclusive option while deposited or withdrawn" do
      player_guid = System.unique_integer([:positive, :monotonic])
      {:ok, _owner} = Entity.register(player_guid)
      item = ItemStore.create(%ItemTemplate{entry: 9000}, owner: player_guid)
      on_exit(fn -> ItemStore.delete(item.object.guid) end)

      condition = %Condition{entry: 30, type: :item_with_bank, value1: 9000, value2: 1}

      option = %Option{
        id: 0,
        option_id: 1,
        condition: condition,
        taxi_path_steps: [%ScriptStep{command: :send_taxi_path, datalong: 315}]
      }

      menu = %Menu{text_id: 68, options: [option]}
      deposited = bank_character(player_guid, item.object.guid)
      deposited_state = Gossip.send_menu(2, menu, [], %{character: deposited, gossip_menu_options: []})
      assert [%Option{id: 0}] = deposited_state.gossip_menu_options
      assert %{gossip_menu_options: []} = Gossip.select(deposited_state, 2, 0)
      assert_receive {:send_taxi_path, 315}

      withdrawn = %{deposited | player: %{deposited.player | bank1: 0, inv1: item.object.guid}}
      withdrawn_state = %{character: withdrawn, gossip_menu_options: [option]}
      assert %{gossip_menu_options: []} = Gossip.select(withdrawn_state, 2, 0)
      assert_receive {:send_taxi_path, 315}

      absent = %{withdrawn | player: %{withdrawn.player | inv1: 0}}
      absent_state = %{character: absent, gossip_menu_options: [option]}
      assert Gossip.select(absent_state, 2, 0) == absent_state
      refute_receive {:send_taxi_path, 315}
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

  defp bank_character(guid, item_guid) do
    %Character{
      object: %Object{guid: guid},
      unit: %Unit{
        level: 20,
        race: 1,
        class: 1,
        health: 100,
        max_health: 100,
        power1: 0,
        max_power1: 0,
        auras: []
      },
      player: %Player{
        bank1: item_guid,
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
