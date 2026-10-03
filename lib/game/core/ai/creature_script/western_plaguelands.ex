defmodule ThistleTea.Game.Core.AI.CreatureScript.WesternPlaguelands do
  @moduledoc """
  The vmangos Western Plaguelands triggers: the Scourge Cauldrons and the
  Andorhal watchtowers.

  Each cauldron calls up its Cauldron Lord once a player on that field's
  Target quest comes within sight, then goes quiet for ten minutes so one
  arrival cannot raise a second lord. A watchtower credits a player on All
  Along the Watchtowers who sees it while a Beacon Torch burns at its foot.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @cauldron 11_152
  @towers [10_902, 10_903, 10_904, 10_905]
  @beacon_torch 176_093

  @cauldrons [
    {45_420, 11_075, [5_216, 5_229]},
    {45_421, 11_077, [5_219, 5_231]},
    {45_419, 11_078, [5_225, 5_235]},
    {45_422, 11_076, [5_222, 5_233]}
  ]
  @watchtower_quests [5_097, 5_098]

  @sight_yards 40
  @torch_yards 20
  @incomplete 1
  @lord_lifetime_ms 600_000
  @timed_or_dead_despawn 1
  @quiet_seconds 600
  @credit_repeat_ms 1_000

  @impl CreatureScript
  def entries, do: [@cauldron | @towers]

  @impl CreatureScript
  def events(@cauldron) do
    @cauldrons
    |> Enum.with_index(1)
    |> Enum.map(fn {{db_guid, lord, quests}, index} ->
      CreatureScript.event(@cauldron, index, :ooc_los, [summon(lord), quiet()],
        param2: @sight_yards,
        condition: %Condition{type: :and, children: [%Condition{type: :db_guid, value1: db_guid}, on_any(quests)]}
      )
    end)
  end

  def events(tower) when tower in @towers do
    [
      CreatureScript.event(tower, 1, :ooc_los, [%ScriptStep{command: :kill_credit, datalong: tower}],
        param2: @sight_yards,
        param3: @credit_repeat_ms,
        param4: @credit_repeat_ms,
        condition: %Condition{type: :and, children: [torch_burning(), on_any(@watchtower_quests)]}
      )
    ]
  end

  defp summon(lord) do
    %ScriptStep{
      command: :summon_creature,
      datalong: lord,
      datalong2: @lord_lifetime_ms,
      dataint4: @timed_or_dead_despawn,
      position: {0.0, 0.0, 0.0, 0.0}
    }
  end

  defp quiet, do: %ScriptStep{command: :despawn, datalong: 0, datalong2: @quiet_seconds}

  defp torch_burning,
    do: %Condition{type: :nearby_game_object, value1: @beacon_torch, value2: @torch_yards, swap_targets?: true}

  defp on_any(quests) do
    %Condition{
      type: :or,
      children: Enum.map(quests, &%Condition{type: :quest_taken, value1: &1, value2: @incomplete})
    }
  end
end
