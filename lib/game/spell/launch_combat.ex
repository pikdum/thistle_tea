defmodule ThistleTea.Game.Spell.LaunchCombat do
  @moduledoc "Combat windows started by an explicit spell target before any impact contact."

  alias ThistleTea.Game.Entity.Logic.CombatTimer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell

  @pvp_combat_ms 5_000

  def duration(source, %Spell{} = spell, target, delay_ms) do
    active =
      if Spell.attribute?(spell, :active_threat) and (source.guid != target.guid or source[:in_combat] == true),
        do: @pvp_combat_ms,
        else: 0

    projectile =
      if projectile?(source, spell, target, delay_ms),
        do: max(delay_ms + 500, if(CombatTimer.uses_timer?(target), do: @pvp_combat_ms, else: 0)),
        else: 0

    duration = max(active, projectile)
    if duration > 0, do: duration
  end

  defp projectile?(source, spell, target, delay_ms) do
    source.guid != target.guid and player_controlled?(source) and delay_ms > 0 and spell.speed > 0 and
      Spell.harmful?(spell) and not Spell.attribute?(spell, :no_threat) and
      not Spell.attribute?(spell, :threat_only_on_miss) and not Spell.attribute?(spell, :no_initial_threat)
  end

  defp player_controlled?(actor), do: player_guid?(actor.guid) or player_guid?(actor[:owner_guid])

  defp player_guid?(guid) when is_integer(guid) and guid > 0, do: Guid.entity_type(guid) == :player
  defp player_guid?(_guid), do: false
end
