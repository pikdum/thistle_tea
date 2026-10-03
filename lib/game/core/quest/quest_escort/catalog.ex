defmodule ThistleTea.Game.Core.Quest.QuestEscort.Catalog do
  @moduledoc """
  Open-world escort quests ported from the vmangos `npc_escortAI` C++
  scripts, keyed by quest id. Each keeps the script's accept actions,
  waypoint actions, credit point, and summons; aggro chatter and
  dead-summon reactions are left out. Grark Lorkrub holds at each ambush
  until every summon is gone rather than counting kills, and his Searscale
  drakes appear where they strike instead of waiting there two points early.
  """

  alias ThistleTea.Game.Core.Quest.QuestEscort

  @immune_to_npc 0x200

  @defias_raider_positions [
    {-11_450.836, 1_569.755, 54.267, 4.230},
    {-11_449.697, 1_569.124, 54.421, 4.206},
    {-11_448.237, 1_568.307, 54.620, 4.206},
    {-11_448.037, 1_570.213, 54.961, 4.283},
    {-11_449.018, 1_570.738, 54.828, 4.220}
  ]

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
        accept: [{:say, 1189}, {:faction, 79}, {:remove_unit_flags, @immune_to_npc}],
        points: %{19 => [{:say, 1188}, :run]}
      },
      %QuestEscort{
        quest_id: 898,
        entry: 3465,
        credit_point: 53,
        accept: [{:faction, 232}, {:stand, 0}, {:remove_unit_flags, @immune_to_npc}, {:say, 1065}],
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
        accept: [{:faction, 10}, {:remove_unit_flags, @immune_to_npc}, {:say, 925}, {:emote, 6}],
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
        accept: [{:say, 5648}, {:faction, 232}, {:remove_unit_flags, @immune_to_npc}],
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
        accept: [{:say, 5926}, {:faction, 33}, {:remove_unit_flags, @immune_to_npc}],
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
        accept: [{:say, 816}, {:remove_unit_flags, @immune_to_npc}],
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
        accept: [{:faction, 10}, {:stand, 0}, {:remove_unit_flags, @immune_to_npc}]
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
        accept: [{:stand, 0}, {:faction, 113}, {:remove_unit_flags, @immune_to_npc}],
        points: %{
          0 => [{:say, 5062}],
          19 => [{:say, 5063}],
          37 => [{:say, 5156}]
        }
      },
      %QuestEscort{
        quest_id: 863,
        entry: 3439,
        credit_point: 24,
        accept: [{:say, 1031}, {:faction, 637}, :run],
        points: %{
          0 => [{:say, 1039}],
          8 => [{:after, 5_000, {:say, 1032}}],
          9 => [:walk],
          17 => [
            {:summon, 3282, {1128.489, -3037.611, 92.701, 1.472}, [script: [{:say, 1040}]] ++ venture_mercenary()},
            {:summon, 3282, {1160.172, -2980.168, 97.313, 3.690}, venture_mercenary()},
            {:after, 7_000, {:say, 1033}},
            {:after, 7_000, :run}
          ],
          24 => [
            {:after, 1_000, {:say, 1043}},
            {:after, 6_000, {:say, 1041}},
            {:after, 11_000, {:say, 1044}},
            {:after, 16_000, {:summon, 3451, {0.0, 0.0, 0.0, 0.0}, despawn: {:timed, 180_000}}},
            {:after, 16_000, {:stand, 7}},
            {:after, 16_000, {:faction, 0}}
          ]
        }
      },
      %QuestEscort{
        quest_id: 994,
        entry: 3692,
        credit_point: 15,
        accept: [{:stand, 0}, {:remove_unit_flags, @immune_to_npc}],
        points: %{
          2 => [{:say, 1237}],
          5 => [
            {:summon, 2171, {4630.2, 22.6, 70.1, 2.4}, blackwood()},
            {:summon, 2170, {4603.8, 53.5, 70.4, 5.4}, blackwood()}
          ],
          6 => [{:say, 1250}],
          11 => [
            {:summon, 2171, {4627.5, 100.4, 62.7, 5.8}, blackwood()},
            {:summon, 2170, {4692.8, 75.8, 56.7, 3.1}, blackwood()},
            {:summon, 2170, {4747.8, 152.8, 54.6, 2.4}, blackwood()},
            {:summon, 2170, {4711.7, 109.1, 53.5, 2.4}, blackwood()}
          ],
          13 => [
            {:summon, 2170, {4747.8, 152.8, 54.6, 2.4}, blackwood()},
            {:summon, 2170, {4711.7, 109.1, 53.5, 2.4}, blackwood()}
          ],
          15 => [
            {:after, 3_000, {:say, 1243}},
            {:after, 7_000, {:say_by, 3695, 1241}},
            {:after, 9_000, {:say, 1244}}
          ]
        }
      },
      %QuestEscort{
        quest_id: 995,
        entry: 3692,
        credit_point: 4,
        start_delay_ms: 9_000,
        accept: [
          {:stand, 0},
          {:faction, 35},
          :run,
          {:emote, 2},
          {:after, 1_000, {:say, 1236}},
          {:after, 5_000, {:add_aura, 10_849}}
        ],
        path: [
          {4604.54, -5.17, 69.51, 0},
          {4604.26, -2.02, 69.42, 0},
          {4607.75, 3.79, 70.13, 0},
          {4619.77, 27.47, 70.40, 0},
          {4640.33, 33.74, 68.22, 0}
        ]
      },
      %QuestEscort{
        quest_id: 976,
        entry: 4484,
        credit_point: 30,
        accept: [{:say, 1292}, {:faction, 10}, {:remove_unit_flags, @immune_to_npc}, :run],
        points: %{
          14 => [
            {:say, 1372},
            {:summon, 3879, {3525.05, 241.72, 10.87, 0.0}, feero_ambush()},
            {:summon, 3879, {3542.58, 226.54, 8.52, 0.0}, feero_ambush()},
            {:summon, 3879, {3544.25, 203.40, 9.53, 0.0}, feero_ambush()},
            {:summon, 3879, {3529.07, 185.87, 8.63, 0.0}, feero_ambush()}
          ],
          20 => [
            {:say, 1373},
            {:summon, 3893, {3769.14, 174.96, 8.71, 0.0}, feero_ambush()},
            {:summon, 3893, {3775.47, 161.02, 8.26, 0.0}, [script: [{:say, 1309}]] ++ feero_ambush()},
            {:summon, 3893, {3766.57, 148.57, 8.01, 0.0}, feero_ambush()}
          ],
          29 => [
            {:say, 1374},
            {:summon, 3899, {4243.12, 108.22, 38.12, 3.62}, [script: [{:say, 1313}]] ++ feero_ambush()},
            {:summon, 3898, {4240.95, 114.04, 38.35, 3.56}, feero_ambush()},
            {:summon, 3900, {4235.78, 118.09, 38.08, 4.12}, feero_ambush()}
          ]
        }
      },
      %QuestEscort{
        quest_id: 6544,
        entry: 12_858,
        credit_point: 20,
        accept: [{:say, 8284}, {:faction, 1174}, :run],
        points: %{
          1 => [{:say, 8278}],
          8 => [{:say, 8282}],
          19 => [
            {:summon, 12_860, {1776.73, -2049.06, 109.83, 1.54}, attack: :escort},
            {:summon, 12_896, {1774.64, -2049.41, 109.83, 1.40}, attack: :escort},
            {:summon, 12_897, {1778.73, -2049.50, 109.83, 1.67}, attack: :escort}
          ],
          20 => [{:say, 8280}],
          21 => [{:say, 8281}]
        }
      },
      %QuestEscort{
        quest_id: 1393,
        entry: 5391,
        credit_point: 20,
        accept: [{:faction, 495}, {:say, 1854}],
        points: %{
          20 => [{:say, 1855}, {:say, 2076}, :run, {:after, 15_000, {:say, 1856}}]
        }
      },
      %QuestEscort{
        quest_id: 2742,
        entry: 7780,
        credit_point: 17,
        accept: [{:faction, 33}, {:remove_unit_flags, @immune_to_npc}],
        points: %{
          1 => [{:say, 3787}],
          7 => highvale_ambush({191.296, -2839.329, 107.388, 0.0}),
          13 => highvale_ambush({70.972, -2848.675, 109.459, 0.0}),
          17 => [{:say, 3790}, :run, {:after, 3_000, {:say, 3817}}, {:after, 6_000, {:say, 3818}}]
        }
      },
      stinky(1222),
      stinky(1270),
      %QuestEscort{
        quest_id: 4261,
        entry: 9598,
        credit_point: 36,
        accept: [{:faction, 10}, {:say, 5004}],
        points: %{
          36 => [
            {:summon, 7139, {6573.321, -1195.213, 442.489, 0.0}, irontree(script: [{:say_by, 9598, 5473}])},
            {:summon, 7138, {6573.240, -1213.475, 443.643, 0.0}, irontree()},
            {:summon, 7138, {6583.354, -1209.811, 444.769, 0.0}, irontree()},
            {:say, 5008}
          ]
        }
      },
      %QuestEscort{
        quest_id: 5203,
        entry: 11_016,
        credit_point: 109,
        accept: [{:stand, 0}, {:remove_unit_flags, @immune_to_npc}],
        points: %{
          0 => [{:say, 6433}],
          14 => [{:say, 6456}],
          34 => [{:say, 6457}, :run],
          38 => [{:emote, 16}],
          39 => [{:add_aura, 18_163}],
          40 => [{:say, 6458}],
          41 => [
            {:say, 6460},
            {:summon, 9862, {5082.068, -490.084, 296.856, 5.15}, legionnaire()},
            {:summon, 9862, {5084.135, -489.187, 296.832, 5.15}, legionnaire()},
            {:summon, 9862, {5085.676, -488.518, 296.824, 5.15}, legionnaire()}
          ],
          43 => [:walk],
          104 => [{:say, 6461}],
          105 => [
            {:summon, 11_141, {4844.839, -395.763, 350.603, 6.25},
             attack: :escort, despawn: {:timed_or_dead, 120_000}, script: [{:say, 6466}]}
          ],
          106 => [{:say, 6463}],
          108 => [{:say, 6468}],
          109 => [:run]
        }
      },
      %QuestEscort{
        quest_id: 6132,
        entry: 12_277,
        credit_point: 12,
        points: %{
          1 => [{:say, 7540}, {:faction, 113}],
          4 => [
            {:summon, 4659, {-1289.492, 2646.650, 111.556, 0.0}, attack: :escort},
            {:summon, 4659, {-1293.492, 2642.650, 111.556, 0.0}, attack: :escort},
            {:summon, 4659, {-1304.730, 2677.163, 111.561, 0.0}, attack: :escort},
            {:summon, 4659, {-1308.730, 2673.163, 111.561, 0.0}, attack: :escort}
          ],
          9 => [
            {:summon, 4660, {-1389.194, 2429.465, 88.689, 0.0}, attack: :escort},
            {:summon, 4655, {-1397.194, 2429.465, 88.689, 0.0}, attack: :escort},
            {:summon, 4660, {-1391.194, 2432.965, 88.689, 0.0}, attack: :escort},
            {:summon, 4655, {-1395.194, 2432.965, 88.689, 0.0}, attack: :escort},
            {:summon, 4660, {-1391.194, 2425.965, 88.689, 0.0}, attack: :escort},
            {:summon, 4655, {-1395.194, 2425.965, 88.689, 0.0}, attack: :escort}
          ],
          12 => [{:say, 7544}, {:faction, 474}, :run],
          19 => [{:say, 7550}, {:after, 4_000, {:say, 7551}}, {:after, 9_000, {:say, 7552}}]
        }
      },
      %QuestEscort{
        quest_id: 1249,
        entry: 4962,
        giver: 4963,
        credit_point: nil,
        start_delay_ms: 750,
        accept: [{:invincible, 20}, {:add_aura, 6634}],
        points: %{3 => [:run, {:faction, 189}], 9 => [:fail]}
      },
      %QuestEscort{
        quest_id: 1651,
        entry: 6182,
        credit_point: 17,
        instant_respawn?: true,
        accept: [{:say, 2360}, :run],
        points: %{
          7 => [{:event_phase, 1} | defias_raiders(3)],
          8 => [{:event_phase, 2} | defias_raiders(4)],
          9 => [{:event_phase, 3} | defias_raiders(5)],
          10 => [:walk],
          11 => [{:say, 3090}]
        }
      },
      %QuestEscort{
        quest_id: 4121,
        entry: 9520,
        credit_point: 45,
        credit_delay_ms: 23_000,
        points: %{
          1 => [{:say, 4903}],
          7 => [{:say, 4904}],
          12 =>
            [{:say, 4905}] ++
              blackrock_ambush([
                {9522, {-7844.3, -1521.6, 139.2, 0.0}},
                {9522, {-7860.4, -1507.8, 141.0, 6.0}},
                {9605, {-7845.6, -1508.1, 138.8, 6.1}},
                {9605, {-7859.8, -1521.8, 139.2, 6.2}}
              ]) ++ [{:hold, [{:say, 4906}]}],
          24 =>
            [{:say, 4907}] ++
              blackrock_ambush([
                {9522, {-8035.3, -1222.2, 135.5, 5.1}},
                {9522, {-8009.5, -1222.1, 139.2, 3.9}},
                {7042, {-8037.5, -1216.9, 135.8, 5.1}},
                {7042, {-8007.1, -1219.4, 140.1, 3.9}}
              ]) ++ [{:hold, [{:say, 4908}]}],
          30 =>
            [{:say, 4909}] ++
              blackrock_ambush([
                {7046, {-7900.1, -1133.14, 193.98, 3.0}},
                {7046, {-7898.8, -1125.1, 193.9, 3.0}},
                {7046, {-7895.6, -1119.5, 194.5, 3.1}}
              ]) ++ [{:hold, [{:say, 4911}]}],
          36 => [{:say, 4912}],
          45 => [
            {:say, 4913},
            {:summon, 9538, {-7532.3, -1029.4, 258.0, 2.7}, despawn: {:timed, 40_000}},
            {:summon, 9539, {-7532.8, -1032.9, 258.2, 2.5}, despawn: {:timed, 40_000}},
            {:hold, []},
            {:after, 3_000, {:say_by, 9539, 4928}},
            {:after, 3_000, {:stand, 8}},
            {:after, 8_000, {:say_by, 9539, 4929}},
            {:after, 12_000, {:say_by, 9538, 4930}},
            {:after, 15_000, {:say_by, 9539, 4932}},
            {:after, 18_000, {:say_by, 9539, 4931}},
            {:after, 18_000, {:emote_by, 9538, 37}},
            {:after, 23_000, {:stand, 7}},
            {:after, 23_000, {:say_by, 9539, 4933}},
            {:after, 23_500, :die}
          ]
        }
      }
    ]
  end

  def get(quest_id), do: Enum.find(all(), &(&1.quest_id == quest_id))

  def summon_entries, do: all() |> Enum.flat_map(&QuestEscort.summon_entries/1) |> Enum.uniq()

  defp gravelflint, do: [attack: :player, despawn: {:timed_out_of_combat, 30_000}]

  defp blackrock_ambush(summons) do
    Enum.map(summons, fn {entry, position} ->
      {:summon, entry, position, attack: :player, despawn: {:timed_out_of_combat, 200_000}}
    end)
  end

  defp vengeful_surge, do: [attack: :escort, despawn: {:timed_or_corpse, 600_000}]

  defp venture_mercenary, do: [attack: :escort, despawn: {:timed_out_of_combat, 120_000}]

  defp blackwood, do: [attack: :escort, despawn: {:timed_out_of_combat, 20_000}]

  defp feero_ambush, do: [attack: :player, despawn: {:timed_or_dead, 20_000}]

  defp irontree(opts \\ []), do: [attack: :escort, despawn: {:timed_out_of_combat, 60_000}] ++ opts

  defp legionnaire, do: [attack: :escort, despawn: {:timed_or_dead, 120_000}]

  defp highvale_ambush(position) do
    opts = [attack: :escort, despawn: {:timed_or_corpse, 60_000}]
    [{:summon, 2694, position, opts}, {:summon, 2691, position, opts}, {:summon, 2691, position, opts}]
  end

  defp stinky(quest_id) do
    %QuestEscort{
      quest_id: quest_id,
      entry: 4880,
      credit_point: 24,
      accept: [{:faction, 113}, {:stand, 0}],
      points: %{
        0 => [{:say, 1610}],
        4 => [{:say, 1611}],
        8 => [{:say, 1612}],
        16 => [{:after, 3_000, {:say, 1614}}, {:after, 4_000, {:say, 1615}}],
        18 => [{:stand, 8}, {:after, 1_000, {:stand, 0}}, {:after, 2_000, {:say, 1617}}],
        24 => [{:say, 1618}]
      }
    }
  end

  defp defias_raiders(count) do
    @defias_raider_positions
    |> Enum.take(count)
    |> Enum.map(&{:summon, 6180, &1, attack: :escort, despawn: {:timed_out_of_combat, 30_000}})
  end

  defp bandits(positions) do
    Enum.map(positions, fn {x, y, z} ->
      {:summon, 10_758, {x, y, z, 0.0}, despawn: {:timed_or_dead, 20_000}}
    end)
  end
end
