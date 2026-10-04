defmodule ThistleTea.Game.Core.AI.CreatureScript.Terenthis do
  @moduledoc """
  vmangos `npc_terenthis` in Auberdine, which brings Sentinel Selarin to
  Terenthis when a player turns in Escape Through Force (994) or Escape
  Through Stealth (995).

  Selarin has no spawn of her own: she runs in from the dock for two minutes,
  long enough for the database's completion script to walk her up and have
  her speak, and to hand out Trek to Ashenvale (990). A second turn-in while
  she is still about calls no one else.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @escape_through_force 994
  @escape_through_stealth 995
  @sentinel_selarin 3_694
  @dock {6_409.01, 381.597, 13.7997, 1.0}
  @selarin_ms 120_000
  @timed_combat_or_dead 9
  @attack_none -1
  @arrival_script 1
  @reach 40

  @impl CreatureScript
  def entries, do: []

  @impl CreatureScript
  def events(_entry), do: []

  @impl CreatureScript
  def quest_end_steps, do: %{@escape_through_force => [summon_selarin()], @escape_through_stealth => [summon_selarin()]}

  defp summon_selarin do
    %ScriptStep{
      command: :summon_creature,
      datalong: @sentinel_selarin,
      datalong2: @selarin_ms,
      dataint2: @arrival_script,
      dataint3: @attack_none,
      dataint4: @timed_combat_or_dead,
      position: @dock,
      sub_scripts: %{@arrival_script => [%ScriptStep{command: :set_run, datalong: 1}]},
      condition: %Condition{type: :nearby_creature, value1: @sentinel_selarin, value2: @reach, reverse?: true}
    }
  end
end
