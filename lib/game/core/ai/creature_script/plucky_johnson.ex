defmodule ThistleTea.Game.Core.AI.CreatureScript.PluckyJohnson do
  @moduledoc """
  vmangos `npc_plucky_johnson`, Magus Tirth's apprentice, who wanders the
  Mirage Raceway as a chicken and knows the phrase to Tirth's strongbox for
  "Get the Scoop" (1950).

  A player on the quest who `/beckon`s at him, or anyone who `/chicken`s at
  him, turns him back into his own form: he becomes friendly and talks, and
  waves when it was the chicken emote. Asking him for the phrase completes
  the quest. Two minutes later he goes back to being a chicken.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.Gossip
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @plucky 6_626
  @get_the_scoop 1_950
  @incomplete 1
  @text_emote_beckon 7
  @text_emote_chicken 22
  @wave 3
  @human_form 9_192
  @chicken_form 9_220
  @friendly 35
  @template_faction 0
  @human_ms 120_000
  @npc_flags 147
  @gossip 0x1
  @set_flags 1
  @remove_flags 2
  @triggered 0x02
  @hello_text 720
  @phrase_text 738
  @ask_phrase "Please tell me the Phrase.."

  @impl CreatureScript
  def entries, do: [@plucky]

  @impl CreatureScript
  def events(@plucky) do
    [
      CreatureScript.event(@plucky, 1, :receive_emote, human_form(),
        param1: @text_emote_beckon,
        inverse_phase_mask: CreatureScript.only_in_phases([0]),
        condition: on_the_quest()
      ),
      CreatureScript.event(@plucky, 2, :receive_emote, human_form() ++ [%ScriptStep{command: :emote, datalong: @wave}],
        param1: @text_emote_chicken,
        inverse_phase_mask: CreatureScript.only_in_phases([0])
      )
    ]
  end

  @impl CreatureScript
  def gossip do
    %{
      @plucky => %Gossip{
        texts: [%Gossip.Text{text_id: @hello_text}],
        options: [
          %Gossip.Option{
            text: @ask_phrase,
            condition: on_the_quest(),
            reply_text_id: @phrase_text,
            steps: [%ScriptStep{command: :quest_explored, datalong: @get_the_scoop}]
          }
        ]
      }
    }
  end

  defp human_form do
    [
      %ScriptStep{command: :set_phase, datalong: 1},
      CreatureScript.faction(@friendly),
      gossip(@set_flags),
      cast(@human_form),
      CreatureScript.timed(Enum.map(chicken_form(), &%{&1 | delay_ms: @human_ms}))
    ]
  end

  defp chicken_form do
    [
      gossip(@remove_flags),
      %ScriptStep{command: :set_faction, datalong: @template_faction},
      cast(@chicken_form),
      %ScriptStep{command: :set_phase, datalong: 0}
    ]
  end

  defp cast(spell_id),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: @triggered, target_self?: true}

  defp gossip(mode), do: %ScriptStep{command: :modify_flags, datalong: @npc_flags, datalong2: @gossip, datalong3: mode}

  defp on_the_quest, do: %Condition{type: :quest_taken, value1: @get_the_scoop, value2: @incomplete}
end
