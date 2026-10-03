defmodule ThistleTea.Game.World.Loader.GossipTest do
  use ExUnit.Case, async: false

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

  defp cleanup(entry, menu_ids) do
    keys = [{:creature_menu, entry}, {:menu, {:creature, entry}} | Enum.map(menu_ids, &{:menu, &1})]
    Enum.each(keys, &:ets.delete(Gossip, &1))
  end
end
