defmodule ThistleTea.Game.Core.Creature.CreatureLink do
  @moduledoc """
  vmangos creature linking: a slave spawn tied to a master spawn by
  `creature_linking` flags. A master's aggro, evade, respawn, and despawn
  pass to its slaves, a slave's aggro and evade can reach back to its
  master, and a slave may refuse to spawn while its master lives or lies
  dead. vmangos never raises its on-death event, so the death flags stay
  inert here too, and no linked spawn in the data follows its master.
  """

  import Bitwise

  @enforce_keys [:slave, :master]
  defstruct [:slave, :master, flags: 0]

  @aggro_on_aggro 0x0001
  @to_aggro_on_aggro 0x0002
  @respawn_on_evade 0x0004
  @to_respawn_on_evade 0x0008
  @respawn_on_respawn 0x0080
  @despawn_on_respawn 0x0100
  @cant_spawn_if_boss_dead 0x0400
  @cant_spawn_if_boss_alive 0x0800
  @despawn_on_evade 0x1000
  @despawn_on_despawn 0x2000
  @evade_on_evade 0x4000

  def slave_command(%__MODULE__{} = link, {:attack, target, _leash}, slave),
    do: slave_command(link, {:attack, target}, slave)

  def slave_command(%__MODULE__{} = link, {:attack, target}, %{alive?: true, combat?: false}) do
    if flag?(link, @aggro_on_aggro), do: {:attack, target}
  end

  def slave_command(%__MODULE__{} = link, :evade, %{alive?: alive?, combat?: combat?}) do
    cond do
      alive? and flag?(link, @despawn_on_evade) -> :despawn
      alive? and combat? and flag?(link, @evade_on_evade) -> :evade
      not alive? and flag?(link, @respawn_on_evade) -> :respawn
      true -> nil
    end
  end

  def slave_command(%__MODULE__{} = link, :respawn, %{alive?: alive?}) do
    cond do
      not alive? and flag?(link, @respawn_on_respawn) -> :respawn
      alive? and flag?(link, @despawn_on_respawn) -> :despawn
      true -> nil
    end
  end

  def slave_command(%__MODULE__{} = link, :despawn, %{alive?: true}) do
    if flag?(link, @despawn_on_despawn), do: :despawn
  end

  def slave_command(%__MODULE__{}, _event, _slave), do: nil

  def master_command(%__MODULE__{} = link, {:attack, target, _leash}, master),
    do: master_command(link, {:attack, target}, master)

  def master_command(%__MODULE__{} = link, {:attack, target}, %{alive?: true, combat?: false}) do
    if flag?(link, @to_aggro_on_aggro), do: {:attack, target}
  end

  def master_command(%__MODULE__{} = link, :evade, %{alive?: false}) do
    if flag?(link, @to_respawn_on_evade), do: :respawn
  end

  def master_command(%__MODULE__{}, _event, _master), do: nil

  def gated?(%__MODULE__{} = link), do: flag?(link, @cant_spawn_if_boss_dead) or flag?(link, @cant_spawn_if_boss_alive)

  def spawn_allowed?(%__MODULE__{} = link, %{present?: true, alive?: alive?}) do
    cond do
      flag?(link, @cant_spawn_if_boss_dead) -> alive?
      flag?(link, @cant_spawn_if_boss_alive) -> not alive?
      true -> true
    end
  end

  def spawn_allowed?(%__MODULE__{}, _absent_master), do: true

  defp flag?(%__MODULE__{flags: flags}, flag), do: (flags &&& flag) != 0
end
