defmodule ThistleTea.Game.Core.AI.CreatureScript.CombatGadgets do
  @moduledoc """
  vmangos `ScriptedPetAI` guardians from `npcs_special`: the engineering
  Gnomish Battle Chicken and Arcanite Dragonling, the Emerald Dragon Whelps
  called by the sword Dragon's Call, the Spiked Collar's Guardian
  Felhunter, and the Felhound Minion.

  Each fights its owner's enemies and uses its abilities on timers. The
  Battle Chicken squawks once, half a minute to a minute and a half into a
  fight, and flies into Chicken Fury as the fight starts and every 25 seconds
  after; vmangos instead triggers the fury when the chicken first takes
  damage. The felhounds' Mana Burn simply fails on a target without mana,
  where vmangos skips the cast.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @battle_chicken 8_836
  @arcanite_dragonling 12_473
  @emerald_dragon_whelp 8_776
  @felhound_minions [9_556, 10_656]

  @battle_squawk 23_060
  @chicken_fury 13_168
  @flame_buffet 9_658
  @flame_breath 8_873
  @acid_spit 9_591
  @mana_burn 15_980
  @triggered 0x02

  @impl CreatureScript
  def entries, do: [@battle_chicken, @arcanite_dragonling, @emerald_dragon_whelp | @felhound_minions]

  @impl CreatureScript
  def events(@battle_chicken = entry) do
    [
      CreatureScript.event(entry, 1, :timer_in_combat, [cast_self(@battle_squawk)],
        param1: 30_000,
        param2: 80_000,
        repeatable?: false
      ),
      CreatureScript.event(entry, 2, :aggro, [cast_self(@chicken_fury)]),
      CreatureScript.event(entry, 3, :timer_in_combat, [cast_self(@chicken_fury)],
        param1: 25_000,
        param2: 25_000,
        param3: 25_000,
        param4: 25_000
      )
    ]
  end

  def events(@arcanite_dragonling = entry) do
    [
      CreatureScript.event(entry, 1, :timer_in_combat, [cast_victim(@flame_buffet)],
        param1: 5_000,
        param2: 5_000,
        param3: 22_500,
        param4: 22_500
      ),
      CreatureScript.event(entry, 2, :timer_in_combat, [cast_victim(@flame_breath)],
        param1: 10_000,
        param2: 60_000,
        param3: 10_000,
        param4: 60_000
      )
    ]
  end

  def events(@emerald_dragon_whelp = entry) do
    [
      CreatureScript.event(entry, 1, :timer_in_combat, [cast_victim(@acid_spit)],
        param1: 1_000,
        param2: 1_000,
        param3: 2_000,
        param4: 2_000
      )
    ]
  end

  def events(entry) when entry in @felhound_minions do
    [
      CreatureScript.event(entry, 1, :timer_in_combat, [cast_victim(@mana_burn)],
        param1: 1_000,
        param2: 2_500,
        param3: 9_800,
        param4: 15_200
      )
    ]
  end

  defp cast_self(spell_id),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: @triggered, target_self?: true}

  defp cast_victim(spell_id), do: %ScriptStep{command: :cast_spell, datalong: spell_id, target_type: :victim}
end
