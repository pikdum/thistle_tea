defmodule ThistleTea.Game.Spell.Cooldowns do
  @moduledoc """
  Owns spell cooldown sources and deadlines. Deferred entries retain the
  cast's item overrides until their event starts the timer. Category blocking
  is derived from those entries; global and school locks are plain deadlines.
  """
  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cooldowns.Entry
  alias ThistleTea.Game.Spell.Modifiers

  def start(entity, spell, now, item_id \\ 0)

  def start(%{internal: internal} = entity, %Spell{} = spell, now, item_id) when is_integer(now) do
    entry = %Entry{
      spell: spell,
      item_id: item_id,
      category: spell.category || 0,
      started_at: now,
      pending?: Spell.attribute?(spell, :cooldown_on_event)
    }

    entry = if entry.pending?, do: entry, else: activate_entry(entity, entry, now)
    cooldowns = internal |> active(now) |> Map.put(spell.id, entry)
    entity = %{entity | internal: %{internal | cooldowns: prune(cooldowns, now)}}
    if entry.pending?, do: entity, else: queue_client_cooldown(entity, with_cooldown_modifiers(entity, spell))
  end

  def start(entity, _spell, _now, _item_id), do: entity

  defp queue_client_cooldown(%{object: %{guid: guid}} = entity, %Spell{id: spell_id} = spell) when is_integer(guid) do
    if Spell.attribute?(spell, :cooldown_on_event) do
      entity
    else
      case client_cooldown_ms(spell) do
        cooldown_ms when cooldown_ms > 0 -> Effects.enqueue(entity, Effects.spell_cooldown(guid, spell_id, cooldown_ms))
        _ -> entity
      end
    end
  end

  defp queue_client_cooldown(entity, _spell), do: entity

  def trigger_gcd(%{internal: internal} = entity, %Spell{} = spell, now) when is_integer(now) do
    case gcd_duration(entity, spell) do
      duration when duration > 0 ->
        cooldowns = internal |> active(now) |> Map.put({:gcd, spell.gcd_category}, now + duration)
        %{entity | internal: %{internal | cooldowns: cooldowns}}

      _ ->
        entity
    end
  end

  def trigger_gcd(entity, _spell, _now), do: entity

  def gcd_duration(%Character{} = entity, %Spell{} = spell) do
    base = positive(spell.gcd_ms)

    if spell.gcd_category > 0 or base > 0 do
      entity |> Modifiers.value(spell, :global_cooldown, base) |> trunc() |> max(0)
    else
      0
    end
  end

  def gcd_duration(_entity, %Spell{} = spell), do: positive(spell.gcd_ms)

  def on_gcd?(%{internal: internal}, %Spell{gcd_category: category}, now) when is_integer(now),
    do: locked_until?(Map.get(stored(internal), {:gcd, category}), now)

  def on_gcd?(_entity, _spell, _now), do: false

  def reset_gcd(%{internal: internal} = entity, %Spell{gcd_category: category}) do
    %{entity | internal: %{internal | cooldowns: Map.delete(stored(internal), {:gcd, category})}}
  end

  def lock_schools(%{internal: internal} = entity, school_mask, duration_ms, now)
      when is_integer(school_mask) and school_mask > 0 and is_integer(duration_ms) and duration_ms > 0 and
             is_integer(now) do
    until_ms = now + duration_ms

    cooldowns =
      Enum.reduce(0..6, stored(internal), fn index, acc ->
        if (school_mask &&& 1 <<< index) == 0 do
          acc
        else
          Map.update(acc, {:school, index}, until_ms, &max(&1, until_ms))
        end
      end)

    entity = %{entity | internal: %{internal | cooldowns: cooldowns}}

    case school_cooldowns(entity, now) do
      [] ->
        entity

      cooldowns ->
        Effects.enqueue(entity, %Effects.SpellSchoolLockout{source_guid: entity.object.guid, cooldowns: cooldowns})
    end
  end

  def lock_schools(entity, _school_mask, _duration_ms, _now), do: entity

  def school_cooldowns(%{internal: %{spellbook: spellbook} = internal} = entity, now) when is_map(spellbook) do
    spellbook
    |> Map.values()
    |> Enum.flat_map(fn spell ->
      remaining = school_remaining(stored(internal), spell, now)

      if remaining > 0 and remaining > remaining_ms(ready_at(entity, spell), now) and is_nil(pending(entity, spell.id)),
        do: [{spell.id, remaining}],
        else: []
    end)
    |> Enum.sort()
  end

  def school_cooldowns(_entity, _now), do: []

  def school_locked?(%{internal: internal}, school_mask, now)
      when is_integer(school_mask) and school_mask > 0 and is_integer(now) do
    cooldowns = stored(internal)

    Enum.any?(0..6, fn index ->
      (school_mask &&& 1 <<< index) != 0 and locked_until?(Map.get(cooldowns, {:school, index}), now)
    end)
  end

  def school_locked?(_entity, _school_mask, _now), do: false

  defp locked_until?(until_ms, now) when is_integer(until_ms), do: until_ms > now
  defp locked_until?(_entry, _now), do: false

  def on_cooldown?(%{internal: internal}, %Spell{} = spell, now) when is_integer(now) do
    internal |> stored() |> matching(spell) |> Enum.any?(&blocked?(&1, spell, now))
  end

  def on_cooldown?(_entity, _spell, _now), do: false

  def ready_at(%{internal: internal}, %Spell{} = spell) do
    internal
    |> stored()
    |> matching(spell)
    |> Enum.flat_map(&deadlines(&1, spell))
    |> Enum.filter(&is_integer/1)
    |> Enum.max(fn -> nil end)
  end

  def ready_at(_entity, _spell), do: nil

  def activate_on_event(entity, holders, now) when is_list(holders) and is_integer(now) do
    holders
    |> Enum.filter(&Spell.attribute?(&1.spell, :cooldown_on_event))
    |> Enum.reject(&retained_holder?(entity, &1))
    |> Enum.uniq_by(&{&1.spell.id, &1.caster_guid})
    |> Enum.reduce({entity, []}, fn holder, {entity, events} ->
      {entity, next} = release_holder(entity, holder, now)
      {entity, events ++ next}
    end)
  end

  def activate_on_event(entity, _holders, _now), do: {entity, []}

  defp retained_holder?(%{unit: %{auras: holders}}, removed) when is_list(holders) do
    Enum.any?(holders, &(&1.spell.id == removed.spell.id and &1.caster_guid == removed.caster_guid))
  end

  defp retained_holder?(_entity, _removed), do: false

  defp release_holder(%{object: %{guid: guid}} = entity, holder, now) do
    if holder.caster_guid in [nil, guid] do
      activate(entity, holder.spell.id, now, holder.cooldown_started_at)
    else
      {entity,
       [
         %Effects.ActivateCooldown{
           target_guid: holder.caster_guid,
           spell_id: holder.spell.id,
           started_at: holder.cooldown_started_at
         }
       ]}
    end
  end

  def handle_event(entity, %Effects.ActivateCooldown{cancel?: false} = event, now),
    do: activate(entity, event.spell_id, now, event.started_at)

  def handle_event(%{object: %{guid: guid}, internal: internal} = entity, %Effects.ActivateCooldown{} = event, _now) do
    case pending(entity, event.spell_id) do
      %Entry{started_at: started_at} when started_at == event.started_at ->
        cooldowns = Map.delete(stored(internal), event.spell_id)
        {%{entity | internal: %{internal | cooldowns: cooldowns}}, [Effects.clear_cooldown(guid, event.spell_id)]}

      _ ->
        {entity, []}
    end
  end

  def activate(entity, spell_id, now, started_at \\ nil)

  def activate(%{object: %{guid: guid}, internal: internal} = entity, spell_id, now, started_at) when is_integer(now) do
    case Map.get(stored(internal), spell_id) do
      %Entry{pending?: true} = entry when is_nil(started_at) or entry.started_at == started_at ->
        entry = activate_entry(entity, entry, now)
        cooldowns = internal |> stored() |> Map.put(spell_id, entry) |> prune(now)
        {%{entity | internal: %{internal | cooldowns: cooldowns}}, [Effects.cooldown_event(guid, spell_id)]}

      _inactive ->
        {entity, []}
    end
  end

  def activate(entity, _spell_id, _now, _started_at), do: {entity, []}

  def pending(%{internal: internal}, spell_id) do
    case Map.get(stored(internal), spell_id) do
      %Entry{pending?: true} = entry -> entry
      _ -> nil
    end
  end

  def initial(%{internal: internal}, spellbook, now) when is_map(spellbook) and is_integer(now) do
    cooldowns = stored(internal)

    sources =
      cooldowns
      |> Map.values()
      |> Enum.filter(&is_struct(&1, Entry))
      |> Map.new(&{&1.spell.id, &1.spell})
      |> then(&Map.merge(spellbook, &1))

    sources
    |> Map.values()
    |> Enum.map(&initial_entry(cooldowns, &1, now))
    |> Enum.filter(&(&1.spell_ms > 0 or &1.category_ms > 0))
    |> Enum.sort_by(& &1.spell_id)
  end

  def initial(_entity, _spellbook, _now), do: []

  def reset(%{internal: internal} = entity, keys) when is_list(keys) do
    categories = for {:category, category} <- keys, do: category

    cooldowns =
      internal
      |> stored()
      |> Map.drop(keys)
      |> Map.new(fn
        {id, %Entry{} = entry} ->
          entry = if entry.category in categories, do: %{entry | category: 0, category_ready_at: nil}, else: entry
          {id, entry}

        entry ->
          entry
      end)

    %{entity | internal: %{internal | cooldowns: cooldowns}}
  end

  def reset(entity, _keys), do: entity

  def reset_family(%{internal: %{spellbook: spellbook}} = entity, spell_family) when is_map(spellbook) do
    reset_matching(entity, &(&1.spell_family == spell_family))
  end

  def reset_family(entity, _spell_family), do: entity

  def reset_matching(%{object: %{guid: guid}, internal: %{spellbook: spellbook} = internal} = entity, predicate)
      when is_integer(guid) and is_map(spellbook) and is_function(predicate, 1) do
    cooldowns = stored(internal)

    spells =
      spellbook
      |> Map.values()
      |> Enum.filter(&(predicate.(&1) and client_cooldown_ms(&1) > 0 and matching(cooldowns, &1) != []))

    entity
    |> reset(Enum.flat_map(spells, &keys/1))
    |> Effects.enqueue(Enum.map(spells, &Effects.clear_cooldown(guid, &1.id)))
  end

  def reset_matching(entity, _predicate), do: entity

  def client_cooldown_ms(%Spell{recovery_time_ms: recovery, category_recovery_time_ms: category_recovery}) do
    max(positive(recovery), positive(category_recovery))
  end

  def client_cooldown_ms(_spell), do: 0

  defp with_cooldown_modifiers(entity, %Spell{} = spell) do
    if positive(spell.recovery_time_ms) > 0 do
      %{spell | recovery_time_ms: modified_recovery(entity, spell, spell.recovery_time_ms)}
    else
      %{spell | category_recovery_time_ms: modified_recovery(entity, spell, spell.category_recovery_time_ms)}
    end
  end

  defp modified_recovery(entity, spell, recovery) when is_integer(recovery) and recovery > 0 do
    Modifiers.integer_value(entity, spell, :cooldown, recovery)
  end

  defp modified_recovery(_entity, _spell, recovery), do: recovery

  defp activate_entry(entity, %Entry{spell: spell} = entry, now) do
    modified = with_cooldown_modifiers(entity, spell)

    %{
      entry
      | pending?: false,
        ready_at: deadline(modified.recovery_time_ms, now),
        category_ready_at: if(entry.category > 0, do: deadline(modified.category_recovery_time_ms, now))
    }
  end

  defp deadline(duration, now) when is_integer(duration) and duration > 0, do: now + duration
  defp deadline(_duration, _now), do: nil

  defp matching(cooldowns, %Spell{} = spell) do
    Enum.filter(cooldowns, fn
      {id, %Entry{} = entry} -> id == spell.id or same_category?(entry, spell)
      {key, _value} -> key in keys(spell)
    end)
  end

  defp same_category?(%Entry{category: category}, %Spell{category: category})
       when is_integer(category) and category > 0, do: true

  defp same_category?(_source, _spell), do: false

  defp blocked?({_id, %Entry{pending?: true}}, _spell, _now), do: true
  defp blocked?(entry, spell, now), do: Enum.any?(deadlines(entry, spell), &locked_until?(&1, now))

  defp deadlines({id, %Entry{} = entry}, spell) do
    [if(id == spell.id, do: entry.ready_at), if(same_category?(entry, spell), do: entry.category_ready_at)]
  end

  defp deadlines({_key, ready_at}, _spell) when is_integer(ready_at), do: [ready_at]
  defp deadlines(_entry, _spell), do: []

  defp initial_entry(cooldowns, spell, now) do
    school_ms = school_remaining(cooldowns, spell, now)

    case Map.get(cooldowns, spell.id) do
      %Entry{} = entry ->
        %{
          spell_id: spell.id,
          item_id: entry.item_id,
          category: entry.category,
          spell_ms: if(entry.pending?, do: 1, else: max(remaining_ms(entry.ready_at, now), school_ms)),
          category_ms: if(entry.pending?, do: 0x80000000, else: remaining_ms(entry.category_ready_at, now))
        }

      deadline ->
        %{
          spell_id: spell.id,
          item_id: 0,
          category: spell.category || 0,
          spell_ms: max(remaining_ms(deadline, now), school_ms),
          category_ms: remaining_ms(Map.get(cooldowns, {:category, spell.category}), now)
        }
    end
  end

  defp school_remaining(cooldowns, %Spell{} = spell, now) do
    if Spell.attribute?(spell, :cooldown_on_event) do
      0
    else
      mask = Spell.school_mask(spell)

      0..6
      |> Enum.filter(&((mask &&& 1 <<< &1) != 0))
      |> Enum.map(&remaining_ms(Map.get(cooldowns, {:school, &1}), now))
      |> Enum.max(fn -> 0 end)
    end
  end

  defp keys(%Spell{id: spell_id, category: category}) do
    case positive(category) do
      0 -> [spell_id]
      category -> [spell_id, {:category, category}]
    end
  end

  defp active(internal, now), do: internal |> stored() |> prune(now)

  defp prune(cooldowns, now) do
    Map.filter(cooldowns, fn
      {_key, %Entry{pending?: true}} -> true
      {_key, %Entry{} = entry} -> locked_until?(entry.ready_at, now) or locked_until?(entry.category_ready_at, now)
      {_key, ready_at} -> locked_until?(ready_at, now)
    end)
  end

  defp stored(internal), do: internal.cooldowns || %{}

  defp positive(value) when is_integer(value) and value > 0, do: value
  defp positive(_value), do: 0

  defp remaining_ms(ready_at, now) when is_integer(ready_at), do: max(ready_at - now, 0)
  defp remaining_ms(_ready_at, _now), do: 0
end
