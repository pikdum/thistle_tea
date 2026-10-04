defmodule ThistleTea.Game.World.Loader.AlteracValleyVMangosTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.Battleground.AlteracValley
  alias ThistleTea.Game.Core.Battleground.AlteracValley.Mine
  alias ThistleTea.Game.Core.Battleground.AlteracValley.Node

  @moduletag :vmangos_db

  describe "Alterac event catalog" do
    test "each wing commander has her supply quest and a route home" do
      for {entry, quest_id, item_id, final_point} <- [
            {13_179, 6_825, 17_326, 74},
            {13_180, 6_826, 17_327, 84},
            {13_181, 6_827, 17_328, 97},
            {13_438, 6_942, 17_502, 66},
            {13_439, 6_941, 17_503, 76},
            {13_437, 6_943, 17_504, 92}
          ] do
        quest = Mangos.Repo.get!(Mangos.QuestTemplate, quest_id)
        assert {quest.req_item_id1, quest.req_item_count1, quest.method} == {item_id, 1, 0}

        points =
          Mangos.Repo.all(from(point in Mangos.ScriptWaypoint, where: point.entry == ^entry, select: point.point))

        assert 0 in points and final_point in points

        assert Mangos.Repo.exists?(
                 from(relation in Mangos.CreatureQuestRelation,
                   where: relation.id == ^entry and relation.quest == ^quest_id
                 )
               )
      end
    end

    test "the altar spell overrides supply one boss summon apiece" do
      for {spell_id, entry} <- [{21_249, 13_256}, {21_648, 13_419}] do
        assert [override] = Mangos.Repo.all(from(mod in Mangos.SpellEffectMod, where: mod.id == ^spell_id))

        assert {override.effect_index, override.effect, override.effect_misc_value, override.effect_implicit_target_a,
                override.effect_radius_index} == {1, 41, entry, 32, 12}
      end
    end

    test "offering quests and summoner routes match the two ten-player altars" do
      for {id, item, amount} <- [{7_385, 17_306, 5}, {6_801, 17_306, 1}, {7_386, 17_423, 5}, {6_881, 17_423, 1}] do
        quest = Mangos.Repo.get!(Mangos.QuestTemplate, id)
        assert {quest.req_item_id1, quest.req_item_count1} == {item, amount}
      end

      for {entry, last} <- [{13_236, 44}, {13_442, 50}, {13_256, 38}, {13_419, 39}] do
        points =
          Mangos.Repo.all(
            from(point in Mangos.ScriptWaypoint,
              where: point.entry == ^entry,
              select: point.point,
              order_by: point.point
            )
          )

        assert points == Enum.to_list(0..last)
      end

      for {entry, spell} <- [{178_465, 21_249}, {178_670, 21_648}] do
        [altar | _] = Mangos.Repo.all(from(altar in Mangos.GameObjectTemplate, where: altar.entry == ^entry))
        assert {altar.type, altar.data0, altar.data1} == {18, 10, spell}
      end
    end

    test "armor donations consume twenty scraps and every graveyard and tower guard tier has spawns" do
      quests = Mangos.Repo.all(from(quest in Mangos.QuestTemplate, where: quest.entry in [6_741, 6_781, 7_223, 7_224]))
      assert length(quests) == 4

      for quest <- quests do
        assert quest.req_item_id1 == 17_422
        assert quest.req_item_count1 == 20
      end

      events =
        Mangos.Repo.all(
          from(binding in Mangos.CreatureBattleground,
            join: creature in Mangos.Creature,
            on: creature.guid == binding.guid,
            where: creature.map == 30,
            select: {binding.event1, binding.event2}
          )
        )
        |> MapSet.new()

      for event <- 15..21, state <- 0..7 do
        assert MapSet.member?(events, {event, state})
      end

      for {_id, node} <- Node.all(), node.kind == :tower, tier <- 0..3 do
        for event <- Node.defender_events(node, tier), do: assert(MapSet.member?(events, event))
      end
    end

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
