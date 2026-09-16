defmodule ThistleTea.Game.World.Loader.FishingIntegrationTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Logic.Trainer
  alias ThistleTea.Game.World.Loader.Fishing
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Loot
  alias ThistleTea.Game.World.Loader.Trainer, as: TrainerLoader

  describe "base_skill/2" do
    @describetag :vmangos_db

    test "loads area difficulty with zone fallback" do
      Fishing.load_all()
      assert Fishing.base_skill(327, 45) == 130
      assert Fishing.base_skill(999_999, 45) == 130
    end
  end

  describe "fishing trainer" do
    @describetag :dbc_db

    test "resolves apprentice and journeyman skill tiers" do
      spells = TrainerLoader.trainer_info(3179).spells
      apprentice = Enum.find(spells, &(&1.teach_spell_id == 7733))
      journeyman = Enum.find(spells, &(&1.teach_spell_id == 7734))

      assert {apprentice.learned_spell_id, apprentice.skill_id, apprentice.skill_max} == {7620, 356, 75}
      assert {journeyman.learned_spell_id, journeyman.skill_id, journeyman.skill_max} == {7731, 356, 150}
      assert Trainer.state(journeyman, [7620], 10, %{356 => %{value: 50}}) == :green
    end
  end

  describe "fishing loot" do
    @describetag :vmangos_db

    setup [:observe_queries]

    test "generates area loot and falls back to the zone table" do
      loaded = :ets.lookup(Loot, :loaded)
      assert :ok = Loot.load_fishing()
      queries = collect_queries()

      assert Enum.any?(queries, &String.contains?(&1, "fishing_loot_template"))
      refute Enum.any?(queries, &String.contains?(&1, ["creature_loot_template", "gameobject_loot_template"]))
      assert :ets.lookup(Loot, :loaded) == loaded

      for {{:fishing, _area}, rows} <- :ets.tab2list(Loot), row <- rows, row.item > 0 do
        assert ItemLoader.get_cached_template(row.item)
      end

      :rand.seed(:exsss, {1, 2, 3})
      assert %{items: [_ | _] = area_items} = Loot.generate_fishing(327, 45)
      assert %{items: [_ | _] = zone_items} = Loot.generate_fishing(999_999, 45)

      assert Enum.all?(area_items, &(&1.item_id in fishing_items(327)))
      assert Enum.all?(zone_items, &(&1.item_id in fishing_items(45)))
      assert collect_queries() == []
    end
  end

  defp observe_queries(_context) do
    handler_id = "fishing-queries-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        Mangos.Repo.config()[:telemetry_prefix] ++ [:query],
        fn _event, _measurements, metadata, test_pid ->
          if self() == test_pid, do: send(test_pid, {:mangos_query, metadata.query})
        end,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp collect_queries do
    receive do
      {:mangos_query, query} -> [query | collect_queries()]
    after
      0 -> []
    end
  end

  defp fishing_items(area) do
    [{{:fishing, ^area}, rows}] = :ets.lookup(Loot, {:fishing, area})
    Enum.map(rows, & &1.item)
  end
end
