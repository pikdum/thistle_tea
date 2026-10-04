defmodule ThistleTea.Game.Core.AI.CreatureScript.BlackrockDepths do
  @moduledoc """
  vmangos's Blackrock Depths boss AIs: `boss_high_interrogator_gerstahn`,
  the Ring of Law's `boss_gorosh_the_dervish`, `boss_grizzle` and
  `boss_anubshiah`, `boss_magmus`, `boss_general_angerforge`, Doom'rel of the
  Seven, the Grim Guzzler's `boss_plugger_spazzring` and `mob_phalanx`, and
  `boss_emperor_dagran_thaurissan` with Princess Moira (`boss_moira_bronzebeard`,
  shared by the High Priestess of Thaurissan).

  Each fights with its own timed abilities, several turning more dangerous
  below half health. General Angerforge sounds the alarm under thirty percent
  and his reserves pour in every three minutes after, and Doom'rel calls his
  voidwalkers once at half health. The Emperor rallies the throne room as he
  fights and every twenty seconds after, and his death leaves Moira shaken
  and no longer hostile. Plugger keeps his demon armor up and grumbles about
  his customers between fights.

  High Justice Grimstone (`npc_grimstone`) runs the Ring of Law for
  `InstanceScript.BlackrockDepths`: he sentences the challengers, calls two
  packs of a random kind of beast through the beast gate, and once they are
  dead walks to the far gate and calls a random champion.

  Moira mends any injured ally rather than only the Emperor, and the Hand of
  Thaurissan strikes the Emperor's victim even when no other player stands
  with it.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Combat
  alias ThistleTea.Game.Core.AI.CreatureScript.Route
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @gerstahn 9_018
  @gorosh 9_027
  @grizzle 9_028
  @anubshiah 9_031
  @magmus 9_938
  @angerforge 9_033
  @doomrel 9_039
  @plugger 9_499
  @phalanx 9_502
  @emperor 9_019
  @moira 8_929
  @high_priestess 10_076
  @grimstone 10_096

  @ring_path [
    {604.803, -191.082, -54.0586},
    {604.073, -222.107, -52.7438},
    {621.4, -214.499, -52.8145},
    {601.301, -198.557, -53.9503},
    {631.818, -180.548, -52.6548},
    {627.39, -201.076, -52.6929}
  ]
  @ring_holds [0, 1, 2, 4, 5]
  @hold_ms 1_800_000
  @ring_mobs [8_925, 8_926, 8_927, 8_928, 8_933, 8_932]
  @ring_champions [9_027, 9_028, 9_029, 9_030, 9_031, 9_032]
  @beast_gate {608.96, -235.322, -53.907, 1.857}
  @champion_gate {644.3, -175.989, -53.739, 3.418}
  @ring_center {596.285156, -188.698944, -54.132176, 0.0}
  @arena_stage 46
  @ring_of_law 0
  @done 3
  @teleport 6_422
  @script_route 5
  @dead_despawn 7
  @charge_in 1

  @anvilrage_reservist 8_901
  @anvilrage_medic 8_894
  @reserves [
    {@anvilrage_reservist, {716.8168, 23.03471, -45.34414, 3.159046}},
    {@anvilrage_reservist, {719.8195, 25.4425, -45.32854, 3.193953}},
    {@anvilrage_reservist, {720.0683, 22.93752, -45.3414, 3.159046}},
    {@anvilrage_reservist, {719.9299, 19.80474, -45.35873, 3.106686}},
    {@anvilrage_reservist, {724.4819, 25.27536, -45.31646, 3.193953}},
    {@anvilrage_reservist, {724.4958, 22.62163, -45.32786, 3.159046}},
    {@anvilrage_reservist, {724.7056, 19.89114, -45.33829, 3.124139}},
    {@anvilrage_reservist, {728.701, 18.92765, -46.00228, 3.106686}},
    {@anvilrage_medic, {728.5464, 21.52842, -45.8926, 3.141593}},
    {@anvilrage_medic, {728.6478, 24.58055, -45.94735, 3.176499}}
  ]

  @triggered 0x02
  @random_target 4
  @timed_or_corpse_despawn 2
  @reserves_ms 30_000
  @visible_range 166.0
  @moira_reach 100
  @mana_users 0x004
  @friendly 35

  @impl CreatureScript
  def entries,
    do: [
      @gerstahn,
      @gorosh,
      @grizzle,
      @anubshiah,
      @magmus,
      @angerforge,
      @doomrel,
      @plugger,
      @phalanx,
      @emperor,
      @moira,
      @high_priestess,
      @grimstone
    ]

  @impl CreatureScript
  def events(@gerstahn = entry) do
    [
      Combat.every(entry, 1, Combat.cast(14_032, :hostile_random), 4_000, 7_000),
      Combat.every(entry, 2, Combat.cast(14_033, :hostile_random), 14_000, 10_000),
      Combat.every(entry, 3, Combat.cast(13_704), 32_000, 30_000),
      Combat.every(entry, 4, Combat.cast(12_040, :self), 8_000, 25_000)
    ]
  end

  def events(@gorosh = entry) do
    [
      Combat.every(entry, 1, Combat.cast(15_589, :self), 12_000, 15_000),
      Combat.every(entry, 2, Combat.cast(15_708), 22_000, 15_000),
      Combat.below_health(entry, 3, Combat.cast(21_049, :self), 51, 45_000)
    ]
  end

  def events(@grizzle = entry) do
    [
      Combat.every(entry, 1, Combat.cast(6_524, :self), 12_000, 8_000),
      Combat.below_health(entry, 2, [Combat.cast(8_269, :self), Combat.talk(7_797)], 51, 15_000)
    ]
  end

  def events(@anubshiah = entry) do
    [
      Combat.every(entry, 1, Combat.cast(15_472), 7_000, 7_000),
      Combat.every(entry, 2, Combat.cast(15_470, :hostile_random), 24_000, 18_000),
      Combat.every(entry, 3, Combat.cast(12_493), 12_000, 45_000),
      Combat.every(entry, 4, Combat.cast(13_787, :self), 3_000, 300_000),
      Combat.every(entry, 5, Combat.cast(15_471, :hostile_random), 16_000, 12_000)
    ]
  end

  def events(@magmus = entry) do
    [
      Combat.every(entry, 1, Combat.cast(13_900), 5_000, 6_000),
      Combat.below_health(entry, 2, Combat.cast(24_375), 51, 8_000)
    ]
  end

  def events(@angerforge = entry) do
    [
      Combat.every(entry, 1, Combat.cast(15_572), {5_000, 10_000}, {5_000, 15_000}),
      Combat.below_health(entry, 2, [Combat.talk(5_286) | Enum.map(@reserves, &reserve/1)], 30, 180_000)
    ]
  end

  def events(@doomrel = entry) do
    [
      Combat.every(entry, 1, Combat.cast(15_245), 10_000, 12_000),
      Combat.every(entry, 2, Combat.cast(12_742, :hostile_random), 18_000, 25_000),
      Combat.every(entry, 3, Combat.cast(12_493), 5_000, 45_000),
      Combat.every(entry, 4, Combat.cast(13_787, :self), 16_000, 300_000),
      Combat.below_health(entry, 5, Combat.cast(15_092, :self, @triggered), 50)
    ]
  end

  def events(@plugger = entry) do
    [
      Combat.every(entry, 1, Combat.cast(8_994, :hostile_random_not_top), {9_000, 15_000}, {26_000, 28_000}),
      Combat.every(entry, 2, Combat.cast(12_742), {5_000, 8_000}, 25_000),
      Combat.every(entry, 3, Combat.cast(12_739), 1_000, {3_600, 6_300}),
      Combat.every(entry, 4, mana_curse(13_338), 14_000, {19_000, 31_000}),
      Combat.every_out_of_combat(entry, 5, Combat.cast(13_787, :self), 1_000, 300_000),
      Combat.every_out_of_combat(entry, 6, grumble(), 10_000, {30_000, 35_000})
    ]
  end

  def events(@phalanx = entry) do
    [
      Combat.every(entry, 1, Combat.cast(15_588), 12_000, 10_000),
      Combat.below_health(entry, 2, Combat.cast(15_285), 51, 15_000),
      Combat.every(entry, 3, Combat.cast(14_099), 15_000, 10_000)
    ]
  end

  def events(@emperor = entry) do
    rally = %ScriptStep{command: :call_for_help, position: {@visible_range, 0.0, 0.0, 0.0}}

    [
      CreatureScript.event(entry, 1, :aggro, [Combat.talk(5_457), rally]),
      CreatureScript.event(entry, 2, :kill, [Combat.talk(5_431)]),
      Combat.every(entry, 3, Combat.cast(17_492), {5_000, 7_500}, {10_000, 15_000}),
      Combat.every(entry, 4, Combat.cast(15_636, :self), 18_000, 18_000),
      Combat.every(entry, 5, rally, 8_000, 20_000),
      CreatureScript.event(entry, 6, :death, Enum.map(moira_shaken(), &at_moira/1))
    ]
  end

  def events(entry) when entry in [@moira, @high_priestess] do
    [
      Combat.every(entry, 1, Combat.cast(15_587), 16_000, 14_000),
      Combat.every(entry, 2, Combat.cast(15_654), 2_000, 18_000),
      Combat.every(entry, 3, Combat.cast(10_934), 8_000, 10_000),
      Combat.every(entry, 4, %{Combat.cast(15_586, :friendly_injured) | target_param1: 40}, 12_000, 10_000)
    ]
  end

  def events(@grimstone), do: []

  @impl CreatureScript
  def routes do
    path =
      @ring_path
      |> Enum.with_index()
      |> Enum.map(fn {{x, y, z}, index} -> {x, y, z, if(index in @ring_holds, do: @hold_ms, else: 0)} end)

    [%Route{entry: @grimstone, path: path, points: ring_points()}]
  end

  defp ring_points do
    %{
      0 => [Combat.talk(5_442), CreatureScript.timed([at(5_000, resume(1))])],
      1 => [
        Combat.talk(5_443),
        CreatureScript.timed([
          at(7_000, stage(1)),
          at(7_000, Combat.cast(@teleport, :self)),
          at(10_000, resume(2)),
          at(10_000, beasts(fn _index -> [] end)),
          at(29_000, beasts(&second_pack_words/1))
        ])
      ],
      4 => [
        Combat.talk(5_446),
        CreatureScript.timed([
          at(5_000, stage(2)),
          at(8_000, Combat.cast(@teleport, :self)),
          at(10_000, champion())
        ])
      ],
      5 => [%ScriptStep{command: :set_instance_data, datalong: @ring_of_law, datalong2: @done}]
    }
  end

  defp beasts(words) do
    @ring_mobs
    |> Enum.map(fn entry ->
      pack =
        [{0, 0}, {1, 3_000}, {2, 3_000}, {3, 7_000}]
        |> Enum.flat_map(fn {index, at_ms} ->
          Enum.map([arena_summon(entry, @beast_gate) | words.(index)], &at(at_ms, &1))
        end)

      [CreatureScript.timed(pack)]
    end)
    |> CreatureScript.pick()
    |> hd()
  end

  defp second_pack_words(2), do: [Combat.talk(5_444)]
  defp second_pack_words(3), do: [Combat.talk(5_445)]
  defp second_pack_words(_index), do: []

  defp champion do
    @ring_champions
    |> Enum.map(&[arena_summon(&1, @champion_gate)])
    |> CreatureScript.pick()
    |> hd()
  end

  defp arena_summon(entry, position) do
    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      dataint2: @charge_in,
      dataint3: -1,
      dataint4: @dead_despawn,
      position: position,
      sub_scripts: %{
        @charge_in => [
          %ScriptStep{command: :set_home_position, position: @ring_center},
          %ScriptStep{command: :zone_combat_pulse, datalong: 1}
        ]
      }
    }
  end

  defp stage(value), do: %ScriptStep{command: :set_instance_data, datalong: @arena_stage, datalong2: value}

  defp resume(point), do: %ScriptStep{command: :start_waypoints, datalong: @script_route, datalong2: point}

  defp at(delay_ms, %ScriptStep{} = step), do: %{step | delay_ms: delay_ms}

  defp reserve({entry, position}) do
    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      datalong2: @reserves_ms,
      dataint3: @random_target,
      dataint4: @timed_or_corpse_despawn,
      position: position
    }
  end

  defp mana_curse(spell_id), do: %{Combat.cast(spell_id, :hostile_random) | target_param1: @mana_users}

  defp grumble, do: %ScriptStep{command: :talk, dataint: 5_310, dataint2: 5_308, dataint3: 5_307, dataint4: 5_309}

  defp moira_shaken do
    [CreatureScript.faction(@friendly), %ScriptStep{command: :enter_evade}, Combat.talk(5_429)]
  end

  defp at_moira(%ScriptStep{} = step) do
    %{
      step
      | target_type: :nearest_creature_with_entry,
        target_param1: @moira,
        target_param2: @moira_reach,
        swap_final?: true,
        condition: %Condition{type: :alive, swap_targets?: true}
    }
  end
end
