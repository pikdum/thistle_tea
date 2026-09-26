defmodule ThistleTea.Game.Entity.Logic.KillFeedback do
  @moduledoc """
  Captures fatal blows before victim cleanup and applies kill procs to the
  entity that dealt them, independently of taps, groups, and reward delivery.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CreatureFlags
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.KillCredit

  defmodule Victim do
    @moduledoc false
    @enforce_keys [:guid, :level, :reward_target?]
    defstruct [:guid, :level, :reward_target?]
  end

  def capture(entity, old_health, new_health, source)

  def capture(%{object: %{guid: guid}, unit: %{level: level}} = entity, old_health, 0, source)
      when old_health > 0 and is_integer(source) and source > 0 and source != guid do
    victim = %Victim{guid: guid, level: level, reward_target?: reward_target?(entity)}
    Effects.enqueue(entity, %Effects.KillOutcome{target_guid: source, victim: victim})
  end

  def capture(entity, _old_health, _new_health, _source), do: entity

  def receive(entity, %Victim{} = victim, now) when is_integer(now) do
    if Death.alive?(entity) and eligible?(entity, victim) do
      {entity, events} = Aura.reactions(entity, :kill, %{victim_guid: victim.guid, now: now})
      Effects.enqueue(entity, events)
    else
      entity
    end
  end

  def eligible?(%Character{unit: %{level: level}}, %Victim{level: victim_level, reward_target?: true})
      when is_integer(level) and is_integer(victim_level), do: victim_level > Experience.gray_level(level)

  def eligible?(%Character{}, %Victim{}), do: false
  def eligible?(%Mob{}, %Victim{}), do: true
  def eligible?(_entity, _victim), do: false

  defp reward_target?(%Character{}), do: true

  defp reward_target?(%Mob{internal: %{creature: %Creature{} = creature, totem: totem}} = mob) do
    is_nil(totem) and not KillCredit.pet?(mob) and creature.experience_multiplier != 0 and
      not CreatureFlags.has?(mob, :no_xp)
  end

  defp reward_target?(_entity), do: false
end
