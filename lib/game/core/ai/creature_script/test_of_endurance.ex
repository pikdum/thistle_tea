defmodule ThistleTea.Game.Core.AI.CreatureScript.TestOfEndurance do
  @moduledoc """
  vmangos `event_test_of_endurance` and `npc_grenka_bloodscreech`, Test of
  Endurance (1150) in Thousand Needles.

  Laying out the Harpy Foodstuffs calls Grenka Bloodscreech, who waits
  unseen while her flock answers: a Screeching Harpy after five seconds, two
  more fifteen seconds later, and a last one fifteen seconds after that, when
  Grenka shows herself and joins the fight. Every harpy goes for the player
  who set out the food. Grenka flees once when she is nearly dead, and no
  second Grenka comes while the first is near.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript
  @behaviour ThistleTea.Game.Core.AI.EventScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.EventScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @event 747
  @grenka 4_490
  @harpy 4_100

  @perch {-5_587.69, -1_571.45, 11.21, 6.14}
  @ledge {-5_589.63, -1_575.89, 11.75, 6.02}
  @flock [{5_000, [@perch]}, {20_000, [@perch, @ledge]}, {35_000, [@perch]}]
  @reveal_ms 35_000

  @flock_script 1
  @lifetime_ms 60_000
  @timed_or_dead_despawn 1
  @no_attack -1
  @attack_provided 0
  @grenka_reach 100
  @flee_pct 15
  @unit_flags 46
  @immune_to_players_and_npcs 0x300
  @add_flags 1
  @remove_flags 2

  @impl CreatureScript
  def entries, do: [@grenka]

  @impl CreatureScript
  def events(@grenka = entry) do
    [
      CreatureScript.event(entry, 1, :spawned, [immune(@add_flags)]),
      CreatureScript.event(entry, 2, :hp, [%ScriptStep{command: :flee}],
        param1: @flee_pct,
        param2: 0,
        repeatable?: false
      )
    ]
  end

  @impl EventScript
  def event_ids, do: [@event]

  @impl EventScript
  def event_steps(@event) do
    [
      %ScriptStep{
        command: :summon_creature,
        datalong: @grenka,
        datalong2: @lifetime_ms,
        dataint2: @flock_script,
        dataint3: @no_attack,
        dataint4: @timed_or_dead_despawn,
        position: @ledge,
        concealed?: true,
        target_self?: true,
        condition: %Condition{type: :nearby_creature, value1: @grenka, value2: @grenka_reach, reverse?: true},
        sub_scripts: %{@flock_script => [CreatureScript.timed(flock() ++ reveal())]}
      }
    ]
  end

  defp flock do
    for {delay_ms, positions} <- @flock, position <- positions do
      %ScriptStep{
        command: :summon_creature,
        datalong: @harpy,
        datalong2: @lifetime_ms,
        dataint3: @attack_provided,
        dataint4: @timed_or_dead_despawn,
        position: position,
        delay_ms: delay_ms
      }
    end
  end

  defp reveal do
    Enum.map(
      [%ScriptStep{command: :set_concealed, datalong: 0}, immune(@remove_flags), %ScriptStep{command: :attack_start}],
      &%{&1 | delay_ms: @reveal_ms}
    )
  end

  defp immune(mode),
    do: %ScriptStep{
      command: :modify_flags,
      datalong: @unit_flags,
      datalong2: @immune_to_players_and_npcs,
      datalong3: mode
    }
end
