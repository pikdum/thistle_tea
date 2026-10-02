defmodule ThistleTea.Game.Core.AI.CreatureScript.TwilightCorrupter do
  @moduledoc """
  vmangos `npc_twilight_corrupter`, the Twilight Grove boss of The
  Nightmare's Corruption (8735) that `AreaTriggerScript.TwilightGrove`
  draws out. It shouts on the pull, wracks everyone near it with Soul
  Corruption, and turns a random player on their friends with Creature of
  Nightmare. Each player it kills feeds it, and it swells with their soul.

  vmangos also restores the charmed player's threat once Creature of
  Nightmare ends; here the player earns threat back by fighting again.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @corrupter 15_625
  @nightmare_cannot_be_stopped 11_269
  @swallows_their_soul 11_270
  @soul_corruption 25_805
  @creature_of_nightmare 25_806
  @swell_of_souls 21_307
  @players_only 0x02
  @triggered 0x02
  @player_kill 1

  @impl CreatureScript
  def entries, do: [@corrupter]

  @impl CreatureScript
  def events(entry) do
    [
      CreatureScript.event(entry, 1, :aggro, [talk(@nightmare_cannot_be_stopped)]),
      CreatureScript.event(entry, 2, :timer_in_combat, [soul_corruption()],
        param1: 6_000,
        param2: 18_000,
        param3: 20_000,
        param4: 30_000
      ),
      CreatureScript.event(entry, 3, :timer_in_combat, [creature_of_nightmare()],
        param1: 10_000,
        param2: 20_000,
        param3: 35_000,
        param4: 40_000
      ),
      CreatureScript.event(entry, 4, :kill, [talk(@swallows_their_soul), swell_of_souls()], param3: @player_kill)
    ]
  end

  defp soul_corruption, do: %ScriptStep{command: :cast_spell, datalong: @soul_corruption, target_self?: true}

  defp creature_of_nightmare do
    %ScriptStep{
      command: :cast_spell,
      datalong: @creature_of_nightmare,
      target_type: :hostile_random,
      target_param1: @players_only
    }
  end

  defp swell_of_souls do
    %ScriptStep{command: :cast_spell, datalong: @swell_of_souls, datalong2: @triggered, target_self?: true}
  end

  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}
end
