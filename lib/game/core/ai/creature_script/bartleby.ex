defmodule ThistleTea.Game.Core.AI.CreatureScript.Bartleby do
  @moduledoc """
  vmangos `npc_bartleby`, the Stormwind dockhand behind the warrior quest
  "Beat Bartleby" (1640).

  Accepting the quest turns him hostile and onto the player. Nobody can beat
  him below fifteen percent of his health: there he yields, credits the player
  he is fighting, and drops the fight as a friend again.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @bartleby 6090
  @beat_bartleby 1640
  @enemy 168
  @template_faction 0
  @yield_pct 15
  @percent 1

  @impl CreatureScript
  def entries, do: [@bartleby]

  @impl CreatureScript
  def events(entry) do
    [
      CreatureScript.event(entry, 1, :spawned, [
        %ScriptStep{command: :invincibility, datalong: @yield_pct, datalong2: @percent}
      ]),
      CreatureScript.event(entry, 2, :hp, yield(), param1: @yield_pct, param2: 0, repeatable?: false),
      CreatureScript.event(entry, 3, :leave_combat, [befriend()])
    ]
  end

  @impl CreatureScript
  def quest_start_steps do
    %{@beat_bartleby => [%ScriptStep{command: :set_faction, datalong: @enemy}, %ScriptStep{command: :attack_start}]}
  end

  defp yield do
    [%ScriptStep{command: :quest_explored, datalong: @beat_bartleby}, befriend(), %ScriptStep{command: :enter_evade}]
  end

  defp befriend, do: %ScriptStep{command: :set_faction, datalong: @template_faction}
end
