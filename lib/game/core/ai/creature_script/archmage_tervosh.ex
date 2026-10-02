defmodule ThistleTea.Game.Core.AI.CreatureScript.ArchmageTervosh do
  @moduledoc """
  vmangos `npc_archmage_tervosh`'s quest reward: when a player turns in the
  fourteenth part of The Missing Diplomat (1265), Tervosh sends them off with
  a blessing and Proudmoore's Defense. His arrival at Sentry Point is the
  area trigger script `AreaTriggerScript.SentryPoint`.

  Tervosh keeps his database EventAI, so this script claims no creature
  entry and only adds to the quest's completion script.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @missing_diplomat 1265
  @go_with_grace 1751
  @proudmoores_defense 7120
  @triggered 0x02

  @impl CreatureScript
  def entries, do: []

  @impl CreatureScript
  def events(_entry), do: []

  @impl CreatureScript
  def quest_end_steps do
    %{
      @missing_diplomat => [
        %ScriptStep{command: :talk, dataint: @go_with_grace},
        %ScriptStep{command: :cast_spell, datalong: @proudmoores_defense, datalong2: @triggered}
      ]
    }
  end
end
