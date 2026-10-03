defmodule ThistleTea.Game.World.Entity.Mob.FireworkGuy do
  @moduledoc """
  Sends up the firework a rocket or rocket cluster called its firework guy
  for (`Core.Creature.FireworkGuy`) as the guy appears: the rockets burst
  around it, whoever fired it gets the firework credit, a lucky cluster
  grants Lunar Fortune a moment later, and an Omen cluster launcher beside
  it hears of the launch.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Creature.FireworkGuy
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.GameEvent.MinionsOfOmen
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity

  @triggered 0x02

  def launch(%Mob{object: %{entry: entry}, movement_block: %{position: {x, y, z, _o}}} = state) do
    case FireworkGuy.launch(entry, {x, y, z}) do
      nil ->
        state

      launch ->
        state
        |> send_up(launch.fireworks)
        |> credit(launch.credit)
        |> fortune(launch.lucky?)
        |> tell_launcher()
    end
  end

  def launch(%Mob{} = state), do: state

  defp send_up(state, fireworks) do
    Enum.reduce(fireworks, state, fn {entry, position}, state ->
      Effects.enqueue(
        state,
        Effects.summon_game_object(entry, FireworkGuy.lifetime_ms(), position: position, owned?: false)
      )
    end)
  end

  defp credit(%Mob{internal: %{spawn: %{summoner_guid: summoner}}} = state, credit) when is_integer(summoner) do
    if Guid.entity_type(summoner) == :player,
      do: Effects.enqueue(state, Effects.quest_kill_credit(summoner, credit)),
      else: state
  end

  defp credit(state, _credit), do: state

  defp fortune(state, false), do: state

  defp fortune(%Mob{object: %{guid: guid}} = state, true) do
    step = %ScriptStep{
      command: :cast_spell,
      datalong: FireworkGuy.lunar_fortune(),
      datalong2: @triggered,
      target_self?: true
    }

    Effects.enqueue(state, Effects.script_steps([step], guid, FireworkGuy.fortune_delay_ms()))
  end

  defp tell_launcher(%Mob{} = state) do
    launcher = MinionsOfOmen.launcher()

    nearest =
      state
      |> World.nearby_game_objects(FireworkGuy.launcher_reach())
      |> Enum.filter(fn {guid, _distance} -> Guid.entry(guid) == launcher end)
      |> Enum.min_by(&elem(&1, 1), fn -> nil end)

    with {guid, _distance} <- nearest, do: Entity.firework_launched(guid)
    state
  end
end
