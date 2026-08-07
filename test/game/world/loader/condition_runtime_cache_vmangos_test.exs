defmodule ThistleTea.Game.World.Loader.ConditionRuntimeCacheVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.World.Loader.AreaTrigger
  alias ThistleTea.Game.World.Loader.Gossip
  alias ThistleTea.Game.World.Loader.Loot
  alias ThistleTea.Game.World.Loader.Vendor

  @moduletag :vmangos_db

  describe "condition-aware runtime caches" do
    test "do not query Mangos after startup preload" do
      assert :ok = Gossip.load_all()
      assert :ok = Vendor.load_all()
      assert :ok = AreaTrigger.load_all()
      assert :ok = Loot.load_all()

      {{:menu, menu_id}, %Gossip.Menu{}} =
        Enum.find(:ets.tab2list(Gossip), &match?({{:menu, _menu_id}, %Gossip.Menu{}}, &1))

      {vendor_entry, [_item | _items]} =
        Enum.find(:ets.tab2list(Vendor), fn
          {entry, [_item | _items]} when is_integer(entry) -> true
          _entry -> false
        end)

      {{:trigger, trigger_id}, trigger} =
        Enum.find(:ets.tab2list(AreaTrigger), &match?({{:trigger, _trigger_id}, %{}}, &1))

      {{:creature, loot_id}, [_row | _rows]} =
        Enum.find(:ets.tab2list(Loot), &match?({{:creature, _loot_id}, [_row | _rows]}, &1))

      counter = :counters.new(1, [:atomics])
      handler_id = "condition-runtime-cache-#{System.unique_integer([:positive])}"
      test_pid = self()

      :ok =
        :telemetry.attach(
          handler_id,
          Mangos.Repo.config()[:telemetry_prefix] ++ [:query],
          fn _event, _measurements, _metadata, {counter, test_pid} ->
            if self() == test_pid, do: :counters.add(counter, 1, 1)
          end,
          {counter, test_pid}
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert %Gossip.Menu{} = Gossip.get_menu(menu_id)
      assert [_item | _items] = Vendor.items(vendor_entry)
      assert ^trigger = AreaTrigger.get(trigger_id)
      assert %{items: items} = Loot.generate(loot_id, 0, 0)
      assert is_list(items)

      assert Gossip.get_menu(2_147_483_647) == nil
      assert Vendor.items(2_147_483_647) == []
      assert AreaTrigger.get(2_147_483_647) == nil
      assert %{items: []} = Loot.generate(2_147_483_647, 0, 0)

      assert :counters.get(counter, 1) == 0
    end
  end
end
