defmodule ThistleTea.Game.Core.AI.CreatureScript.RiggleBassbait do
  @moduledoc """
  vmangos `npc_riggle_bassbait`: the judge of the Stranglethorn Fishing
  Extravaganza.

  Riggle and his crew arrive at Booty Bay every Sunday at noon. When the
  tournament opens at two he yells the start across the zone and takes Master
  Angler (8193) turn-ins. The first angler to bring him forty Speckled
  Tastyfish wins the week: Riggle names them to the whole zone, stops taking
  the quest, and his gossip switches to the "we have a winner" text through
  the same server variable. When the tastyfish schools vanish at four he
  yells that the tournament is over and stays another hour for the
  apprentice and rare fish turn-ins.

  The week's state lives in vmangos's server variables, so the yells fire
  once and a respawned Riggle neither repeats them nor crowns a second
  winner. A Riggle who arrives before the tournament starts a fresh week;
  one who arrives after a restart mid-tournament starts one only if nothing
  has been announced yet. vmangos also clears the week a day after the last
  win, which the before-the-tournament reset covers here, since Riggle only
  spawns on Sundays.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @riggle 15_077
  @master_angler 8_193
  @tournament 15

  @announce_begin 30_022
  @announce_over 30_023
  @has_winner 30_056

  @tournament_begins 10_608
  @tournament_over 10_609
  @winner 10_610

  @npc_flags_field 147
  @questgiver 0x2
  @add_flags 1
  @remove_flags 2
  @equal 0
  @check_ms 1_000

  @impl CreatureScript
  def entries, do: [@riggle]

  @impl CreatureScript
  def events(@riggle = entry) do
    [
      CreatureScript.event(entry, 1, :spawned, new_week()),
      CreatureScript.event(entry, 2, :timer_ooc, judge(),
        param1: @check_ms,
        param2: @check_ms,
        param3: @check_ms,
        param4: @check_ms
      )
    ]
  end

  def events(_entry), do: []

  @impl CreatureScript
  def quest_end_steps do
    %{
      @master_angler => [
        set_variable(@has_winner, 1),
        questgiver(@remove_flags),
        talk(@winner)
      ]
    }
  end

  defp new_week do
    [
      when_met(
        CreatureScript.timed([
          set_variable(@has_winner, 0),
          set_variable(@announce_over, 0),
          set_variable(@announce_begin, 1)
        ]),
        negate(tournament())
      ),
      when_met(set_variable(@announce_begin, 1), all([tournament(), no_winner(), variable(@announce_over, 0)]))
    ]
  end

  defp judge do
    open = all([tournament(), no_winner()])

    [
      when_met(questgiver(@add_flags), all([open, negate(questgiver?())])),
      when_met(
        CreatureScript.timed([
          talk(@tournament_begins),
          set_variable(@announce_begin, 0),
          set_variable(@announce_over, 1)
        ]),
        all([open, variable(@announce_begin, 1)])
      ),
      when_met(questgiver(@remove_flags), all([negate(open), questgiver?()])),
      when_met(
        CreatureScript.timed([talk(@tournament_over), set_variable(@announce_over, 0)]),
        all([negate(tournament()), variable(@announce_over, 1)])
      )
    ]
  end

  defp tournament, do: %Condition{type: :active_game_event, value1: @tournament}
  defp no_winner, do: variable(@has_winner, 0)
  defp questgiver?, do: %Condition{type: :has_flag, value1: @npc_flags_field, value2: @questgiver}

  defp variable(index, value), do: %Condition{type: :saved_variable, value1: index, value2: value, value3: @equal}

  defp all(children), do: %Condition{type: :and, children: children}
  defp negate(%Condition{} = condition), do: %{condition | reverse?: not condition.reverse?}

  defp when_met(%ScriptStep{} = step, %Condition{} = condition), do: %{step | condition: condition}

  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}

  defp set_variable(index, value), do: %ScriptStep{command: :set_server_variable, datalong: index, datalong2: value}

  defp questgiver(mode),
    do: %ScriptStep{command: :modify_flags, datalong: @npc_flags_field, datalong2: @questgiver, datalong3: mode}
end
