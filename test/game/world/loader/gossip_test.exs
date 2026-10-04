defmodule ThistleTea.Game.World.Loader.GossipTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.CreatureScript.Gossip, as: ScriptedGossip
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.World.Loader.Gossip
  alias ThistleTea.Game.World.Loader.Gossip.Menu
  alias ThistleTea.Game.World.Loader.Gossip.Option
  alias ThistleTea.Test.Unique

  describe "trainer_of?/4" do
    test "allows another race to use a mount trainer at exalted" do
      entry = Unique.integer()
      key = {:trainer, entry}
      :ets.insert(Gossip, {key, %{type: 1, class: 0, race: 1}})
      on_exit(fn -> :ets.delete(Gossip, key) end)

      assert Gossip.trainer_of?(entry, 1, 1)
      refute Gossip.trainer_of?(entry, 1, 3)
      assert Gossip.trainer_of?(entry, 1, 3, true)
    end
  end

  describe "add_creature_option/2" do
    test "gives a creature without a menu one holding just the option" do
      entry = Unique.integer()
      on_exit(fn -> cleanup(entry, []) end)

      assert :ok = Gossip.add_creature_option(entry, %Option{text: "Insert key"})
      assert %Menu{text_id: nil, options: [%Option{id: 0, text: "Insert key"}]} = Gossip.menu_for_creature(entry)
    end

    test "appends to a copy of the creature's menu, leaving the shared menu alone" do
      entry = Unique.integer()
      menu_id = Unique.integer()
      shared = %Menu{menu_id: menu_id, text_id: 7, options: [%Option{id: 0, text: "Hello"}, %Option{id: 4}]}
      :ets.insert(Gossip, [{{:menu, menu_id}, shared}, {{:creature_menu, entry}, menu_id}])
      on_exit(fn -> cleanup(entry, [menu_id]) end)

      :ok = Gossip.add_creature_option(entry, %Option{text: "Insert key"})

      assert %Menu{text_id: 7, options: [%Option{id: 0}, %Option{id: 4}, %Option{id: 5, text: "Insert key"}]} =
               Gossip.menu_for_creature(entry)

      assert Gossip.get_menu(menu_id) == shared
    end
  end

  describe "put_scripted_menu/3" do
    test "replaces the creature's menu with greetings ranked by order and options that close the window" do
      entry = Unique.integer()
      menu_id = Unique.integer()
      :ets.insert(Gossip, [{{:menu, menu_id}, %Menu{menu_id: menu_id, text_id: 7}}, {{:creature_menu, entry}, menu_id}])
      on_exit(fn -> cleanup(entry, [menu_id]) end)
      ready = %Condition{type: :instance_data, value1: 1, value2: 8}
      steps = [%ScriptStep{command: :talk, dataint: 3_882}]

      gossip = %ScriptedGossip{
        texts: [
          %ScriptedGossip.Text{text_id: 1_516},
          %ScriptedGossip.Text{text_id: 1_515, condition: %Condition{type: :instance_data, value1: 1}},
          %ScriptedGossip.Text{text_id: 1_517, condition: ready}
        ],
        options: [%ScriptedGossip.Option{text: "Fight", condition: ready, steps: steps}]
      }

      assert :ok = Gossip.put_scripted_menu(entry, gossip, &[:resolved | &1])

      assert %Menu{text_id: 1_516, texts: texts, options: [option]} = Gossip.menu_for_creature(entry)
      assert Enum.map(texts, &{&1.text_id, &1.condition_id}) == [{1_516, 0}, {1_515, 2}, {1_517, 3}]

      assert %Option{id: 0, text: "Fight", option_id: 1, action_menu_id: -1, condition: ^ready, talk_credit?: false} =
               option

      assert option.action_steps == [:resolved | steps]
    end

    test "an option with a reply text leads to a menu showing just that text" do
      entry = Unique.integer()
      reply_id = {:creature_reply, entry, 1}
      on_exit(fn -> cleanup(entry, [reply_id]) end)

      gossip = %ScriptedGossip{
        texts: [%ScriptedGossip.Text{text_id: 720}],
        options: [%ScriptedGossip.Option{text: "Bye"}, %ScriptedGossip.Option{text: "Phrase", reply_text_id: 738}]
      }

      :ok = Gossip.put_scripted_menu(entry, gossip, & &1)

      assert %Menu{options: [%Option{action_menu_id: -1}, %Option{action_menu_id: ^reply_id}]} =
               Gossip.menu_for_creature(entry)

      assert %Menu{menu_id: ^reply_id, text_id: 738, texts: [], options: []} = Gossip.get_menu(reply_id)
    end
  end

  defp cleanup(entry, menu_ids) do
    keys = [{:creature_menu, entry}, {:menu, {:creature, entry}} | Enum.map(menu_ids, &{:menu, &1})]
    Enum.each(keys, &:ets.delete(Gossip, &1))
  end
end
