defmodule ThistleTea.Game.Core.AI.CreatureScript.MoltenCore do
  @moduledoc """
  vmangos's Molten Core lieutenants: `boss_lucifron`, `boss_gehennas`,
  `boss_shazzrah`, `boss_garr` with `mob_firesworn`, `boss_baron_geddon`,
  `boss_sulfuron`, and `boss_golemagg` with `mob_core_rager`. Magmadar runs
  on EventAI, and Majordomo Executus and Ragnaros have their own scripts.

  Most lieutenants pull the whole raid into the fight, then work through
  their timed curses and blasts. Shazzrah blinks to a random player every
  half minute, forgetting all threat and attacking them. Garr's Firesworn
  erupt as they die, and each death enrages Garr further; after six minutes
  he forces a random Firesworn to erupt every twenty seconds. Baron Geddon
  roots himself in an Inferno that burns hotter with every pulse, and below
  five percent health he stops fighting to perform one last service for
  Ragnaros with Armageddon. Sulfuron inspires himself and a nearby
  Flamewaker Priest. Golemagg keeps the Core Ragers beside him empowered
  with his trust, calls them to his side below a tenth of his health, and
  shakes the ground every five seconds from then on. While he lives, his
  ragers refuse to drop below half health; the instance script takes them
  with him when he falls.

  vmangos also binds the Firesworn to Garr with Separation Anxiety, has
  Golemagg evade when a rager is dragged a hundred yards from him, and turns
  Geddon to face his Living Bomb's victim, which this port leaves out. Garr
  may force a stunned Firesworn to erupt, Geddon keeps meleeing inside his
  Inferno, and Sulfuron inspires any priest rather than one missing the
  buff.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Combat
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @lucifron 12_118
  @gehennas 12_259
  @shazzrah 12_264
  @garr 12_057
  @firesworn 12_099
  @geddon 12_056
  @sulfuron 12_098
  @flamewaker_priest 11_662
  @golemagg 11_988
  @core_rager 11_672

  @triggered 0x02
  @aura_not_present 0x20
  @player 0x2
  @all_attackers 8
  @unchecked [check_result?: false]
  @lone_script 1

  @erupting 1
  @armageddon 1
  @earthquake 1

  @golemagg_field 3
  @failed 2
  @at_most 2
  @percent 1

  @impl CreatureScript
  def entries, do: [@lucifron, @gehennas, @shazzrah, @garr, @firesworn, @geddon, @sulfuron, @golemagg, @core_rager]

  @impl CreatureScript
  def events(@lucifron = entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [zone_combat()]),
      Combat.every(entry, 2, Combat.cast(19_702, :self), 10_000, 20_000),
      Combat.every(entry, 3, Combat.cast(19_703, :self), 20_000, 15_000),
      Combat.every(entry, 4, Combat.cast(19_460, :hostile_random), 6_000, 6_000)
    ]
  end

  def events(@gehennas = entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [zone_combat()]),
      Combat.every(entry, 2, Combat.cast(19_717, :hostile_random), {6_000, 12_000}, {6_000, 12_000}),
      Combat.every(entry, 3, Combat.cast(19_716, :self), {5_000, 10_000}, {25_000, 30_000}),
      Combat.every(entry, 4, Combat.cast(19_728, :hostile_random), {3_000, 6_000}, {3_000, 6_000}),
      Combat.every(entry, 5, Combat.cast(19_729), {3_000, 6_000}, {3_000, 6_000})
    ]
  end

  def events(@shazzrah = entry) do
    [
      Combat.every(entry, 1, Combat.cast(19_712), 2_000, {3_000, 5_000}),
      Combat.every(entry, 2, Combat.cast(19_713, :victim, @aura_not_present), 10_000, 20_000),
      Combat.every(entry, 3, Combat.cast(19_714, :self), 5_000, {7_000, 14_000}),
      Combat.every(entry, 4, Combat.cast(19_715), 15_000, {16_000, 18_000}),
      Combat.every(entry, 5, [Combat.cast(23_138, :self, @triggered), blink()], {25_000, 30_000}, {25_000, 35_000})
    ]
  end

  def events(@garr = entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [zone_combat()]),
      Combat.every(entry, 2, Combat.cast(19_492, :self), 15_000, {15_000, 20_000}),
      Combat.every(entry, 3, Combat.cast(19_496, :self), 10_000, {10_000, 15_000}),
      Combat.every(entry, 4, [erupt_firesworn()], 360_000, 20_000, @unchecked),
      CreatureScript.event(entry, 5, :hit_by_spell, [Combat.cast(19_516, :self, @triggered)], param1: 19_515)
    ]
  end

  def events(@firesworn = entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [Combat.cast(3_391, :self, @triggered + @aura_not_present), zone_combat()]),
      Combat.every(entry, 2, Combat.cast(15_732), 10_000, 20_000),
      CreatureScript.event(entry, 3, :hit_by_spell, [set_phase(@erupting), Combat.cast(20_483, :self, @triggered)],
        param1: 20_482
      ),
      CreatureScript.event(entry, 4, :death, [enrage_garr()]),
      CreatureScript.event(entry, 5, :death, [Combat.cast(19_497, :self, @triggered)],
        inverse_phase_mask: CreatureScript.only_in_phases([0])
      )
    ]
  end

  def events(@geddon = entry) do
    fighting = [inverse_phase_mask: CreatureScript.only_in_phases([0])]

    [
      CreatureScript.event(entry, 1, :aggro, [zone_combat()]),
      Combat.every(entry, 2, random_player(20_475), {15_000, 20_000}, {12_000, 15_000}, fighting),
      Combat.every(entry, 3, Combat.cast(19_659, :self), {10_000, 15_000}, {20_000, 30_000}, fighting),
      Combat.every(entry, 4, Combat.cast(19_695, :self), {18_000, 24_000}, {18_000, 24_000}, fighting),
      Combat.below_health(entry, 5, armageddon(), 5, nil, fighting),
      CreatureScript.event(entry, 6, :evade, [set_phase(0), combat_movement(true)])
    ]
  end

  def events(@sulfuron = entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [zone_combat()]),
      Combat.every(entry, 2, Combat.cast(19_778), 15_000, {15_000, 20_000}),
      Combat.every(entry, 3, [inspire_priest(), Combat.cast(19_779, :self)], 13_000, {20_000, 26_000}),
      Combat.every(entry, 4, Combat.cast(19_780), 6_000, {12_000, 15_000}),
      Combat.every(entry, 5, Combat.cast(19_781, :hostile_random), 2_000, {12_000, 16_000}),
      Combat.every(entry, 6, Combat.cast(19_777), 10_000, {15_000, 18_000})
    ]
  end

  def events(@golemagg = entry) do
    [
      Combat.every(entry, 1, Combat.cast(20_228, :hostile_random), 7_000, 7_000),
      Combat.every(entry, 2, Combat.cast(20_553, :self), 10_000, 2_000),
      Combat.below_health(entry, 3, [Combat.cast(20_544, :self), quake_in(5_000)], 10),
      CreatureScript.event(entry, 4, :script_event, [Combat.cast(19_798), quake_in(5_000)], param1: @earthquake)
    ]
  end

  def events(@core_rager = entry) do
    master_alive = %Condition{type: :instance_data, value1: @golemagg_field, value2: @failed, value3: @at_most}

    [
      CreatureScript.event(entry, 1, :spawned, [%ScriptStep{command: :invincibility, datalong: 50, datalong2: @percent}]),
      Combat.every(entry, 2, Combat.cast(19_820), 7_000, 10_000),
      Combat.below_health(entry, 3, [Combat.talk(7_865), Combat.cast(17_683, :self, @triggered)], 50, 1_000,
        condition: master_alive
      )
    ]
  end

  def events(_entry), do: []

  defp blink do
    lone_script(:hostile_random, @player, 0, [
      %ScriptStep{command: :teleport_to, at_target?: true},
      %ScriptStep{command: :modify_threat, datalong: @all_attackers, position: {-100.0, 0.0, 0.0, 0.0}},
      %ScriptStep{command: :attack_start}
    ])
  end

  defp erupt_firesworn do
    lone_script(:random_creature_with_entry, @firesworn, 150, [
      Combat.talk(8_254),
      Combat.cast(20_482, :provided, @triggered)
    ])
  end

  defp inspire_priest do
    lone_script(:random_creature_with_entry, @flamewaker_priest, 45, [Combat.cast(19_779, :provided, @triggered)])
  end

  defp enrage_garr,
    do: %{Combat.cast(19_515, :nearest_creature_with_entry, @triggered) | target_param1: @garr, target_param2: 150}

  defp lone_script(target_type, param1, param2, steps) do
    %ScriptStep{
      command: :start_script,
      datalong: @lone_script,
      dataint: 100,
      target_type: target_type,
      target_param1: param1,
      target_param2: param2,
      sub_scripts: %{@lone_script => steps}
    }
  end

  defp armageddon do
    [
      %ScriptStep{command: :interrupt_casts},
      combat_movement(false),
      Combat.cast(20_478, :self, @triggered),
      Combat.talk(8_253),
      set_phase(@armageddon)
    ]
  end

  defp quake_in(delay_ms) do
    CreatureScript.timed([
      %ScriptStep{command: :send_script_event, datalong: @earthquake, target_self?: true, delay_ms: delay_ms}
    ])
  end

  defp random_player(spell_id), do: %{Combat.cast(spell_id, :hostile_random) | target_param1: @player}
  defp zone_combat, do: %ScriptStep{command: :zone_combat_pulse}
  defp combat_movement(chase?), do: %ScriptStep{command: :set_combat_movement, datalong: if(chase?, do: 1, else: 0)}
  defp set_phase(phase), do: %ScriptStep{command: :set_phase, datalong: phase}
end
