defmodule ThistleTea.Game.Core.AI.CreatureScript.Scholomance do
  @moduledoc """
  The vmangos Scholomance boss AIs: the six room bosses whose deaths call
  Darkmaster Gandling, Ras Frostwhisper, and Jandice Barov with her
  illusions.

  The room bosses fight on fixed timers, as their `boss_*` scripts do; their
  deaths reach the instance script through the creature events every
  instance mob reports, standing in for the scripts setting their encounter
  done. Malicia heals herself in bursts of three Flash Heals, the counter her
  script keeps.

  Jandice turns unselectable, sheds her threat, and calls ten illusions onto
  random attackers, coming back three seconds later. vmangos also hides her
  model, makes her friendly while hidden, and dispels the illusions once she
  takes 500 damage; here she stays visible among her illusions, keeps her
  faction so she never drops out of the fight, and the illusions fade after
  their minute. They cleave, as `mob_illusionofjandicebarov` does, but
  without its immunity to magic damage.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @theolen 11_261
  @malicia 10_505
  @illucia 10_502
  @alexei 10_504
  @polkelt 10_901
  @ravenian 10_507
  @ras 10_508
  @jandice 10_503
  @illusion 11_439

  @frenzy_emote 7_797
  @unit_flags 46
  @not_selectable 0x02000000
  @add_flags 1
  @remove_flags 2
  @triggered 0x02
  @aura_not_present 0x20
  @hostile_random 4
  @timed_or_corpse_despawn 2

  @impl CreatureScript
  def entries, do: [@theolen, @malicia, @illucia, @alexei, @polkelt, @ravenian, @ras, @jandice, @illusion]

  @impl CreatureScript
  def events(@theolen = entry) do
    [
      timer(entry, 1, [cast(16_509, :victim)], 8_000, 10_000),
      timer(entry, 2, [cast(18_103, :victim), drop_victim_threat(-100.0)], 9_000, 10_000),
      CreatureScript.event(entry, 3, :hp, [cast_self(8_269), %ScriptStep{command: :talk, dataint: @frenzy_emote}],
        param1: 26,
        param2: 0,
        param3: 120_000,
        param4: 120_000,
        repeatable?: true
      )
    ]
  end

  def events(@malicia = entry) do
    [
      timer(entry, 1, [cast(17_831, :victim)], 4_000, 65_000),
      timer(entry, 2, [cast(11_672, :hostile_random)], 8_000, 24_000),
      timer(entry, 3, [cast_self(10_929)], 15_000, 10_000),
      timer(
        entry,
        4,
        [cast_self(10_917), CreatureScript.timed(flash_heals())],
        22_000,
        40_000
      ),
      timer(entry, 5, [cast_self(9_889)], 25_000, 30_000)
    ]
  end

  def events(@illucia = entry) do
    [
      timer(entry, 1, [cast(18_671, :victim)], 18_000, 30_000),
      timer(entry, 2, [cast(20_603, :hostile_random)], 9_000, 12_000),
      timer(entry, 3, [cast(15_487, :victim)], 5_000, 14_000),
      timer(entry, 4, [cast(6_215, :victim)], 30_000, 30_000)
    ]
  end

  def events(@alexei = entry) do
    [
      timer(entry, 1, [cast(15_570, :hostile_random)], 7_000, 12_000),
      timer(entry, 2, [cast(17_820, :victim)], 15_000, 20_000)
    ]
  end

  def events(@polkelt = entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [
        %{cast_self(12_038) | datalong2: Bitwise.bor(@triggered, @aura_not_present)}
      ]),
      timer(entry, 2, [cast(24_928, :victim)], 38_000, 32_000),
      timer(entry, 3, [cast(8_245, :victim)], 45_000, 25_000),
      timer(entry, 4, [cast(18_151, :victim)], 35_000, 38_000)
    ]
  end

  def events(@ravenian = entry) do
    [
      timer(entry, 1, [cast(15_550, :victim)], 24_000, 10_000),
      timer(entry, 2, [cast(20_691, :victim)], 15_000, 7_000),
      timer(entry, 3, [cast(25_174, :victim)], 40_000, 20_000),
      timer(entry, 4, [cast(10_101, :victim)], 32_000, 12_000)
    ]
  end

  def events(@ras = entry) do
    ice_armor = %{cast_self(18_100) | datalong2: @triggered}

    [
      CreatureScript.event(entry, 1, :spawned, [ice_armor]),
      CreatureScript.event(entry, 2, :evade, [ice_armor]),
      timer(entry, 3, [cast_self(18_100)], 2_000, 180_000),
      timer(entry, 4, [cast(21_369, :hostile_random)], 8_000, 8_000),
      timer(entry, 5, [cast(18_763, :victim)], 18_000, 24_000),
      timer(entry, 6, [cast(26_070, :victim)], 45_000, 30_000),
      timer(entry, 7, [cast(18_099, :victim)], 12_000, 14_000),
      timer(entry, 8, [cast(8_398, :victim)], 24_000, 15_000)
    ]
  end

  def events(@jandice = entry) do
    [
      timer(entry, 1, [cast(16_098, :victim)], 10_000, 30_000),
      timer(entry, 2, vanish(), 15_000, 25_000),
      CreatureScript.event(entry, 3, :death, [%{cast_self(26_096) | datalong2: @triggered}])
    ]
  end

  def events(@illusion = entry) do
    [
      CreatureScript.event(entry, 1, :timer_in_combat, [cast(15_584, :victim)],
        param1: 2_000,
        param2: 8_000,
        param3: 5_000,
        param4: 15_000
      )
    ]
  end

  defp flash_heals, do: [%{cast_self(10_917) | delay_ms: 5_000}, %{cast_self(10_917) | delay_ms: 10_000}]

  defp vanish do
    [
      %ScriptStep{command: :interrupt_casts},
      unit_flags(@not_selectable, @add_flags),
      drop_victim_threat(-99.0),
      %ScriptStep{command: :set_melee_attack, datalong: 0},
      %ScriptStep{
        command: :summon_creature,
        datalong: @illusion,
        datalong2: 60_000,
        dataint3: @hostile_random,
        dataint4: @timed_or_corpse_despawn,
        scatter: 10.0,
        count: 10
      },
      CreatureScript.timed([
        %{unit_flags(@not_selectable, @remove_flags) | delay_ms: 3_000},
        %ScriptStep{delay_ms: 3_000, command: :set_melee_attack, datalong: 1}
      ])
    ]
  end

  defp timer(entry, index, steps, initial_ms, repeat_ms) do
    CreatureScript.event(entry, index, :timer_in_combat, steps,
      param1: initial_ms,
      param2: initial_ms,
      param3: repeat_ms,
      param4: repeat_ms
    )
  end

  defp cast(spell_id, target_type), do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_type: target_type}
  defp cast_self(spell_id), do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_self?: true}

  defp drop_victim_threat(percent),
    do: %ScriptStep{command: :modify_threat, datalong: 1, position: {percent, 0.0, 0.0, 0.0}}

  defp unit_flags(flags, mode),
    do: %ScriptStep{command: :modify_flags, datalong: @unit_flags, datalong2: flags, datalong3: mode}
end
