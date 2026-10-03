defmodule ThistleTea.Game.Core.AI.CreatureScript.ScourgeInvasion do
  @moduledoc """
  vmangos `scourge_invasion` creature AIs. The Mouth of Kel'Thuzad
  (`MouthAI`) taunts its zone every two and a half minutes to an hour. Over
  an invaded zone it answers `World.System.ScourgeInvasion`: script event 7
  proclaims the attack, and script event 8 concedes the zone and departs.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @mouth 16_995

  @zone_start 7
  @zone_stop 8
  @zone_yell 6

  @attack_starts [13_121, 13_125]
  @attack_ends [13_165, 13_164, 13_163]
  @taunts [13_126, 13_124, 13_122, 13_123]
  @fewest_taunt_ms 150_000
  @most_taunt_ms 3_600_000

  @impl CreatureScript
  def entries, do: [@mouth]

  @impl CreatureScript
  def events(@mouth) do
    [
      CreatureScript.event(@mouth, 1, :timer_ooc, [zone_yell(@taunts)],
        param1: @fewest_taunt_ms,
        param2: @most_taunt_ms,
        param3: @fewest_taunt_ms,
        param4: @most_taunt_ms
      ),
      CreatureScript.event(@mouth, 2, :script_event, [zone_yell(@attack_starts)], param1: @zone_start, param2: 0),
      CreatureScript.event(@mouth, 3, :script_event, [zone_yell(@attack_ends), %ScriptStep{command: :despawn}],
        param1: @zone_stop,
        param2: 0
      )
    ]
  end

  def events(_entry), do: []

  defp zone_yell(texts) do
    [dataint, dataint2, dataint3, dataint4] = Enum.take(texts ++ [0, 0, 0], 4)

    %ScriptStep{
      command: :talk,
      datalong: @zone_yell,
      dataint: dataint,
      dataint2: dataint2,
      dataint3: dataint3,
      dataint4: dataint4
    }
  end
end
