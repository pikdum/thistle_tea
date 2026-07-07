defmodule ThistleTea.Game.Entity.Logic.Threat do
  @moduledoc """
  Per-mob threat table and victim selection, following vmangos'
  `ThreatManager`: damage accrues threat toward the attacker, heals accrue
  threat toward the healer on every mob fighting the healed unit, and the
  current victim is only overtaken when a candidate exceeds 110% of its
  threat in melee range or 130% at range. The table lives on
  `internal.threat` and is wiped when the mob leaves combat.
  """
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  @melee_overtake_ratio 1.1
  @ranged_overtake_ratio 1.3
  @heal_threat_ratio 0.5

  def heal_threat_ratio, do: @heal_threat_ratio

  def heal_threat_events(entity, healer_guid, healing)

  def heal_threat_events(
        %{object: %{guid: healed_guid}, unit: %Unit{health: health, max_health: max_health}},
        healer_guid,
        healing
      )
      when is_integer(healer_guid) and healer_guid > 0 and is_number(healing) and healing > 0 and is_number(health) and
             is_number(max_health) do
    case min(healing, max(max_health - health, 0)) do
      gain when gain > 0 -> [Event.heal_threat(healer_guid, healed_guid, gain * @heal_threat_ratio)]
      _no_gain -> []
    end
  end

  def heal_threat_events(_entity, _healer_guid, _healing), do: []

  def add(entity, source_guid, amount)

  def add(%Mob{object: %{guid: self_guid}, internal: %Internal{} = internal} = entity, source_guid, amount)
      when is_integer(source_guid) and source_guid > 0 and source_guid != self_guid and is_number(amount) and
             amount >= 0 do
    existing = internal.threat || %{}
    table = Map.update(existing, source_guid, amount / 1, &(&1 + amount))
    entity = %{entity | internal: %{internal | threat: table}}

    if Map.has_key?(existing, source_guid) do
      entity
    else
      Event.enqueue(entity, Event.threat_ref_gained(source_guid))
    end
  end

  def add(entity, _source_guid, _amount), do: entity

  def add_damage(%Mob{internal: %Internal{in_combat: true}} = entity, source_guid, damage) do
    add(entity, source_guid, damage)
  end

  def add_damage(entity, _source_guid, _damage), do: entity

  def taunt(%Mob{internal: %Internal{threat: table}} = entity, taunter_guid)
      when is_map(table) and is_integer(taunter_guid) do
    top = table |> Map.values() |> Enum.max(fn -> 0.0 end)
    entity = add(entity, taunter_guid, 0)

    case entity.internal.threat do
      %{^taunter_guid => current} = table ->
        %{entity | internal: %{entity.internal | threat: Map.put(table, taunter_guid, max(current, top))}}

      _rejected ->
        entity
    end
  end

  def taunt(entity, _taunter_guid), do: entity

  def wipe(%Mob{internal: %Internal{threat: table} = internal} = entity) when is_map(table) do
    entity = %{entity | internal: %{internal | threat: %{}}}

    table
    |> Map.keys()
    |> Enum.reduce(entity, &Event.enqueue(&2, Event.threat_ref_lost(&1)))
  end

  def wipe(%Mob{internal: %Internal{} = internal} = entity) do
    %{entity | internal: %{internal | threat: %{}}}
  end

  def wipe(entity), do: entity

  def tracking?(%Mob{internal: %Internal{threat: table}}, guid) when is_map(table) do
    Map.has_key?(table, guid)
  end

  def tracking?(_entity, _guid), do: false

  def entries(%Mob{internal: %Internal{threat: table}}) when is_map(table) do
    Enum.sort_by(table, fn {_guid, threat} -> threat end, :desc)
  end

  def entries(_entity), do: []

  def reselect(entity, opts \\ [])

  def reselect(%Mob{unit: %Unit{target: current}, internal: %Internal{threat: table}} = entity, opts)
      when is_map(table) do
    valid? = Keyword.get_lazy(opts, :valid?, fn -> &Hostility.valid_hostile_target?(entity, &1) end)
    in_melee? = Keyword.get_lazy(opts, :in_melee?, fn -> &in_melee_range?(entity, &1) end)

    {kept, dropped} = Enum.split_with(table, fn {guid, _threat} -> valid?.(guid) end)
    pruned = Map.new(kept)

    entity =
      dropped
      |> Enum.reduce(%{entity | internal: %{entity.internal | threat: pruned}}, fn {guid, _threat}, acc ->
        Event.enqueue(acc, Event.threat_ref_lost(guid))
      end)

    sorted = Enum.sort_by(pruned, fn {_guid, threat} -> threat end, :desc)

    current_threat =
      if is_integer(current) and current > 0 and Map.has_key?(pruned, current) do
        Map.fetch!(pruned, current)
      end

    decision =
      case taunt_caster(entity) do
        taunter when is_integer(taunter) and taunter != current ->
          if valid?.(taunter), do: {:switch, taunter}, else: decide(sorted, current, current_threat, in_melee?)

        taunter when is_integer(taunter) ->
          :keep

        _no_taunt ->
          decide(sorted, current, current_threat, in_melee?)
      end

    {entity, decision}
  end

  def reselect(entity, _opts), do: {entity, :keep}

  defp decide([], _current, _current_threat, _in_melee?), do: :keep

  defp decide([{top_guid, _threat} | _rest], current, nil, _in_melee?) do
    if top_guid == current, do: :keep, else: {:switch, top_guid}
  end

  defp decide([{guid, _threat} | _rest], current, _current_threat, _in_melee?) when guid == current, do: :keep

  defp decide([{_guid, threat} | _rest], _current, current_threat, _in_melee?)
       when threat <= current_threat * @melee_overtake_ratio, do: :keep

  defp decide([{guid, threat} | rest], current, current_threat, in_melee?) do
    if threat > current_threat * @ranged_overtake_ratio or in_melee?.(guid) do
      {:switch, guid}
    else
      decide(rest, current, current_threat, in_melee?)
    end
  end

  defp taunt_caster(%Mob{unit: %Unit{auras: holders}}) when is_list(holders) do
    holders
    |> Enum.find(&Holder.has_aura_type?(&1, :mod_taunt))
    |> case do
      %Holder{caster_guid: caster_guid} -> caster_guid
      _no_taunt -> nil
    end
  end

  defp taunt_caster(_entity), do: nil

  defp in_melee_range?(%Mob{} = entity, guid) do
    case World.distance_to_guid(entity, guid) do
      distance when is_number(distance) ->
        distance <= Combat.melee_reach(own_combat_reach(entity), target_combat_reach(guid))

      _ ->
        false
    end
  end

  defp own_combat_reach(%Mob{unit: %Unit{combat_reach: reach}}) when is_number(reach) and reach > 0, do: reach
  defp own_combat_reach(%Mob{}), do: Unit.default_combat_reach()

  defp target_combat_reach(guid) do
    case Metadata.query(guid, [:combat_reach]) do
      %{combat_reach: reach} when is_number(reach) -> reach
      _ -> Unit.default_combat_reach()
    end
  end
end
