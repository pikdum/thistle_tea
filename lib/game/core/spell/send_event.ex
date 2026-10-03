defmodule ThistleTea.Game.Core.Spell.SendEvent do
  @moduledoc """
  Spell effects that start a VMangos `event_scripts` entry.

  An event effect without implicit targets runs once per cast, from the
  caster, aimed at the spell focus, the targeted object, or the selected unit
  in that order (VMangos `EffectSendEvent` in the immediate phase). A targeted
  event effect runs per recipient instead, through the spell-effect script
  dispatcher.
  """

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect

  def cast_events(%Spell{effects: effects}, owner_guid, caster_guid, target_guid)
      when is_integer(caster_guid) and is_integer(target_guid) do
    for %Effect{type: :send_event, implicit_target_a: nil, implicit_target_b: nil, event_steps: [_ | _] = steps} <-
          effects do
      if owner_guid == caster_guid,
        do: Effects.script_steps(steps, target_guid, 0),
        else: Effects.forward_script_steps(caster_guid, steps, target_guid)
    end
  end

  def cast_events(_spell, _owner_guid, _caster_guid, _target_guid), do: []

  def cast_level?(%Spell{effects: effects}),
    do: Enum.any?(effects, &match?(%Effect{type: :send_event, implicit_target_a: nil, implicit_target_b: nil}, &1))

  def target(focus_guid, object_guids, selected_guid, caster_guid) do
    Enum.find([focus_guid, List.first(object_guids || []), selected_guid], caster_guid, &(is_integer(&1) and &1 > 0))
  end
end
