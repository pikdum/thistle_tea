defmodule ThistleTea.Game.Core.Quest.QuestEscort.Catalog do
  @moduledoc """
  Open-world escort quests ported from the vmangos `npc_escortAI` C++
  scripts, keyed by quest id. Each keeps the script's accept actions,
  waypoint actions, credit point, and summons; aggro chatter and
  dead-summon reactions are left out.
  """

  alias ThistleTea.Game.Core.Quest.QuestEscort

  def all do
    [
      %QuestEscort{
        quest_id: 309,
        entry: 1379,
        credit_point: 23,
        points: %{
          19 => [
            {:say, 510},
            {:summon, 2149, {-5691.93, -3745.91, 319.159, 2.21}, attack: :escort, script: [{:say, 1936}]},
            {:summon, 2149, {-5706.98, -3745.39, 318.728, 1.04}, attack: :escort}
          ],
          23 => [{:say, 498}]
        }
      },
      %QuestEscort{
        quest_id: 435,
        entry: 1978,
        credit_point: 13,
        accept: [{:say, 481}, {:faction, 232}],
        points: %{
          0 => [{:say, 482}],
          13 => [{:say, 484}],
          14 => [{:say_by, 1950, 534}],
          15 => [{:say, 535}],
          16 => [{:say, 536}],
          24 => [{:say, 537}],
          25 => [{:say_by, 1951, 539}],
          26 => [{:say, 538}]
        }
      },
      %QuestEscort{
        quest_id: 945,
        entry: 3584,
        credit_point: 17,
        accept: [{:say, 1189}, {:faction, 79}],
        points: %{19 => [{:say, 1188}, :run]}
      },
      %QuestEscort{
        quest_id: 898,
        entry: 3465,
        credit_point: 53,
        accept: [{:faction, 232}, {:stand, 0}, {:say, 1065}],
        points: %{
          16 => [{:say, 1066}],
          17 => [{:say, 1067}],
          18 => [{:say, 1068}],
          37 => [{:say, 1069}],
          47 => [{:say, 1070}],
          53 => [{:say, 1071}]
        }
      },
      %QuestEscort{
        quest_id: 731,
        entry: 2917,
        credit_point: 48,
        instant_respawn?: true,
        accept: [{:faction, 10}, {:say, 925}, {:emote, 6}],
        points: %{
          5 => [{:say, 926}],
          9 => [{:say, 927}, {:emote, 6}],
          10 => [{:summon, 2158, {4639.86, 631.96, 7.48, 4.7}, gravelflint()}],
          13 => [{:say, 928}, {:emote, 6}],
          18 => [{:say, 929}],
          19 => [{:say, 930}, {:emote, 6}],
          20 => [
            {:summon, 2158, {4610.03, 642.37, 6.31, 0.0}, gravelflint()},
            {:summon, 2158, {4610.03, 644.37, 6.31, 0.0}, gravelflint()}
          ],
          30 => [{:say, 931}, {:say, 932}],
          31 => [{:say, 933}],
          36 => [{:say, 935}, {:emote, 6}],
          37 => [
            {:summon, 2159, {4564.11, 553.67, 5.21, 2.26}, gravelflint()},
            {:summon, 2160, {4569.33, 549.43, 5.61, 2.4}, gravelflint()}
          ],
          47 => [{:say, 936}, {:emote, 1}],
          48 => [{:say, 937}]
        }
      },
      %QuestEscort{
        quest_id: 6482,
        entry: 12_818,
        credit_point: 25,
        accept: [{:faction, 33}, {:stand, 0}],
        points: %{
          13 => [
            {:summon, 3922, {3449.218, -587.825, 174.979, 4.714}, attack: :escort},
            {:summon, 3921, {3446.385, -587.831, 175.186, 4.714}, attack: :escort},
            {:summon, 3926, {3444.219, -587.835, 175.381, 4.714}, attack: :escort}
          ],
          19 => [
            {:summon, 3922, {3508.344, -492.024, 186.929, 4.145}, attack: :escort},
            {:summon, 3921, {3506.266, -490.531, 186.740, 4.239}, attack: :escort},
            {:summon, 3926, {3503.682, -489.394, 186.630, 4.349}, attack: :escort}
          ],
          25 => [{:remove_aura, 20_514}, {:say, 8265}]
        }
      },
      %QuestEscort{
        quest_id: 4770,
        entry: 10_427,
        credit_point: 27,
        accept: [{:say, 5648}, {:faction, 232}],
        points: %{
          15 => [
            {:say, 5654},
            {:summon, 4107, {-4990.606, -906.057, -5.343, 0.0}, despawn: {:timed_or_dead, 20_000}},
            {:summon, 4107, {-4970.241, -927.378, -4.951, 0.0}, despawn: {:timed_or_dead, 20_000}},
            {:summon, 4107, {-4985.364, -952.528, -5.199, 0.0}, despawn: {:timed_or_dead, 20_000}}
          ],
          26 => [{:say, 5683}]
        }
      },
      %QuestEscort{
        quest_id: 4904,
        entry: 10_646,
        credit_point: 45,
        accept: [{:say, 5926}, {:faction, 33}],
        points: %{
          8 => [{:say, 5927} | bandits([{-4905.479, -2062.733, 84.352}, {-4915.201, -2073.528, 84.733}])],
          14 => [{:say, 5928} | bandits([{-4878.883, -1986.948, 91.966}, {-4877.504, -1966.113, 91.859}])],
          21 => [{:say, 5929} | bandits([{-4767.985, -1873.169, 90.192}, {-4788.861, -1888.008, 89.888}])],
          45 => [{:say, 5930}]
        }
      },
      %QuestEscort{
        quest_id: 660,
        entry: 2713,
        credit_point: 34,
        accept: [{:say, 816}],
        points: %{
          9 => [{:say, 817}],
          16 => [{:say, 818}, {:say, 819}],
          17 => [{:say, 821}],
          18 => [{:say, 822}, :run],
          33 => [{:say, 892}, {:say, 891}]
        }
      },
      %QuestEscort{
        quest_id: 1440,
        entry: 5644,
        credit_point: 18,
        accept: [{:faction, 10}, {:stand, 0}]
      },
      %QuestEscort{
        quest_id: 665,
        entry: 2768,
        credit_point: 20,
        instant_respawn?: true,
        accept: [{:faction, 113}, {:say, 845}],
        points: %{
          4 => [{:say, 846}],
          5 => [{:say, 847}],
          8 => [{:say, 848}],
          9 => [
            {:summon, 2776, {-2056.41, -2144.01, 20.59, 5.70}, vengeful_surge()},
            {:summon, 2776, {-2050.17, -2140.02, 19.54, 5.17}, vengeful_surge()}
          ],
          10 => [{:say, 849}],
          11 => [{:say, 850}, :run],
          19 => [{:say, 851}],
          20 => [{:say, 889}, {:say, 890}]
        }
      },
      %QuestEscort{
        quest_id: 4245,
        entry: 9623,
        credit_point: 37,
        accept: [{:stand, 0}, {:faction, 113}],
        points: %{
          0 => [{:say, 5062}],
          19 => [{:say, 5063}],
          37 => [{:say, 5156}]
        }
      }
    ]
  end

  def get(quest_id), do: Enum.find(all(), &(&1.quest_id == quest_id))

  def summon_entries, do: all() |> Enum.flat_map(&QuestEscort.summon_entries/1) |> Enum.uniq()

  defp gravelflint, do: [attack: :player, despawn: {:timed_out_of_combat, 30_000}]

  defp vengeful_surge, do: [attack: :escort, despawn: {:timed_or_corpse, 600_000}]

  defp bandits(positions) do
    Enum.map(positions, fn {x, y, z} ->
      {:summon, 10_758, {x, y, z, 0.0}, despawn: {:timed_or_dead, 20_000}}
    end)
  end
end
