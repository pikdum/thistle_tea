defmodule ThistleTea.Game.World.Entity.GameObject.OmenLauncher do
  @moduledoc """
  Runs one of Omen's cluster launchers at Elune's lake in Moonglade. Each
  firework sent up from it is reported to `World.System.MinionsOfOmen`, and
  when the watch calls Omen the launcher summons him, then reports his
  arrival, his death, and his leaving back to the watch.
  """

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.GameEvent.MinionsOfOmen
  alias ThistleTea.Game.Core.Pet.SummonEvent
  alias ThistleTea.Game.World.System.MinionsOfOmen, as: Watch

  def firework_launched(%GameObject{object: %{entry: entry}} = state) do
    if entry == MinionsOfOmen.launcher() and Watch.launched(),
      do: Effects.enqueue(state, Effects.summon_creature(MinionsOfOmen.summon(), [], nil)),
      else: state
  end

  def summon_event(%GameObject{object: %{entry: entry}} = state, %SummonEvent{} = event) do
    if entry == MinionsOfOmen.launcher() and event.entry == MinionsOfOmen.omen(), do: report(event)
    state
  end

  defp report(%SummonEvent{event: :summoned_unit, observation: %{guid: guid}}), do: Watch.omen_arrived(guid)
  defp report(%SummonEvent{event: :summoned_just_died}), do: Watch.omen_fell()
  defp report(%SummonEvent{event: :summoned_just_despawn}), do: Watch.omen_gone()
  defp report(%SummonEvent{}), do: :ok
end
