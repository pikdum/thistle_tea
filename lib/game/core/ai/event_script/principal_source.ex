defmodule ThistleTea.Game.Core.AI.EventScript.PrincipalSource do
  @moduledoc """
  vmangos `event_the_principle_source`, The Principal Source (6127) on
  Dreadmist Peak in the Barrens.

  Drawing a water sample from the poisoned well calls three Burning Blade
  Toxicologists down on the player who drew it. They leave after two minutes
  unless they are still fighting.
  """

  @behaviour ThistleTea.Game.Core.AI.EventScript

  alias ThistleTea.Game.Core.AI.EventScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @event 5_246
  @toxicologist 12_319
  @positions [
    {331.52, -2_270.94, 242.21, 5.15},
    {332.09, -2_291.26, 241.86, 1.05},
    {345.97, -2_282.66, 241.77, 3.16}
  ]
  @lifetime_ms 120_000
  @attack_summoner 8
  @timed_or_dead_despawn 1

  @impl EventScript
  def event_ids, do: [@event]

  @impl EventScript
  def event_steps(@event) do
    Enum.map(
      @positions,
      &%ScriptStep{
        command: :summon_creature,
        datalong: @toxicologist,
        datalong2: @lifetime_ms,
        dataint3: @attack_summoner,
        dataint4: @timed_or_dead_despawn,
        position: &1
      }
    )
  end
end
