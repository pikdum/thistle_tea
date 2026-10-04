defmodule ThistleTea.Game.Core.AI.CreatureScript.AlteracValley do
  @moduledoc """
  vmangos's Alterac Valley leaders: the generals `npc_Vanndar` and
  `npc_DrekThar`, the captains `npc_Balinda` and `npc_Galvangar`, and the
  `npc_WarMaster` marshals and warmasters standing guard over the generals.

  Each leader fights through a handful of timed abilities and refuses to be
  drawn out of their keep or bunker: dragged past 35 yards from Vanndar's
  spot, 33 from Drek'Thar's, or 45 from a captain's, they give up the fight
  and go home. A general shouts one taunt when pulled out and another when
  the attackers die, and barks at the attackers as his health falls. While a
  general fights, the guards and marshals or warmasters linked to him within
  a hundred yards join in against his victim, and Drek'Thar raises his fallen
  wolves when he resets. Balinda holds her ground and casts while her victim
  is in sight and within 5 to 25 yards, and chases otherwise. A warmaster
  charges whoever it fights from 8 to 25 yards away and whirlwinds twice in
  a row.

  vmangos copies a general's whole threat list onto each linked defender;
  here they only go after his victim. vmangos also links just six of
  Drek'Thar's eight warmasters, and this port links all of them. Galvangar's
  Whirlwind and Balinda's Arcane Explosion wait for their victim to come
  within reach rather than for three attackers within six yards. Balinda's
  frostbolt is left out, because the spell vmangos casts is a melee-range
  stun, and whirlwinding leaders keep moving.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Combat
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @vanndar 11_948
  @drek_thar 11_946
  @balinda 11_949
  @galvangar 11_947
  @marshals Enum.to_list(14_762..14_769)
  @warmasters Enum.to_list(14_770..14_777)
  @veteran_guardsman 13_333
  @wolves [12_121, 12_122]

  @vanndar_home {722.4, -11.0, 50.7}
  @drek_thar_home {-1_370.9, -219.8, 98.5}
  @balinda_home {-57.7, -286.6, 15.6}
  @galvangar_home {-545.2, -165.3, 57.8}

  @vanndar_barks Enum.to_list(8_838..8_843)
  @drek_thar_barks Enum.to_list(8_844..8_849)
  @bark_thresholds [80, 60, 40, 20, 5]

  @whirlwind 13_736

  @at_least 1
  @at_most 2
  @creatures 2
  @linked_radius 100
  @rallied 1
  @unchecked [check_result?: false]

  @fighting 0
  @leashed 1

  @impl true
  def entries, do: [@vanndar, @drek_thar, @balinda, @galvangar] ++ @marshals ++ @warmasters

  @impl true
  def events(@vanndar = entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [Combat.talk(10_243)]),
      Combat.every(entry, 2, Combat.cast(19_135, :self), {12_000, 20_000}, {20_000, 30_000}),
      Combat.every(entry, 3, Combat.cast(19_136), 8_000, {8_000, 10_000}),
      Combat.every(entry, 4, Combat.cast(15_588, :self), 5_000, {5_000, 8_000})
    ] ++
      barks(entry, 5, @vanndar_barks) ++
      general(entry, 10, @vanndar_home, 35, [@veteran_guardsman | @marshals], leashed: 10_373, wiped: 10_374)
  end

  def events(@drek_thar = entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [Combat.talk(10_245)]),
      Combat.every(entry, 2, Combat.cast(@whirlwind, :self), {8_000, 12_000}, {12_000, 16_000}),
      Combat.every(entry, 3, Combat.cast(19_128), 18_000, {16_000, 24_000}),
      Combat.below_health(entry, 4, Combat.cast(28_747, :self), 30, 120_000)
    ] ++
      barks(entry, 5, @drek_thar_barks) ++
      general(entry, 10, @drek_thar_home, 33, @wolves ++ @warmasters, leashed: 10_377, wiped: 10_376) ++
      [CreatureScript.event(entry, 14, :evade, Enum.map(@wolves, &raise_fallen/1))]
  end

  def events(@balinda = entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [Combat.talk(10_054)]),
      Combat.below_health(entry, 2, Combat.talk(10_056), 50),
      Combat.every(entry, 3, Combat.cast(20_420), 0, {2_500, 3_000}),
      Combat.every(entry, 4, Combat.cast(22_746), 1_500, {12_000, 16_000}, condition: within(10)),
      Combat.every(entry, 5, Combat.cast(19_712), 2_000, {6_000, 9_000}, condition: within(6)),
      Combat.every(entry, 6, Combat.cast(15_534, :hostile_second_aggro), 1_750, {16_000, 20_000}),
      Combat.every(entry, 7, combat_movement(false), 1_000, 1_000, [condition: casting_spot()] ++ @unchecked),
      Combat.every(entry, 8, combat_movement(true), 1_000, 1_000, [condition: off_casting_spot()] ++ @unchecked),
      leash(entry, 9, @balinda_home, 45, [evade()]),
      CreatureScript.event(entry, 10, :evade, [Combat.talk(10_375), combat_movement(true)])
    ]
  end

  def events(@galvangar = entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [Combat.talk(10_055)]),
      Combat.below_health(entry, 2, Combat.talk(10_057), 50),
      Combat.every(entry, 3, Combat.cast(@whirlwind, :self), {8_000, 12_000}, {10_000, 16_000}, condition: within(6)),
      Combat.every(entry, 4, Combat.cast(19_134), {9_000, 17_000}, {24_000, 32_000}),
      Combat.every(entry, 5, Combat.cast(15_284), 4_000, {7_000, 9_000}),
      Combat.every(entry, 6, Combat.cast(16_856), 7_000, {9_000, 13_000}),
      leash(entry, 7, @galvangar_home, 45, [evade()]),
      CreatureScript.event(entry, 8, :evade, [Combat.talk(10_378)])
    ]
  end

  def events(entry) when entry in @marshals or entry in @warmasters do
    whirlwind = Combat.cast(@whirlwind, :self)

    [
      Combat.every(entry, 1, Combat.cast(22_911), 0, {12_000, 18_000}, condition: charge_reach()),
      Combat.every(entry, 2, Combat.cast(20_684), 8_000, {8_000, 10_000}),
      Combat.every(entry, 3, Combat.cast(23_511, :self), 4_000, {14_000, 20_000}),
      Combat.every(
        entry,
        4,
        [whirlwind, CreatureScript.timed([%{whirlwind | delay_ms: 2_000}])],
        12_000,
        {13_000, 15_000}
      ),
      Combat.below_health(entry, 5, Combat.cast(8_599, :self), 30, 120_000),
      CreatureScript.event(entry, 6, :evade, [%ScriptStep{command: :stop_scripts}])
    ]
  end

  defp barks(entry, index, texts) do
    taunt = texts |> Enum.map(&[Combat.talk(&1)]) |> CreatureScript.pick()

    @bark_thresholds
    |> Enum.with_index(index)
    |> Enum.map(fn {percent, index} -> Combat.below_health(entry, index, taunt, percent) end)
  end

  defp general(entry, index, home, radius, linked, leashed: leashed, wiped: wiped) do
    [
      leash(entry, index, home, radius, [set_phase(@leashed), evade()]),
      Combat.every(entry, index + 1, Enum.map(linked, &rally/1), 1_000, 1_000, @unchecked),
      CreatureScript.event(entry, index + 2, :evade, [Combat.talk(wiped)],
        inverse_phase_mask: CreatureScript.only_in_phases([@fighting])
      ),
      CreatureScript.event(entry, index + 3, :evade, [Combat.talk(leashed), set_phase(@fighting)],
        inverse_phase_mask: CreatureScript.only_in_phases([@leashed])
      )
    ]
  end

  defp leash(entry, index, {x, y, z}, radius, steps) do
    away = %Condition{
      type: :distance_to_position,
      value1: x,
      value2: y,
      value3: z,
      value4: radius,
      swap_targets?: true,
      reverse?: true
    }

    Combat.every(entry, index, steps, 1_000, 1_000, [condition: away] ++ @unchecked)
  end

  defp rally(linked_entry) do
    idle = %Condition{
      type: :and,
      children: [
        %Condition{type: :alive, swap_targets?: true},
        %Condition{type: :in_combat, swap_targets?: true, reverse?: true}
      ]
    }

    %ScriptStep{
      command: :start_script_for_all,
      datalong: @rallied,
      datalong2: @creatures,
      datalong3: linked_entry,
      datalong4: @linked_radius,
      sub_scripts: %{@rallied => [%ScriptStep{command: :attack_start, condition: idle}]}
    }
  end

  defp raise_fallen(wolf) do
    %ScriptStep{
      command: :start_script_for_all,
      datalong: @rallied,
      datalong2: @creatures,
      datalong3: wolf,
      datalong4: @linked_radius,
      sub_scripts: %{@rallied => [%ScriptStep{command: :respawn_creature}]}
    }
  end

  defp within(yards), do: %Condition{type: :distance_to_target, value1: yards, value2: @at_most}

  defp charge_reach do
    %Condition{
      type: :and,
      children: [
        %Condition{type: :distance_to_target, value1: 8, value2: @at_least},
        %Condition{type: :distance_to_target, value1: 25, value2: @at_most}
      ]
    }
  end

  defp casting_spot do
    %Condition{
      type: :and,
      children: [
        %Condition{type: :distance_to_target, value1: 5, value2: @at_least},
        %Condition{type: :distance_to_target, value1: 25, value2: @at_most},
        %Condition{type: :line_of_sight}
      ]
    }
  end

  defp off_casting_spot, do: %{casting_spot() | reverse?: true}

  defp combat_movement(chase?), do: %ScriptStep{command: :set_combat_movement, datalong: if(chase?, do: 1, else: 0)}
  defp set_phase(phase), do: %ScriptStep{command: :set_phase, datalong: phase}
  defp evade, do: %ScriptStep{command: :enter_evade}
end
