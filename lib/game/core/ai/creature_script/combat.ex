defmodule ThistleTea.Game.Core.AI.CreatureScript.Combat do
  @moduledoc """
  Building blocks for porting vmangos boss AIs, most of which are a handful
  of in-combat spell timers.

  A vmangos boss counts each ability down from its `Reset()` value and starts
  it over from its repeat value once it fires, but only while it has a
  victim. `every/6` is that timer as a repeatable in-combat event, and
  `every_out_of_combat/6` the idle chatter and buffs some bosses keep up
  between fights. `below_health/5` fires once under a health threshold, or
  keeps repeating there, as the `GetHealthPercent() < X` blocks do. Each
  timing is milliseconds or a `{min, max}` range rolled every time, as `urand`
  timers are.
  """

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  def every(entry, index, steps, first, repeat, opts \\ []),
    do: timer(entry, index, :timer_in_combat, steps, first, repeat, opts)

  def every_out_of_combat(entry, index, steps, first, repeat, opts \\ []),
    do: timer(entry, index, :timer_ooc, steps, first, repeat, opts)

  def below_health(entry, index, steps, percent, repeat \\ nil) do
    case repeat do
      nil ->
        CreatureScript.event(entry, index, :hp, List.wrap(steps), param1: percent, repeatable?: false)

      repeat ->
        {repeat_min, repeat_max} = range(repeat)

        CreatureScript.event(entry, index, :hp, List.wrap(steps),
          param1: percent,
          param3: repeat_min,
          param4: repeat_max
        )
    end
  end

  def cast(spell_id, target \\ :victim, flags \\ 0)

  def cast(spell_id, :self, flags),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: flags, target_self?: true}

  def cast(spell_id, target, flags) when is_atom(target),
    do: %ScriptStep{command: :cast_spell, datalong: spell_id, datalong2: flags, target_type: target}

  def talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}

  def text_emote(text) when is_binary(text),
    do: %ScriptStep{command: :talk, texts: [%{text: text, chat_type: :text_emote, language: 0, emote_id: 0}]}

  defp timer(entry, index, event_type, steps, first, repeat, opts) do
    {first_min, first_max} = range(first)
    {repeat_min, repeat_max} = range(repeat)

    CreatureScript.event(
      entry,
      index,
      event_type,
      List.wrap(steps),
      [param1: first_min, param2: first_max, param3: repeat_min, param4: repeat_max] ++ opts
    )
  end

  defp range({min_ms, max_ms}), do: {min_ms, max_ms}
  defp range(ms) when is_integer(ms), do: {ms, ms}
end
