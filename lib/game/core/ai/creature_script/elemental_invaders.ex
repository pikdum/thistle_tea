defmodule ThistleTea.Game.Core.AI.CreatureScript.ElementalInvaders do
  @moduledoc """
  vmangos `npc_invaderAI`: the Blazing, Whirling, Thundering, and Watery
  Invaders that Elemental Invasion rifts call into Un'Goro, Silithus,
  Azshara, and Winterspring. Fire and air invaders keep an elemental shield
  up and answer a victim standing close with Blast Wave or Whirlwind; earth
  invaders knock a meleeing victim down and Earth Shock it; water invaders
  chill a meleeing victim and Frost Shock it.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @whirling 14_455
  @watery 14_458
  @blazing 14_460
  @thundering 14_462

  @chilled 20_005
  @frost_shock 19_133
  @knockdown 11_428
  @earth_shock 23_114
  @whirlwind 17_207
  @lightning_shield 12_550
  @blast_wave 23_113
  @fire_shield 11_968

  @aura_not_present 0x20

  @impl CreatureScript
  def entries, do: [@whirling, @watery, @blazing, @thundering]

  @impl CreatureScript
  def events(@blazing) do
    [
      shield(@blazing, @fire_shield, 6_000, 8_000),
      CreatureScript.event(@blazing, 2, :range, [cast_self(@blast_wave)],
        param1: 0,
        param2: 10,
        param3: 13_000,
        param4: 18_000
      )
    ]
  end

  def events(@whirling) do
    [
      shield(@whirling, @lightning_shield, 10_000, 12_000),
      CreatureScript.event(@whirling, 2, :range, [cast_self(@whirlwind)],
        param1: 0,
        param2: 8,
        param3: 9_000,
        param4: 12_000
      )
    ]
  end

  def events(@thundering) do
    [
      melee_range(@thundering, 1, @knockdown, 11_000, 15_000),
      CreatureScript.event(@thundering, 2, :timer_in_combat, [cast_victim(@earth_shock)],
        param1: 3_000,
        param2: 5_000,
        param3: 9_000,
        param4: 13_000
      )
    ]
  end

  def events(@watery) do
    [
      melee_range(@watery, 1, @chilled, 5_000, 8_000),
      CreatureScript.event(@watery, 2, :timer_in_combat, [cast_victim(@frost_shock)],
        param1: 3_000,
        param2: 5_000,
        param3: 8_000,
        param4: 15_000
      )
    ]
  end

  def events(_entry), do: []

  defp shield(entry, spell_id, repeat_min, repeat_max) do
    CreatureScript.event(entry, 1, :timer_in_combat, [cast_self(spell_id, @aura_not_present)],
      param1: 100,
      param2: 200,
      param3: repeat_min,
      param4: repeat_max
    )
  end

  defp melee_range(entry, index, spell_id, repeat_min, repeat_max) do
    CreatureScript.event(entry, index, :range, [cast_victim(spell_id)],
      param1: 0,
      param2: 5,
      param3: repeat_min,
      param4: repeat_max
    )
  end

  defp cast_self(spell_id, flags \\ 0),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: flags, target_self?: true}

  defp cast_victim(spell_id), do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_type: :victim}
end
