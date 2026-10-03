defmodule ThistleTea.Game.Core.AI.CreatureScript.Omen do
  @moduledoc """
  vmangos `boss_omen`, the ancient that Lunar Festival fireworks call out of
  Elune's lake in Moonglade (`Core.GameEvent.MinionsOfOmen`). He surfaces
  with a splash and a roar and runs ashore, sears himself whenever Elune's
  Candle strikes him, and in death leaves Omen's Moonlight shining over
  Elune's Blessing.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @omen 15_467
  @elunes_candle 26_374
  @self_damage 26_544
  @omens_moonlight 26_392
  @splash 1_097
  @roar 8_460
  @surfaces_ms 800
  @ashore_ms 4_000
  @shore {7_553.95, -2_848.48, 454.56, 0.0}
  @distance_dependent 0x2
  @triggered 0x02
  @pathfind_run 0x5

  @impl CreatureScript
  def entries, do: [@omen]

  @impl CreatureScript
  def events(@omen) do
    [
      CreatureScript.event(@omen, 1, :spawned, [
        CreatureScript.timed([
          sound(@splash),
          sound(@roar),
          %ScriptStep{command: :move_to, delay_ms: @ashore_ms, datalong3: @pathfind_run, position: @shore}
        ])
      ]),
      CreatureScript.event(@omen, 2, :hit_by_spell, [cast_self(@self_damage, @triggered)], param1: @elunes_candle),
      CreatureScript.event(@omen, 3, :death, [cast_self(@omens_moonlight, 0)])
    ]
  end

  def events(_entry), do: []

  defp sound(sound_id),
    do: %ScriptStep{command: :play_sound, datalong: sound_id, datalong2: @distance_dependent, delay_ms: @surfaces_ms}

  defp cast_self(spell_id, flags),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: flags, target_self?: true}
end
