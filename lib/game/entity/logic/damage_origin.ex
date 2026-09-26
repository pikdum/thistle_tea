defmodule ThistleTea.Game.Entity.Logic.DamageOrigin do
  @moduledoc "Tracks player and NPC damage for creature loot eligibility and assisted-kill XP."

  alias ThistleTea.Game.Entity.Data.DamageOrigin, as: Totals
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.CreatureFlags
  alias ThistleTea.Game.Guid

  def record(%Mob{internal: internal, object: %{guid: guid}} = mob, health, damage, opts)
      when is_number(health) and health > 0 and is_number(damage) and damage > 0 do
    source = Keyword.get(opts, :source)
    owner = controlling_source(Keyword.get(opts, :source_owner), source)
    totals = internal.damage_origin

    totals =
      if self_damage?(source, guid) or player?(owner),
        do: %{totals | player: totals.player + damage},
        else: %{totals | npc: totals.npc + damage}

    %{mob | internal: %{internal | damage_origin: totals}}
  end

  def record(entity, _health, _damage, _opts), do: entity

  def loot_allowed?(%Mob{internal: %{damage_origin: %Totals{player: player, npc: npc}}} = mob) do
    CreatureFlags.has?(mob, :corpse_raid) or 65 * player > 35 * npc
  end

  def xp_multiplier(%Mob{internal: %{damage_origin: %Totals{player: player, npc: npc}}} = mob) do
    cond do
      CreatureFlags.has?(mob, :corpse_raid) -> 1.0
      loot_allowed?(mob) -> player / (player + npc)
      true -> 0.0
    end
  end

  defp player?(guid) when is_integer(guid) and guid > 0, do: Guid.entity_type(guid) == :player
  defp player?(_guid), do: false

  defp controlling_source(owner, _source) when is_integer(owner) and owner > 0, do: owner
  defp controlling_source(_owner, source), do: source

  defp self_damage?(source, guid) when is_integer(source) and source > 0, do: source == guid
  defp self_damage?(_source, _guid), do: false
end
