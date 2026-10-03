defmodule ThistleTea.Game.Core.Quest.QuestFollower.Catalog do
  @moduledoc """
  Follower quests ported from the vmangos `FollowerAI` C++ scripts, keyed by
  quest id. Each keeps the script's accept actions, goal, and arrival. Idle
  chatter is left out, and so are the lapses a player must tend to on the
  way: Shay wandering off until her bell rings, Kerlonian falling asleep
  until the horn wakes him, and Ringo fainting until he drinks from the
  canteen. Kernobee walks out of Gnomeregan without the Alarm-a-bomb. The
  Threshwackonator starts from its key gossip and, once it reaches Gelkak,
  turns on the player instead of crediting them: killing it is the quest.
  Mist's script is missing from vmangos, so her return to Sentinel Arynia
  Cloudsbreak follows the ScriptDev2 `npc_mist` it came from.
  """

  alias ThistleTea.Game.Core.Quest.QuestFollower

  def all do
    [
      %QuestFollower{
        quest_id: 938,
        entry: 3568,
        goal: {3519, 10},
        accept: [{:faction, 79}],
        arrive: [{:say_by, 3519, 1330}, {:say, 1340}],
        despawn_ms: 3_000
      },
      %QuestFollower{
        quest_id: 1560,
        entry: 5955,
        goal: {6015, 5},
        accept: [{:faction, 290}],
        arrive: [
          {:after, 6_000, {:say, 2137}},
          {:after, 11_000, {:say_by, 6015, 2138}},
          {:after, 16_000, {:say, 2139}},
          {:after, 21_000, {:say_by, 6015, 2140}},
          {:after, 26_000, {:say, 2141}},
          {:after, 31_000, {:say_by, 6015, 2145}}
        ],
        despawn_ms: 32_000
      },
      %QuestFollower{
        quest_id: 2845,
        entry: 7774,
        goal: {7765, 20},
        distance: 5.0,
        accept: [{:say, 3921}, {:remove_unit_flags, 0x200}, {:faction, 10}],
        arrive: [{:say, 3917}, {:say_by, 7765, 3922}],
        despawn_ms: 30_000
      },
      %QuestFollower{
        quest_id: 5321,
        entry: 11_218,
        goal: {11_219, 25},
        accept: [{:stand, 0}, {:remove_unit_flags, 0x200}, {:say, 6540}, {:faction, 10}],
        arrive: [{:say, 6643}]
      },
      %QuestFollower{
        quest_id: 4491,
        entry: 9999,
        goal: {9997, 5},
        accept: [{:stand, 0}, {:remove_unit_flags, 0x200}, {:faction, 113}],
        arrive: [
          {:after, 1_000, {:say, 5402}},
          {:after, 4_000, {:say_by, 9997, 5405}},
          {:after, 9_000, {:say, 5403}},
          {:after, 10_000, {:say, 5393}},
          {:after, 10_000, {:stand, 3}},
          {:after, 19_000, {:stand, 0}},
          {:after, 20_000, {:say, 5404}},
          {:after, 23_000, {:say_by, 9997, 5406}}
        ],
        despawn_ms: 38_000
      },
      %QuestFollower{
        quest_id: 2904,
        entry: 7850,
        goal: {:point, {-330.92, -3.03, -152.85}, 10},
        accept: [{:say, 3881}, {:stand, 0}, {:remove_unit_flags, 0x200}],
        arrive: [{:say, 3929}],
        despawn_ms: 2_700
      },
      %QuestFollower{
        quest_id: 2078,
        entry: 6669,
        goal: {6667, 10},
        gossip: "[PH] Insert key",
        accept: [{:say, 3012}],
        arrive: [{:say_by, 6667, 2704}, {:faction, 14}, {:attack, :player}],
        credit?: false,
        despawn_ms: nil
      }
    ]
  end

  def get(quest_id), do: Enum.find(all(), &(&1.quest_id == quest_id))

  def summon_entries, do: all() |> Enum.flat_map(&QuestFollower.summon_entries/1) |> Enum.uniq()
end
