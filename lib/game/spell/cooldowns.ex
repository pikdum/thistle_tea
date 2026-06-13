defmodule ThistleTea.Game.Spell.Cooldowns do
  @moduledoc """
  Pure spell and category cooldown state kept on `internal.cooldowns` as a map
  of `spell_id` / `{:category, id}` keys to ready-at timestamps. `start/3`
  owns the whole lifecycle when a cast fires: it records the ready-at entries
  and enqueues the client cooldown event; `on_cooldown?/3` checks before the
  next cast. Expiry is just a timestamp comparison, no timers.
  """
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell

  def start(%{internal: internal} = entity, %Spell{} = spell, now) when is_integer(now) do
    case entries(spell, now) do
      [] ->
        entity

      entries ->
        cooldowns =
          internal
          |> active(now)
          |> Map.merge(Map.new(entries))

        %{entity | internal: Map.put(internal, :cooldowns, cooldowns)}
        |> queue_client_cooldown(spell)
    end
  end

  def start(entity, _spell, _now), do: entity

  defp queue_client_cooldown(%{object: %{guid: guid}} = entity, %Spell{id: spell_id} = spell) when is_integer(guid) do
    case client_cooldown_ms(spell) do
      cooldown_ms when cooldown_ms > 0 -> Event.enqueue(entity, Event.spell_cooldown(guid, spell_id, cooldown_ms))
      _ -> entity
    end
  end

  defp queue_client_cooldown(entity, _spell), do: entity

  def on_cooldown?(%{internal: internal}, %Spell{} = spell, now) when is_integer(now) do
    cooldowns = stored(internal)

    spell
    |> keys()
    |> Enum.any?(fn key ->
      case Map.get(cooldowns, key) do
        ready_at when is_integer(ready_at) -> ready_at > now
        _ -> false
      end
    end)
  end

  def on_cooldown?(_entity, _spell, _now), do: false

  def ready_at(%{internal: internal}, %Spell{} = spell) do
    spell
    |> keys()
    |> Enum.map(&Map.get(stored(internal), &1))
    |> Enum.filter(&is_integer/1)
    |> Enum.max(fn -> nil end)
  end

  def ready_at(_entity, _spell), do: nil

  def client_cooldown_ms(%Spell{recovery_time_ms: recovery, category_recovery_time_ms: category_recovery}) do
    max(positive(recovery), positive(category_recovery))
  end

  def client_cooldown_ms(_spell), do: 0

  defp entries(%Spell{id: spell_id, category: category} = spell, now) do
    spell_entry =
      case positive(spell.recovery_time_ms) do
        0 -> []
        recovery -> [{spell_id, now + recovery}]
      end

    category_entry =
      case {positive(category), positive(spell.category_recovery_time_ms)} do
        {0, _recovery} -> []
        {_category, 0} -> []
        {category, recovery} -> [{{:category, category}, now + recovery}]
      end

    spell_entry ++ category_entry
  end

  defp keys(%Spell{id: spell_id, category: category} = spell) do
    spell_key =
      case positive(spell.recovery_time_ms) do
        0 -> []
        _recovery -> [spell_id]
      end

    category_key =
      case {positive(category), positive(spell.category_recovery_time_ms)} do
        {0, _recovery} -> []
        {_category, 0} -> []
        {category, _recovery} -> [{:category, category}]
      end

    spell_key ++ category_key
  end

  defp active(internal, now) do
    internal
    |> stored()
    |> Map.filter(fn {_key, ready_at} -> is_integer(ready_at) and ready_at > now end)
  end

  defp stored(internal) do
    case Map.get(internal, :cooldowns) do
      cooldowns when is_map(cooldowns) -> cooldowns
      _ -> %{}
    end
  end

  defp positive(value) when is_integer(value) and value > 0, do: value
  defp positive(_value), do: 0
end
