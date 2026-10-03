defmodule ThistleTea.Game.Core.AI.CreatureScript.ScarletMonastery do
  @moduledoc """
  The vmangos Scarlet Monastery boss AIs: Houndmaster Loksey, Arcanist Doan,
  Herod and the trainees his death calls, Interrogator Vishas, and High
  Inquisitor Fairbanks.

  Doan wraps himself in an Arcane Bubble at half health and detonates it.
  Herod spins in place while Whirlwind lasts and frenzies at half health;
  when he falls, twenty Scarlet Trainees pour down into his chamber, and
  each runs once it is badly hurt. The Scarlet Myrmidons vmangos posts on
  the stairs to punish kiting Herod out of his room are not called, and his
  Rushing Charge opens the fight but does not chase down distant targets.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @loksey 3_974
  @herod 3_975
  @vishas 3_983
  @fairbanks 4_542
  @doan 6_487
  @trainee 6_575

  @trainee_script 657_501
  @timed_or_dead_despawn 1
  @pathfinding_run 5
  @herod_chamber {1_965.09, -431.61, 6.79, 0.0}
  @trainee_spawn {1_939.18, -431.58, 17.09, 6.22}

  @impl CreatureScript
  def entries, do: [@loksey, @herod, @vishas, @fairbanks, @doan, @trainee]

  @impl CreatureScript
  def events(@loksey = entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [talk(2_655), cast_self(17_164)]),
      timer(entry, 2, [cast_self(6_742)], {20_000, 20_000}, {20_000, 20_000})
    ]
  end

  def events(@doan = entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [talk(6_199)]),
      timer(entry, 2, [cast(13_323, :hostile_random_not_top)], {20_000, 20_000}, {20_000, 20_000}),
      timer(entry, 3, [cast(8_988, :victim)], {15_000, 15_000}, {15_000, 20_000}),
      timer(entry, 4, [cast(9_433, :victim)], {3_000, 3_000}, {8_000, 8_000}),
      CreatureScript.event(
        entry,
        5,
        :hp,
        [
          cast_self(9_438),
          CreatureScript.timed([%{talk(6_200) | delay_ms: 500}, %{cast_self(9_435) | delay_ms: 500}])
        ],
        param1: 50,
        param2: 0,
        repeatable?: false
      )
    ]
  end

  def events(@herod = entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [talk(6_194), cast_self(8_260)]),
      CreatureScript.event(entry, 2, :kill, [talk(6_196)]),
      CreatureScript.event(entry, 3, :hp, [cast_self(8_269), talk(7_798), talk(6_195)],
        param1: 50,
        param2: 0,
        repeatable?: false
      ),
      timer(entry, 4, [cast(15_496, :victim)], {12_000, 12_000}, {12_000, 12_000}),
      timer(
        entry,
        5,
        [
          cast(8_989, :victim),
          talk(6_534),
          %ScriptStep{command: :set_combat_movement, datalong: 0},
          CreatureScript.timed([%ScriptStep{delay_ms: 11_000, command: :set_combat_movement, datalong: 1}])
        ],
        {10_000, 20_000},
        {20_000, 30_000}
      ),
      CreatureScript.event(entry, 6, :death, [trainees()])
    ]
  end

  def events(@trainee = entry) do
    [CreatureScript.event(entry, 1, :hp, [%ScriptStep{command: :flee}], param1: 15, param2: 0, repeatable?: false)]
  end

  def events(@vishas = entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [talk(6_204)]),
      CreatureScript.event(entry, 2, :kill, [talk(6_205)]),
      CreatureScript.event(entry, 3, :hp, [talk(6_206)], param1: 60, param2: 0, repeatable?: false),
      CreatureScript.event(entry, 4, :hp, [talk(6_207)], param1: 30, param2: 0, repeatable?: false),
      timer(entry, 5, [cast(2_767, :victim)], {5_000, 5_000}, {5_000, 15_000})
    ]
  end

  def events(@fairbanks = entry) do
    [
      CreatureScript.event(entry, 1, :hp, [cast_self(12_039)],
        param1: 25,
        param2: 0,
        param3: 30_000,
        param4: 30_000,
        repeatable?: true
      ),
      CreatureScript.event(entry, 2, :hp, [cast_self(11_647)], param1: 25, param2: 0, repeatable?: false),
      timer(entry, 3, [cast(12_096, :hostile_random_not_top)], {40_000, 40_000}, {40_000, 40_000}),
      timer(entry, 4, [cast(8_399, :victim)], {30_000, 30_000}, {30_000, 30_000}),
      timer(entry, 5, [cast(15_090, :hostile_random)], {20_000, 20_000}, {30_000, 30_000}),
      timer(entry, 6, [cast(8_282, :victim)], {10_000, 10_000}, {25_000, 25_000})
    ]
  end

  defp trainees do
    %ScriptStep{
      command: :summon_creature,
      datalong: @trainee,
      datalong2: 180_000,
      dataint2: @trainee_script,
      dataint4: @timed_or_dead_despawn,
      position: @trainee_spawn,
      scatter: 3.0,
      count: 20,
      sub_scripts: %{
        @trainee_script => [%ScriptStep{command: :move_to, datalong3: @pathfinding_run, position: @herod_chamber}]
      }
    }
  end

  defp timer(entry, index, steps, {initial_min, initial_max}, {repeat_min, repeat_max}) do
    CreatureScript.event(entry, index, :timer_in_combat, steps,
      param1: initial_min,
      param2: initial_max,
      param3: repeat_min,
      param4: repeat_max
    )
  end

  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}
  defp cast(spell_id, target_type), do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_type: target_type}
  defp cast_self(spell_id), do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_self?: true}
end
