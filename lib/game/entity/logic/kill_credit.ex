defmodule ThistleTea.Game.Entity.Logic.KillCredit do
  @moduledoc """
  Creature reward eligibility captured before lethal damage releases control.
  Pet identity survives charm and possession; player-controlled victims never
  grant experience, reputation, or quest kill credit.
  """

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.ControlOwner
  alias ThistleTea.Game.Guid

  def capture(%Mob{} = mob) do
    %{mob | internal: %{mob.internal | pve_reward_eligible?: eligible?(mob)}}
  end

  def eligible?(%Mob{internal: %{pve_reward_eligible?: eligible?}}) when is_boolean(eligible?), do: eligible?

  def eligible?(%Mob{} = mob) do
    case ControlOwner.guid(mob) do
      guid when is_integer(guid) and guid > 0 -> Guid.entity_type(guid) != :player
      _uncontrolled -> true
    end
  end

  def pet?(%Mob{object: %{guid: guid}}) when is_integer(guid), do: Guid.high_guid(guid) == Guid.high_guid(:pet)
  def pet?(_entity), do: false
end
