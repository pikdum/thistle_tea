defmodule ThistleTea.Game.Entity.Logic.Aura.DeathItem do
  @moduledoc """
  Creates DBC-defined death items for eligible aura casters when a tapped
  creature crosses the living-to-dead health transition.
  """
  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Experience

  def enqueue_rewards(entity, old_health, new_health)

  def enqueue_rewards(entity, old_health, new_health)
      when is_number(old_health) and old_health > 0 and is_number(new_health) and new_health <= 0 do
    Event.enqueue(entity, reward_events(entity))
  end

  def enqueue_rewards(entity, _old_health, _new_health), do: entity

  def reward_events(%{
        unit: %Unit{level: victim_level, auras: holders},
        internal: %Internal{loot: %Loot{tapped_by: %{player: tapped_player}}}
      })
      when is_integer(victim_level) and is_list(holders) and is_integer(tapped_player) do
    holders
    |> Enum.flat_map(&holder_rewards(&1, tapped_player, victim_level))
    |> Enum.uniq_by(fn {caster_guid, _item_type, _count} -> caster_guid end)
    |> Enum.map(fn {caster_guid, item_type, count} -> Event.create_item(caster_guid, item_type, count) end)
  end

  def reward_events(_entity), do: []

  defp holder_rewards(
         %Holder{caster_guid: caster_guid, caster_level: caster_level, auras: auras},
         caster_guid,
         victim_level
       )
       when is_integer(caster_level) and caster_level > 0 and victim_level > 0 do
    if victim_level > Experience.gray_level(caster_level) do
      Enum.flat_map(auras, &aura_reward(&1, caster_guid))
    else
      []
    end
  end

  defp holder_rewards(_holder, _tapped_player, _victim_level), do: []

  defp aura_reward(%Aura{type: :channel_death_item, item_type: item_type, amount: amount}, caster_guid)
       when is_integer(item_type) and item_type > 0 do
    [{caster_guid, item_type, max(amount || 0, 1)}]
  end

  defp aura_reward(_aura, _caster_guid), do: []
end
