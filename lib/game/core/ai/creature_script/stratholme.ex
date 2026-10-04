defmodule ThistleTea.Game.Core.AI.CreatureScript.Stratholme do
  @moduledoc """
  vmangos's Stratholme boss AIs: `boss_magistrate_barthilas`,
  `boss_baroness_anastari`, `boss_nerubenkan`, `boss_maleki_the_pallid`,
  `boss_ramstein_the_gorger`, `boss_timmy_the_cruel`,
  `boss_dathrohan_balnazzar`, `boss_cannon_master_willey`, and
  `boss_postmaster_malown`.

  Each fights with its own timed abilities. Nerub'enkan raises a swarm of
  Crypt Scarabs or one Undead Scarab against a random attacker every few
  seconds. Maleki stands back and casts, closing in only on a victim out of
  his reach, and once badly hurt drains his victim's mana, or the life of a
  warrior or rogue. Ramstein's Knockout wipes his victim's threat. Cannon
  Master Willey calls three Crimson Riflemen to the courtyard every ten
  seconds, and they leave once the fight is over. Grand Crusader Dathrohan
  reveals himself as the dreadlord Balnazzar at 40 percent health, healing to
  full and fighting on with shadow magic, sleeping a random attacker and
  dominating his second-highest threat; he becomes Dathrohan again if he
  leaves the fight. His death raises skeletons across the square.

  Encasing Webs and Ice Tomb leave their victim's threat alone, where vmangos
  wipes it for the duration and restores it afterwards. Barthilas keeps his
  Furious Anger stacked for the whole fight instead of stopping after
  twenty-six casts, and his corpse keeps his undead form. Anastari does not
  possess players, Maleki ignores his own mana when deciding to drain and
  leaves a caster who has run dry undrained, Willey always fights in melee
  range, and Dathrohan's sleep leaves its victim's threat alone.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Combat
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @barthilas 10_435
  @anastari 10_436
  @nerubenkan 10_437
  @maleki 10_438
  @ramstein 10_439
  @timmy 10_808
  @dathrohan 10_812
  @balnazzar 10_813
  @willey 10_997
  @malown 11_143

  @crypt_scarab 10_577
  @undead_scarab 10_876
  @skeletal_guardian 10_390
  @skeletal_berserker 10_391
  @crimson_rifleman 11_054

  @triggered 0x02
  @aura_not_present 0x20
  @victim 1
  @random_target 4
  @no_attack -1
  @timed_out_of_combat_despawn 4
  @dead_despawn 7
  @rally 1
  @unchecked [check_result?: false]

  @transformed 1
  @draining 1
  @shadow_shock 1
  @deep_sleep 2
  @psychic_scream 3
  @mind_control 4

  @manaless_classes 0x9

  @rifleman_spots [
    {3_537.2725, -2_958.18, 125.001015, 0.592007},
    {3_542.206299, -2_965.929932, 125.001015, 0.592007},
    {3_539.41748, -2_959.667236, 125.001015, 0.592007},
    {3_540.651855, -2_964.519043, 125.001015, 0.592007},
    {3_531.927246, -2_962.977295, 125.001015, 0.592007},
    {3_538.094697, -2_963.123291, 125.001015, 0.592007},
    {3_535.727539, -2_969.776123, 125.001015, 0.592007},
    {3_532.15625, -2_966.162354, 125.001015, 0.592007},
    {3_533.202148, -2_969.437744, 125.001015, 0.592007}
  ]

  @skeleton_spots [
    {3_444.156, -3_090.626, 135.002, 2.240},
    {3_449.123, -3_087.009, 135.002, 2.240},
    {3_446.246, -3_093.466, 135.002, 2.240},
    {3_451.160, -3_089.904, 135.002, 2.240},
    {3_457.995, -3_080.916, 135.002, 3.784},
    {3_454.302, -3_076.330, 135.002, 3.784},
    {3_460.975, -3_078.901, 135.002, 3.784},
    {3_457.338, -3_073.979, 135.002, 3.784},
    {3_479.995, -3_062.916, 135.002, 3.784},
    {3_476.302, -3_058.330, 135.002, 3.784},
    {3_482.975, -3_060.901, 135.002, 3.784},
    {3_479.338, -3_055.979, 135.002, 3.784},
    {3_501.995, -3_074.916, 134.997, 3.784},
    {3_498.302, -3_070.330, 134.997, 3.784},
    {3_504.975, -3_072.901, 134.997, 3.784},
    {3_501.338, -3_067.979, 134.997, 3.784},
    {3_530.995, -3_053.916, 134.997, 3.784},
    {3_527.302, -3_049.330, 134.997, 3.784},
    {3_533.975, -3_051.901, 134.997, 3.784},
    {3_530.338, -3_046.979, 134.997, 3.784},
    {3_559.995, -3_065.916, 134.997, 3.784},
    {3_556.302, -3_061.330, 134.997, 3.784},
    {3_562.975, -3_063.901, 134.997, 3.784},
    {3_559.338, -3_058.979, 134.997, 3.784},
    {3_591.995, -3_085.916, 135.664, 3.784},
    {3_588.302, -3_081.330, 135.664, 3.784},
    {3_594.975, -3_083.901, 135.664, 3.784},
    {3_591.338, -3_078.979, 135.664, 3.784},
    {3_624.995, -3_091.916, 134.122, 3.784},
    {3_621.302, -3_087.330, 134.122, 3.784},
    {3_627.975, -3_089.901, 134.122, 3.784},
    {3_624.338, -3_084.979, 134.122, 3.784}
  ]

  @impl CreatureScript
  def entries, do: [@barthilas, @anastari, @nerubenkan, @maleki, @ramstein, @timmy, @dathrohan, @willey, @malown]

  @impl CreatureScript
  def events(@barthilas = entry) do
    [
      Combat.every(entry, 1, Combat.cast(16_791, :self), 5_000, 4_000, @unchecked),
      Combat.every(entry, 2, Combat.cast(16_793), 16_000, 15_000, @unchecked),
      Combat.every(entry, 3, Combat.cast(10_887), 12_000, 15_000, @unchecked),
      Combat.every(entry, 4, Combat.cast(14_099), 8_000, 20_000, @unchecked)
    ]
  end

  def events(@anastari = entry) do
    [
      Combat.every(entry, 1, Combat.cast(16_565), 1_000, 4_000),
      Combat.every(entry, 2, Combat.cast(16_867, :victim, @aura_not_present), 11_000, 18_000),
      Combat.every(entry, 3, Combat.cast(18_327, :self), 13_000, {13_000, 18_000})
    ]
  end

  def events(@nerubenkan = entry) do
    raise_scarabs =
      CreatureScript.pick_weighted([
        {1, [scarabs(@crypt_scarab, 4)]},
        {1, [scarabs(@crypt_scarab, 6)]},
        {1, [scarabs(@crypt_scarab, 8)]},
        {3, [scarabs(@undead_scarab, 1)]}
      ])

    [
      Combat.every(entry, 1, Combat.cast(4_962), 7_000, {10_000, 15_000}),
      Combat.every(entry, 2, Combat.cast(6_016), 15_000, {15_000, 20_000}),
      Combat.every(entry, 3, raise_scarabs, 3_000, {6_000, 10_000})
    ]
  end

  def events(@maleki = entry) do
    has_mana = %Condition{type: :mana_percent, value1: 1, value2: 1}
    manaless = %Condition{type: :race_class, value2: @manaless_classes}

    [
      CreatureScript.event(entry, 1, :aggro, [combat_movement(false)]),
      Combat.every(entry, 2, Combat.cast(17_503), 1_000, {3_500, 4_500}),
      Combat.every(entry, 3, Combat.cast(16_869), 12_000, {20_000, 25_000}),
      drain(entry, 4, 17_243, has_mana),
      drain(entry, 5, 17_238, manaless),
      reach(entry, 6, 0, 40, false, [0]),
      reach(entry, 7, 40, 500, true, [0]),
      reach(entry, 8, 0, 20, false, [@draining]),
      reach(entry, 9, 20, 500, true, [@draining]),
      CreatureScript.event(entry, 10, :evade, [set_phase(0)])
    ]
  end

  def events(@ramstein = entry) do
    knockout = [
      Combat.cast(17_307),
      %ScriptStep{command: :modify_threat, datalong: @victim, position: {-100.0, 0.0, 0.0, 0.0}}
    ]

    [
      Combat.every(entry, 1, Combat.cast(5_568, :self), 3_000, 7_000, @unchecked),
      Combat.every(entry, 2, knockout, 12_000, 10_000)
    ]
  end

  def events(@timmy = entry) do
    [
      Combat.every(entry, 1, Combat.cast(17_470), 7_000, 12_000),
      Combat.below_health(entry, 2, Combat.cast(8_599, :self, @triggered), 10)
    ]
  end

  def events(@dathrohan = entry) do
    as_dathrohan = [inverse_phase_mask: CreatureScript.only_in_phases([0])]
    as_balnazzar = [inverse_phase_mask: CreatureScript.only_in_phases([@transformed])]

    [
      CreatureScript.event(entry, 1, :aggro, [Combat.talk(6_441)]),
      Combat.every(entry, 2, Combat.cast(17_287), 6_000, {15_000, 20_000}),
      Combat.every(entry, 3, Combat.cast(17_286, :self), 8_000, 12_000, as_dathrohan),
      Combat.every(entry, 4, Combat.cast(17_281), 12_000, 15_000, as_dathrohan),
      Combat.every(entry, 5, Combat.cast(17_284), 18_000, 15_000, as_dathrohan),
      Combat.below_health(entry, 6, transform(), 40),
      CreatureScript.event(
        entry,
        7,
        :script_event,
        chain(@shadow_shock, Combat.cast(17_399), 11_000),
        [param1: @shadow_shock] ++ as_balnazzar
      ),
      CreatureScript.event(
        entry,
        8,
        :script_event,
        chain(@deep_sleep, Combat.cast(12_098, :hostile_random_not_top, @aura_not_present), 15_000),
        [param1: @deep_sleep] ++ as_balnazzar
      ),
      CreatureScript.event(
        entry,
        9,
        :script_event,
        chain(@psychic_scream, Combat.cast(13_704, :self), 20_000),
        [param1: @psychic_scream] ++ as_balnazzar
      ),
      CreatureScript.event(
        entry,
        10,
        :script_event,
        mind_control(),
        [param1: @mind_control] ++ as_balnazzar
      ),
      CreatureScript.event(entry, 11, :death, [Combat.talk(6_442) | Enum.flat_map(@skeleton_spots, &skeleton/1)]),
      CreatureScript.event(entry, 12, :evade, [
        %ScriptStep{command: :stop_scripts},
        set_phase(0),
        %ScriptStep{command: :update_entry, datalong: @dathrohan},
        clear_spell_list()
      ])
    ]
  end

  def events(@willey = entry) do
    riflemen =
      @rifleman_spots
      |> Enum.with_index()
      |> Enum.map(fn {_spot, index} -> Enum.map([0, 1, 3], &rifleman(Enum.at(@rifleman_spots, rem(index + &1, 9)))) end)
      |> CreatureScript.pick()

    [
      Combat.every(entry, 1, Combat.cast(15_615), {5_000, 10_000}, 12_000),
      Combat.every(entry, 2, Combat.cast(10_101), {15_000, 20_000}, {15_000, 20_000}),
      Combat.every(entry, 3, Combat.cast(20_463), 1_000, {2_500, 3_500}),
      Combat.every(entry, 4, riflemen, 5_000, 10_000)
    ]
  end

  def events(@malown = entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [Combat.talk(6_504)]),
      CreatureScript.event(entry, 2, :kill, [Combat.talk(6_530)]),
      Combat.every(entry, 3, Combat.cast(7_713), 19_000, 19_000, [chance: 65] ++ @unchecked),
      Combat.every(entry, 4, Combat.cast(6_253), 8_000, 8_000, [chance: 45] ++ @unchecked),
      Combat.every(entry, 5, Combat.cast(8_552), 20_000, 20_000, [chance: 3] ++ @unchecked),
      Combat.every(entry, 6, Combat.cast(12_889), 22_000, 22_000, [chance: 3] ++ @unchecked),
      Combat.every(entry, 7, Combat.cast(17_831), 25_000, 25_000, [chance: 5] ++ @unchecked)
    ]
  end

  defp scarabs(entry, count) do
    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      datalong2: 10_000,
      dataint3: @random_target,
      dataint4: @timed_out_of_combat_despawn,
      scatter: 10.0,
      count: count
    }
  end

  defp drain(entry, index, spell_id, victim) do
    Combat.below_health(entry, index, [set_phase(@draining), Combat.cast(spell_id)], 60, {12_000, 18_000},
      condition: victim
    )
  end

  defp reach(entry, index, min_yards, max_yards, chase?, phases) do
    CreatureScript.event(entry, index, :range, [combat_movement(chase?)],
      param1: min_yards,
      param2: max_yards,
      param3: 1_000,
      param4: 1_000,
      inverse_phase_mask: CreatureScript.only_in_phases(phases)
    )
  end

  defp transform do
    [
      %ScriptStep{command: :interrupt_casts},
      Combat.cast(17_288, :self, @triggered),
      %ScriptStep{command: :update_entry, datalong: @balnazzar},
      clear_spell_list(),
      set_phase(@transformed),
      CreatureScript.timed([
        %{Combat.talk(6_447) | delay_ms: 4_000},
        send_self(@shadow_shock, 7_000),
        send_self(@deep_sleep, 13_000),
        send_self(@psychic_scream, 16_000),
        send_self(@mind_control, 22_000)
      ])
    ]
  end

  defp mind_control do
    [Combat.cast(17_405, :hostile_second_aggro)] ++
      CreatureScript.pick(
        for delay <- [25_000, 27_500, 30_000], do: [CreatureScript.timed([send_self(@mind_control, delay)])]
      )
  end

  defp chain(event_id, %ScriptStep{} = cast, repeat_ms),
    do: [cast, CreatureScript.timed([send_self(event_id, repeat_ms)])]

  defp send_self(event_id, delay_ms),
    do: %ScriptStep{command: :send_script_event, datalong: event_id, target_self?: true, delay_ms: delay_ms}

  defp skeleton(spot) do
    CreatureScript.pick(
      for entry <- [@skeletal_berserker, @skeletal_guardian], do: [summon(entry, spot, 3_600_000, @dead_despawn)]
    )
  end

  defp rifleman(spot) do
    %{
      summon(@crimson_rifleman, spot, 10_000, @timed_out_of_combat_despawn)
      | dataint2: @rally,
        sub_scripts: %{@rally => [%ScriptStep{command: :zone_combat_pulse, datalong: 1}]}
    }
  end

  defp summon(entry, spot, despawn_ms, despawn_type) do
    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      datalong2: despawn_ms,
      dataint3: @no_attack,
      dataint4: despawn_type,
      position: spot
    }
  end

  defp combat_movement(chase?), do: %ScriptStep{command: :set_combat_movement, datalong: if(chase?, do: 1, else: 0)}
  defp set_phase(phase), do: %ScriptStep{command: :set_phase, datalong: phase}
  defp clear_spell_list, do: %ScriptStep{command: :creature_spells, datalong: 0}
end
