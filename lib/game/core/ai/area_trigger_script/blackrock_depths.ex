defmodule ThistleTea.Game.Core.AI.AreaTriggerScript.BlackrockDepths do
  @moduledoc """
  vmangos `at_ring_of_law`, the Blackrock Depths trigger at the center of the
  Ring of Law. Stepping into the ring asks `InstanceScript.BlackrockDepths` to
  begin the fight, or to resume one a wiped party left with its champion still
  waiting; the instance ignores the step once the ring is already fighting or
  won.
  """

  @behaviour ThistleTea.Game.Core.AI.AreaTriggerScript

  alias ThistleTea.Game.Core.AI.AreaTriggerScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @ring_of_law_trigger 1_526
  @ring_of_law 0
  @in_progress 1

  @impl AreaTriggerScript
  def triggers, do: [@ring_of_law_trigger]

  @impl AreaTriggerScript
  def steps(@ring_of_law_trigger, _position),
    do: [%ScriptStep{command: :set_instance_data, datalong: @ring_of_law, datalong2: @in_progress}]
end
