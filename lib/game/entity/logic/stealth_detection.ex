defmodule ThistleTea.Game.Entity.Logic.StealthDetection do
  @moduledoc """
  Pure observer-specific detection rules for stealth, detection auras, and
  caster-specific marks. Positions and line of sight remain boundary inputs.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Invisibility

  @collision_distance 1.5
  @base_creature_distance 5.0 / 6.0
  @max_distance 30.0

  def target_metadata(%{unit: %Unit{level: level}} = entity) do
    level = level || 1
    stealthed? = Aura.has_aura?(entity, :mod_stealth)

    Map.merge(Invisibility.metadata(entity), %{
      stealthed?: stealthed?,
      stealth_skill: stealth_skill(entity, stealthed?, level),
      undetectable_until: entity.internal.undetectable_until,
      level: level,
      player?: match?(%Character{}, entity),
      stealth_detection_bonus: detection_bonus(entity),
      stunned?: Aura.has_aura?(entity, :mod_stun),
      stalked_by: stalked_by(entity)
    })
  end

  def detectable?(detector, target, distance, now, behind? \\ false)

  def detectable?(detector, target, distance, now, behind?) when is_map(detector) and is_map(target) do
    marked_by?(target, Map.get(detector, :guid)) or
      (Invisibility.detectable?(detector, target) and stealth_detectable?(detector, target, distance, now, behind?))
  end

  def detectable?(_detector, _target, _distance, _now, _behind?), do: false

  def marked_by?(target, guid) when is_integer(guid), do: guid in Map.get(target, :stalked_by, [])
  def marked_by?(_target, _guid), do: false

  defp stealth_detectable?(_detector, %{undetectable_until: expires_at}, _distance, now, _behind?)
       when is_integer(expires_at) and is_integer(now) and expires_at > now, do: false

  defp stealth_detectable?(_detector, %{stealthed?: false}, _distance, _now, _behind?), do: true

  defp stealth_detectable?(_detector, target, _distance, _now, _behind?) when not is_map_key(target, :stealthed?),
    do: true

  defp stealth_detectable?(%{stunned?: true}, _target, _distance, _now, _behind?), do: false

  defp stealth_detectable?(%{level: level} = detector, %{stealthed?: true} = target, distance, _now, behind?)
       when is_integer(level) and is_number(distance) do
    distance < @collision_distance or distance <= detection_distance(detector, target, behind?)
  end

  defp stealth_detectable?(_detector, _target, _distance, _now, _behind?), do: false

  def detection_distance(level, stealth_skill) when is_integer(level) and is_number(stealth_skill) do
    detection_distance(%{level: level}, %{stealth_skill: stealth_skill}, false)
  end

  def detection_distance(%{level: level} = detector, target, behind?) do
    player? = Map.get(detector, :player?, false)
    base = if player?, do: if(Map.get(target, :player?, false), do: 9.0, else: 21.0), else: @base_creature_distance
    yards_per_level = if player?, do: 1.5, else: @base_creature_distance
    scale = if level - Map.get(target, :level, level) > 3, do: 2, else: 1
    skill = level * 5 + Map.get(detector, :stealth_detection_bonus, 0) - Map.get(target, :stealth_skill, 0)
    distance = min(max(base + skill * yards_per_level * scale / 5, 0.0), @max_distance)
    distance - if(behind?, do: 9.0, else: 0.0)
  end

  defp detection_bonus(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    for %Holder{auras: auras, stacks: stacks} <- holders,
        %ThistleTea.Game.Aura{type: :mod_stealth_detect, misc_value: 0, amount: amount} <- auras,
        is_integer(amount),
        reduce: 0 do
      total -> total + amount * max(stacks || 1, 1)
    end
  end

  defp detection_bonus(_entity), do: 0

  defp stalked_by(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    for %Holder{caster_guid: guid} = holder <- holders,
        is_integer(guid),
        Holder.has_aura_type?(holder, :mod_stalked),
        uniq: true,
        do: guid
  end

  defp stalked_by(_entity), do: []

  defp stealth_skill(entity, true, level) do
    max(Aura.flat_amount(entity, :mod_stealth), level * 5) + Aura.flat_amount(entity, :mod_stealth_level)
  end

  defp stealth_skill(_entity, false, _level), do: 0
end
