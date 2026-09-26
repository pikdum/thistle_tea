defmodule ThistleTea.Game.Entity.Logic.Aura.DeathItem do
  @moduledoc """
  Captures death-item rewards before death removes their auras. Soul Shards
  require a non-gray honor or experience target and, for creatures, a tap.
  Other death items use only their spell-defined item and quantity.
  """

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.DamageOrigin
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell

  defmodule Victim do
    @moduledoc false
    defstruct [:level, :tap, player?: false, shard_target?: true]
  end

  def enqueue_rewards(entity, old_health, new_health)

  def enqueue_rewards(entity, old_health, new_health)
      when is_number(old_health) and old_health > 0 and is_number(new_health) and new_health <= 0 do
    Effects.enqueue(entity, reward_events(entity))
  end

  def enqueue_rewards(entity, _old_health, _new_health), do: entity

  def reward_events(%{unit: %Unit{auras: holders}} = entity) when is_list(holders) do
    victim = victim(entity)

    holders
    |> Enum.with_index()
    |> Enum.flat_map(fn {holder, index} -> holder_rewards(holder, victim, index) end)
    |> Enum.uniq_by(fn {key, _reward} -> key end)
    |> Enum.map(fn {_key, reward} -> reward end)
  end

  def reward_events(_entity), do: []

  def eligible?(%Effects.DeathItemReward{item_id: 6265, victim: %Victim{} = victim}, caster_level, tapped?)
      when is_integer(caster_level) and caster_level > 0 and is_integer(victim.level) do
    victim.shard_target? and victim.level > Experience.gray_level(caster_level) and (victim.player? or tapped?)
  end

  def eligible?(%Effects.DeathItemReward{item_id: 6265}, _caster_level, _tapped?), do: false
  def eligible?(%Effects.DeathItemReward{}, _caster_level, _tapped?), do: true

  defp victim(%{unit: %Unit{level: level}, player: %Player{}}), do: %Victim{level: level, player?: true}

  defp victim(%{unit: %Unit{level: level}, internal: %Internal{} = internal} = entity) do
    %Victim{
      level: level,
      tap: tap(internal.loot),
      shard_target?:
        not pet?(entity) and is_nil(internal.totem) and damage_eligible?(entity) and
          not match?(%Creature{experience_multiplier: multiplier} when multiplier == 0, internal.creature)
    }
  end

  defp damage_eligible?(%Mob{} = mob), do: DamageOrigin.loot_allowed?(mob)
  defp damage_eligible?(_entity), do: true

  defp pet?(%{object: %{guid: guid}}) when is_integer(guid), do: Guid.high_guid(guid) == Guid.high_guid(:pet)
  defp pet?(_entity), do: false

  defp tap(%Loot{tapped_by: tap}), do: tap
  defp tap(_loot), do: nil

  defp holder_rewards(%Holder{spell: %Spell{} = spell, caster_guid: caster, auras: auras}, victim, holder_index) do
    auras
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {%Aura{type: :channel_death_item, item_type: item, amount: count}, index}
      when is_integer(item) and item > 0 and is_integer(count) and count > 0 ->
        key = if spell.spell_family == 5, do: {:warlock, caster}, else: {holder_index, index}
        [{key, %Effects.DeathItemReward{target_guid: caster, item_id: item, count: count, victim: victim}}]

      _aura ->
        []
    end)
  end

  defp holder_rewards(_holder, _victim, _index), do: []
end
