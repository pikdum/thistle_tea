defmodule ThistleTea.Game.World.Entity.GameObject.CheerSpeaker do
  @moduledoc """
  Runs a cheer speaker's fireworks show (`Core.GameEvent.FireworksLaunch`)
  for as long as the fireworks event keeps it spawned: a cheer when it
  appears and when it leaves, and between them a firework sent up over its
  city every one to two seconds.
  """

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.GameEvent.FireworksLaunch

  @launch :launch_firework
  @firework_lifetime_ms 500

  def start(%GameObject{object: %{entry: entry}} = state) do
    if FireworksLaunch.speaker?(entry) do
      schedule_launch()
      cheer(state)
    else
      state
    end
  end

  def stop(%GameObject{object: %{entry: entry}} = state) do
    if FireworksLaunch.speaker?(entry), do: cheer(state), else: state
  end

  def launch(%GameObject{internal: %{world: world}} = state) do
    schedule_launch()

    case FireworksLaunch.sites(world.map_id, state.movement_block.position) do
      [] ->
        state

      sites ->
        firework = Enum.random(FireworksLaunch.fireworks())

        effect =
          Effects.summon_game_object(firework, @firework_lifetime_ms, position: Enum.random(sites), owned?: false)

        Effects.enqueue(state, effect)
    end
  end

  defp cheer(state), do: Effects.enqueue(state, Effects.play_object_sound(Enum.random(FireworksLaunch.cheers())))

  defp schedule_launch, do: Process.send_after(self(), @launch, Enum.random(FireworksLaunch.interval_ms()))
end
