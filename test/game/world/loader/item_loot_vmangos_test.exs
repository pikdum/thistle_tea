defmodule ThistleTea.Game.World.Loader.ItemLootVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Loot, as: LootLoader

  @moduletag :vmangos_db

  describe "generate_item/4" do
    test "preloads item loot and generates lockbox contents without gameplay queries" do
      assert :ok = LootLoader.load_all()
      assert [{{:item, 16_885}, [_ | _]}] = :ets.lookup(LootLoader, {:item, 16_885})

      for {{:item, _entry}, rows} <- :ets.tab2list(LootLoader), row <- rows, row.item > 0 do
        if !ItemLoader.get_cached_template(row.item), do: refute(Mangos.Repo.get(Mangos.ItemTemplate, row.item))
      end

      handler = "item-loot-#{System.unique_integer([:positive])}"
      :telemetry.attach(handler, Mangos.Repo.config()[:telemetry_prefix] ++ [:query], &__MODULE__.query/4, self())
      on_exit(fn -> :telemetry.detach(handler) end)
      :rand.seed(:exsss, {1, 2, 3})
      rolls = for _ <- 1..20, do: LootLoader.generate_item(16_885, 150, 600)
      assert Enum.all?(rolls, &(&1.gold in 150..600))
      assert Enum.any?(rolls, &(&1.items != []))
      assert LootLoader.generate_item(999_999, 0, 0).items == []

      :ets.insert(
        LootLoader,
        {{:item, 999_999}, [%{item: 2063, chance: 100.0, groupid: 0, mincount_or_ref: 1, maxcount: 1}]}
      )

      on_exit(fn -> :ets.delete(LootLoader, {:item, 999_999}) end)
      assert LootLoader.generate_item(999_999, 0, 0).items == []
      refute_receive :gameplay_query
    end
  end

  def query(_event, _measurements, _metadata, pid) do
    if self() == pid, do: send(pid, :gameplay_query)
  end
end
