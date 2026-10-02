defmodule ThistleTea.Game.Core.AI.CreatureScript.ChickenCluck do
  @moduledoc """
  vmangos `npc_chicken_cluck`, the chickens behind "CLUCK!" (3861).

  A chicken is no quest giver until a player who never took the quest
  `/chicken`s at it and wins an even chance of about one in thirty: then it
  turns friendly, offers the quest, and looks up quizzically. A player
  carrying the quest's feed `/cheer`s at any chicken to make it take the
  quest back, and it looks on expectantly. Either way the chicken goes back
  to being prey twenty seconds later, or as soon as it respawns or a fight
  ends.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @chicken 620
  @cluck 3_861
  @text_emote_cheer 21
  @text_emote_chicken 22
  @hello_chance 3
  @looks_up 4_714
  @looks_expectant 5_170
  @reset_ms 20_000
  @npc_flags 147
  @questgiver 0x2
  @set_flags 1
  @remove_flags 2
  @friendly 35
  @template_faction 0
  @quest_complete 2

  @impl CreatureScript
  def entries, do: [@chicken]

  @impl CreatureScript
  def events(entry) do
    [
      CreatureScript.event(entry, 1, :spawned, reset()),
      CreatureScript.event(entry, 2, :receive_emote, offer(@looks_up),
        param1: @text_emote_chicken,
        chance: @hello_chance,
        condition: %Condition{type: :quest_none, value1: @cluck}
      ),
      CreatureScript.event(entry, 3, :receive_emote, offer(@looks_expectant),
        param1: @text_emote_cheer,
        condition: %Condition{type: :quest_taken, value1: @cluck, value2: @quest_complete}
      ),
      CreatureScript.event(entry, 4, :leave_combat, reset())
    ]
  end

  defp offer(text_id) do
    [
      questgiver(@set_flags),
      %ScriptStep{command: :set_faction, datalong: @friendly},
      %ScriptStep{command: :talk, dataint: text_id},
      CreatureScript.timed(Enum.map(reset(), &%{&1 | delay_ms: @reset_ms}))
    ]
  end

  defp reset, do: [questgiver(@remove_flags), %ScriptStep{command: :set_faction, datalong: @template_faction}]

  defp questgiver(mode) do
    %ScriptStep{command: :modify_flags, datalong: @npc_flags, datalong2: @questgiver, datalong3: mode}
  end
end
