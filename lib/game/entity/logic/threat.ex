defmodule ThistleTea.Game.Entity.Logic.Threat do
  @moduledoc """
  Per-mob threat table and victim selection, following vmangos'
  `ThreatManager`: damage accrues threat toward the attacker, heals accrue
  threat toward the healer on every mob fighting the healed unit, and the
  current victim is only overtaken when a candidate exceeds 110% of its
  threat in melee range or 130% at range. The table lives on
  `internal.threat` and is wiped when the mob leaves combat.
  """
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
    table = Map.update(internal.threat || %{}, source_guid, amount / 1, &(&1 + amount))
    %{entity | internal: %{internal | threat: table}}
  end

  def add(entity, _source_guid, _amount), do: entity

  def add_damage(%Mob{internal: %Internal{in_combat: true}} = entity, source_guid, damage) do
    add(entity, source_guid, damage)
  end

  def add_damage(entity, _source_guid, _damage), do: entity

  def taunt(%Mob{internal: %Internal{threat: table} = internal} = entity, taunter_guid)
      when is_map(table) and is_integer(taunter_guid) do
    top = table |> Map.values() |> Enum.max(fn -> 0.0 end)
    current = Map.get(table, taunter_guid, 0.0)
    %{entity | internal: %{internal | threat: Map.put(table, taunter_guid, max(current, top))}}
  end

  def taunt(entity, _taunter_guid), do: entity

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

    pruned = table |> Enum.filter(fn {guid, _threat} -> valid?.(guid) end) |> Map.new()
    entity = %{entity | internal: %{entity.internal | threat: pruned}}
    sorted = Enum.sort_by(pruned, fn {_guid, threat} -> threat end, :desc)

    current_threat =
      if is_integer(current) and current > 0 and Map.has_key?(pruned, current) do
        Map.fetch!(pruned, current)
      end

    {entity, decide(sorted, current, current_threat, in_melee?)}
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
