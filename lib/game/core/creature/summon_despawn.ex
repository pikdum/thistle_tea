defmodule ThistleTea.Game.Core.Creature.SummonDespawn do
  @moduledoc """
  vmangos `TempSummonType` rules for when a typed temporary summon leaves the
  world.

  A summon's despawn timer starts when it appears, unless its type only
  counts after death. Timed-or-dead, timed-or-corpse, and out-of-combat
  summons wait out any fight before their timer may end them. At death,
  timed-or-corpse, corpse, and timed-combat-or-corpse summons vanish with no
  body left behind, while out-of-combat and corpse-timed summons start their
  timer over from the death. Every other type keeps its corpse for looting
  until the timer ends a type that keeps running after death, or the corpse
  decays.

  vmangos holds an in-combat timer at its full length and lets it run once
  the fight ends, so such a summon starts its timer over whenever it leaves
  a fight. A timer that comes due mid-fight looks again a little later, in
  case the fight ends some way that does not start it over.
  """

  @timed_or_dead 1
  @timed_or_corpse 2
  @timed 3
  @timed_out_of_combat 4
  @corpse 5
  @corpse_timed 6
  @timed_combat_or_dead 9
  @timed_combat_or_corpse 10

  @timed_while_alive [@timed_or_dead, @timed_or_corpse, @timed, @timed_out_of_combat, @timed_combat_or_dead] ++
                       [@timed_combat_or_corpse]
  @timed_while_dead [@timed, @timed_out_of_combat, @corpse_timed, @timed_combat_or_dead, @timed_combat_or_corpse]
  @waits_out_combat [@timed_or_dead, @timed_or_corpse, @timed_out_of_combat]
  @gone_at_death [@timed_or_corpse, @corpse, @timed_combat_or_corpse]
  @timer_from_death [@timed_out_of_combat, @corpse_timed]

  def typed?(type), do: is_integer(type) and type > 0

  def timer_at_spawn?(type), do: type in @timed_while_alive

  def restart_after_combat?(type), do: type in @waits_out_combat

  def at_death(type) when type in @gone_at_death, do: :despawn
  def at_death(type) when type in @timer_from_death, do: :restart_timer
  def at_death(_type), do: :keep_corpse

  def when_due(type, true = _dead?, _in_combat?) do
    if type in @timed_while_dead, do: :despawn, else: :ignore
  end

  def when_due(type, false = _dead?, in_combat?) do
    cond do
      type not in @timed_while_alive -> :ignore
      in_combat? and type in @waits_out_combat -> :wait
      true -> :despawn
    end
  end
end
