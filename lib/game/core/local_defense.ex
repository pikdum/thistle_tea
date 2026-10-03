defmodule ThistleTea.Game.Core.LocalDefense do
  @moduledoc """
  The LocalDefense "under attack" alert, after vmangos
  `Creature::SendZoneUnderAttackMessage`: a player killing a town guard or a
  creature that flags its killer for PvP warns the other team on that map
  that the creature's area is under attack, at most once every ten seconds
  per area.
  """

  alias ThistleTea.Game.Core.Creature.CreatureFlags
  alias ThistleTea.Game.Core.Entity.Mob

  @cooldown_ms 10_000

  def defender?(%Mob{internal: %{pet: nil}} = mob),
    do: CreatureFlags.guard?(mob) or CreatureFlags.has?(mob, :pvp_enabling)

  def defender?(_entity), do: false

  def alert(cooldowns, area_id, now) when is_map(cooldowns) and is_integer(area_id) and is_integer(now) do
    case Map.fetch(cooldowns, area_id) do
      {:ok, alerted_at} when alerted_at + @cooldown_ms >= now -> {:quiet, cooldowns}
      _due -> {:alert, Map.put(cooldowns, area_id, now)}
    end
  end

  def defending?(attacking_team, team), do: team in [:alliance, :horde] and team != attacking_team
end
