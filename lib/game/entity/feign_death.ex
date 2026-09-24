defmodule ThistleTea.Game.Entity.FeignDeath do
  @moduledoc """
  Samples Feign Death resistance from current hostile references and pet state.
  Player-controlled opponents never resist the feign attempt.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Aggro
  alias ThistleTea.Game.Entity.Logic.FeignDeath
  alias ThistleTea.Game.Entity.Logic.SpellResist
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  def prepare(entity, %CastContext{} = context, spell, now, opts \\ []) do
    if FeignDeath.spell?(spell) do
      attempt = %FeignDeath.Attempt{
        resisted?: Enum.any?(opponents(entity, now), &(not SpellResist.spell_hit?(entity, spell, &1, false, opts))),
        pet_in_combat?: pet_in_combat?(entity)
      }

      %{context | feign_death: attempt}
    else
      context
    end
  end

  defp opponents(%Character{internal: %{threat_refs: refs}} = character, now) do
    for {guid, incarnation} <- Enum.sort(refs || MapSet.new()),
        metadata = Metadata.get(guid),
        match?(%{alive?: true, incarnation_id: ^incarnation}, metadata),
        Guid.entity_type(guid) == :mob,
        not player_owned?(metadata),
        within_attack_range?(character, guid, metadata, now),
        do: metadata
  end

  defp opponents(_entity, _now), do: []

  defp player_owned?(%{owner_guid: owner}) when is_integer(owner) and owner > 0, do: Guid.entity_type(owner) == :player

  defp player_owned?(_metadata), do: false

  defp within_attack_range?(character, guid, metadata, now) do
    case {World.position(character, now), World.position(guid, now)} do
      {{world, x, y, z}, {world, mx, my, mz}} ->
        Math.distance({x, y, z}, {mx, my, mz}) <= Aggro.radius(metadata, character.unit.level)

      _ ->
        false
    end
  end

  defp pet_in_combat?(%Character{} = character) do
    case Metadata.get(Character.controlled_guid(character)) do
      %{alive?: true, in_combat: true, victim_guid: victim} when is_integer(victim) and victim > 0 -> true
      _ -> false
    end
  end

  defp pet_in_combat?(_entity), do: false
end
