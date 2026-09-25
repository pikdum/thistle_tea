defmodule ThistleTea.Game.World.Loader.AlteracValleyVMangosTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Battleground.AlteracValley
  alias ThistleTea.Game.Battleground.AlteracValley.Mine
  alias ThistleTea.Game.Battleground.AlteracValley.Node

  @moduletag :vmangos_db

  describe "Alterac event catalog" do
    test "every neutral and faction supply spawn maps to its controlling mine" do
      supplies =
        Mangos.Repo.all(
          from(binding in Mangos.GameObjectBattleground,
            join: object in Mangos.GameObject,
            on: object.guid == binding.guid,
            where: object.map == 30 and binding.event1 in [50, 51],
            select: {binding.event1, binding.event2, object.id},
            distinct: true
          )
        )

      assert length(supplies) == 6

      for {event, state, entry} <- supplies do
        assert state in 0..2
        assert Mine.supply_mine_id(entry) == event - 50
      end
    end

    test "pins starting nodes, faction marshals, mine variants, and non-clickable destroyed towers" do
      creatures =
        Mangos.Repo.all(
          from(binding in Mangos.CreatureBattleground,
            join: creature in Mangos.Creature,
            on: creature.guid == binding.guid,
            where: creature.map == 30,
            select: {binding.event1, binding.event2}
          )
        )
        |> MapSet.new()

      objects =
        Mangos.Repo.all(
          from(binding in Mangos.GameObjectBattleground,
            join: object in Mangos.GameObject,
            on: object.guid == binding.guid,
            where: object.map == 30,
            select: {binding.event1, binding.event2, object.id}
          )
        )

      events = AlteracValley.initial_events()

      for {id, node} <- Node.all() do
        assert Enum.any?(objects, fn {event, state, _entry} -> event == id and state == events[id] end)
        assert Enum.all?(Node.defender_events(node), &MapSet.member?(creatures, &1))
      end

      for event <- 22..29, state <- [1, 3], do: assert(MapSet.member?(creatures, {event, state}))
      for event <- [46, 47, 50, 51], state <- 0..2, do: assert(MapSet.member?(creatures, {event, state}))
      for event <- [48, 49, 61, 62], do: assert(MapSet.member?(creatures, {event, 0}))

      for id <- 7..14 do
        destroyed_state = if id <= 10, do: 3, else: 1
        entries = for {^id, ^destroyed_state, entry} <- objects, do: entry
        assert entries != []

        refute Enum.any?(
                 entries,
                 &(&1 in [178_364, 178_365, 178_925, 178_940, 178_943, 179_286, 179_287, 179_435, 180_418])
               )
      end
    end
  end
end
