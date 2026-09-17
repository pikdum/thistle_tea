defmodule ThistleTea.Game.Entity.Logic.Pickpocket do
  @moduledoc """
  Pick Pocket admission and private loot policy. Ordinary pocket loot is rolled
  once per creature life; later rogues can only receive their own quest drops.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot, as: InternalLoot
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.Loot.Actor
  alias ThistleTea.Game.Entity.Logic.LootSession
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell

  def spell?(%Spell{effects: effects}), do: Enum.any?(effects, &(&1.type == :pickpocket))

  def validate(caster, %Spell{} = spell, target) do
    if spell?(spell), do: validate_target(caster, target), else: :ok
  end

  def validate_target(%Character{} = caster, target) when is_map(target) do
    cond do
      not Aura.has_aura?(caster, :mod_stealth) -> {:error, :only_stealthed}
      not creature?(target) -> {:error, :bad_targets}
      Map.get(target, :alive?) != true -> {:error, :targets_dead}
      Map.get(target, :friendly?) != false -> {:error, :bad_targets}
      not pockets?(Map.get(target, :pickpocket_id)) -> {:error, :target_no_pockets}
      true -> :ok
    end
  end

  def validate_target(_caster, _target), do: {:error, :bad_targets}

  def available?(%Mob{internal: %Internal{loot: %InternalLoot{pickpocket_id: id}, pet: nil}} = mob) do
    not Core.dead?(mob) and pockets?(id)
  end

  def available?(_mob), do: false

  def session(%Loot{} = loot, %Actor{guid: guid}, previously_picked?) do
    loot = if previously_picked?, do: %{loot | gold: 0, items: Enum.filter(loot.items, & &1.quest_item)}, else: loot
    LootSession.new(loot, guid)
  end

  defp creature?(%{guid: guid} = target) when is_integer(guid) do
    Guid.entity_type(guid) == :mob and Map.get(target, :owner_guid) in [nil, 0]
  end

  defp creature?(_target), do: false
  defp pockets?(id), do: is_integer(id) and id > 0
end
