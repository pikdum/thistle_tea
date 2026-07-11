defmodule ThistleTea.Game.Spell.Cooldowns do
  @moduledoc """
  Pure spell and category cooldown state kept on `internal.cooldowns` as a map
  of `spell_id` / `{:category, id}` keys to ready-at timestamps. `start/3`
  owns the whole lifecycle when a cast fires: it records the ready-at entries
  and enqueues the client cooldown event; `on_cooldown?/3` checks before the
  next cast. Expiry is just a timestamp comparison, no timers.
  """
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell

  def start(%{internal: internal} = entity, %Spell{} = spell, now) when is_integer(now) do
    case initial_entries(spell, now) do
      [] ->
        entity

      entries ->
        cooldowns =
          internal
          |> active(now)
          |> Map.merge(Map.new(entries))

        %{entity | internal: %{internal | cooldowns: cooldowns}}
        |> queue_client_cooldown(spell)
    end
  end

  def start(entity, _spell, _now), do: entity

  defp queue_client_cooldown(%{object: %{guid: guid}} = entity, %Spell{id: spell_id} = spell) when is_integer(guid) do
    if Spell.attribute?(spell, :cooldown_on_event) do
      entity
    else
      case client_cooldown_ms(spell) do
        cooldown_ms when cooldown_ms > 0 -> Event.enqueue(entity, Event.spell_cooldown(guid, spell_id, cooldown_ms))
        _ -> entity
      end
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
        {:on_event, _spell_id} -> true
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

  def activate_on_event(%{object: %{guid: guid}, internal: internal} = entity, holders, now)
      when is_list(holders) and is_integer(now) do
    spells =
      holders
      |> Enum.map(fn %Holder{spell: spell} -> spell end)
      |> Enum.filter(&Spell.attribute?(&1, :cooldown_on_event))
      |> Enum.uniq_by(& &1.id)

    cooldowns =
      Enum.reduce(spells, stored(internal), fn spell, acc ->
        acc
        |> Map.drop(keys(spell))
        |> Map.merge(Map.new(entries(spell, now)))
      end)

    events = Enum.map(spells, &Event.cooldown_event(guid, &1.id))
    {%{entity | internal: %{internal | cooldowns: cooldowns}}, events}
  end

  def activate_on_event(entity, _holders, _now), do: {entity, []}

  def initial(%{internal: internal}, spellbook, now) when is_map(spellbook) and is_integer(now) do
    cooldowns = stored(internal)

    spellbook
    |> Map.values()
    |> Enum.map(fn %Spell{} = spell ->
      %{
        spell_id: spell.id,
        category: spell.category || 0,
        spell_ms: remaining_ms(Map.get(cooldowns, spell.id), now),
        category_ms: remaining_ms(Map.get(cooldowns, {:category, spell.category}), now)
      }
    end)
    |> Enum.filter(&(&1.spell_ms > 0 or &1.category_ms > 0))
  end

  def initial(_entity, _spellbook, _now), do: []

  def reset(%{internal: internal} = entity, keys) when is_list(keys) do
    %{entity | internal: %{internal | cooldowns: Map.drop(stored(internal), keys)}}
  end

  def reset(entity, _keys), do: entity

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

  defp initial_entries(%Spell{} = spell, now) do
    if Spell.attribute?(spell, :cooldown_on_event) and client_cooldown_ms(spell) > 0 do
      Enum.map(keys(spell), &{&1, {:on_event, spell.id}})
    else
      entries(spell, now)
    end
  end

  defp keys(%Spell{id: spell_id, category: category}) do
    case positive(category) do
      0 -> [spell_id]
      category -> [spell_id, {:category, category}]
    end
  end

  defp active(internal, now) do
    internal
    |> stored()
    |> Map.filter(fn
      {_key, ready_at} when is_integer(ready_at) -> ready_at > now
      {_key, {:on_event, _spell_id}} -> true
      _entry -> false
    end)
  end

  defp stored(internal) do
    case internal.cooldowns do
      cooldowns when is_map(cooldowns) -> cooldowns
      _ -> %{}
    end
  end

  defp positive(value) when is_integer(value) and value > 0, do: value
  defp positive(_value), do: 0

  defp remaining_ms(ready_at, now) when is_integer(ready_at), do: max(ready_at - now, 0)
  defp remaining_ms(_ready_at, _now), do: 0
end
