defmodule ThistleTea.Game.Entity.Logic.Regen do
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death

  @tick_ms 2_000
  @five_second_rule_ms 5_000
  @energy_per_tick 20
  @rage_decay_per_tick 20

  @mana_power_type 0
  @rage_power_type 1
  @energy_power_type 3

  @class_warrior 1
  @class_paladin 2
  @class_hunter 3
  @class_rogue 4
  @class_priest 5
  @class_shaman 7
  @class_mage 8
  @class_warlock 9
  @class_druid 11

  def tick_ms, do: @tick_ms

  def tick(entity, now) when is_integer(now) do
    if Death.alive?(entity) do
      entity
      |> regen_health()
      |> regen_power(now)
    else
      entity
    end
  end

  def needs_regen?(%{unit: %Unit{}} = entity) do
    Death.alive?(entity) and
      (missing_health?(entity) or missing_power?(entity))
  end

  def needs_regen?(_entity), do: false

  def under_five_second_rule?(%{internal: %Internal{} = internal}, now) when is_integer(now) do
    case Map.get(internal, :last_mana_use_at) do
      at when is_integer(at) -> now - at < @five_second_rule_ms
      _ -> false
    end
  end

  def under_five_second_rule?(_entity, _now), do: false

  defp missing_health?(%{unit: %Unit{health: health, max_health: max_health}})
       when is_integer(health) and is_integer(max_health) do
    health < max_health
  end

  defp missing_health?(_entity), do: false

  defp missing_power?(%{unit: %Unit{power_type: @mana_power_type, power1: mana, max_power1: max_mana}})
       when is_integer(mana) and is_integer(max_mana) do
    mana < max_mana
  end

  defp missing_power?(%{unit: %Unit{power_type: @rage_power_type, power2: rage}}) when is_integer(rage) do
    rage > 0
  end

  defp missing_power?(%{unit: %Unit{power_type: @energy_power_type, power4: energy, max_power4: max_energy}})
       when is_integer(energy) and is_integer(max_energy) do
    energy < max_energy
  end

  defp missing_power?(_entity), do: false

  defp regen_health(%{internal: %Internal{in_combat: true}} = entity), do: entity

  defp regen_health(%{unit: %Unit{class: class, spirit: spirit}} = entity)
       when is_integer(class) and is_number(spirit) do
    Core.heal(entity, trunc(health_per_tick(class, spirit)))
  end

  defp regen_health(entity), do: entity

  defp regen_power(%{unit: %Unit{power_type: @mana_power_type}} = entity, now), do: regen_mana(entity, now)
  defp regen_power(%{unit: %Unit{power_type: @rage_power_type}} = entity, _now), do: decay_rage(entity)
  defp regen_power(%{unit: %Unit{power_type: @energy_power_type}} = entity, _now), do: regen_energy(entity)
  defp regen_power(entity, _now), do: entity

  defp regen_mana(%{unit: %Unit{class: class, spirit: spirit}} = entity, now)
       when is_integer(class) and is_number(spirit) do
    if under_five_second_rule?(entity, now) do
      entity
    else
      Core.restore_mana(entity, trunc(mana_per_tick(class, spirit)))
    end
  end

  defp regen_mana(entity, _now), do: entity

  defp decay_rage(%{internal: %Internal{in_combat: true}} = entity), do: entity

  defp decay_rage(%{unit: %Unit{power2: rage} = unit} = entity) when is_integer(rage) and rage > 0 do
    %{entity | unit: %{unit | power2: max(rage - @rage_decay_per_tick, 0)}}
    |> Core.mark_broadcast_update()
  end

  defp decay_rage(entity), do: entity

  defp regen_energy(%{unit: %Unit{power4: energy, max_power4: max_energy} = unit} = entity)
       when is_integer(energy) and is_integer(max_energy) and max_energy > 0 and energy < max_energy do
    %{entity | unit: %{unit | power4: min(energy + @energy_per_tick, max_energy)}}
    |> Core.mark_broadcast_update()
  end

  defp regen_energy(entity), do: entity

  defp health_per_tick(@class_warrior, spirit), do: spirit * 1.26 - 22.6
  defp health_per_tick(@class_paladin, spirit), do: spirit * 0.25
  defp health_per_tick(@class_hunter, spirit), do: spirit * 0.43 - 5.5
  defp health_per_tick(@class_rogue, spirit), do: spirit * 0.84 - 13
  defp health_per_tick(@class_priest, spirit), do: spirit * 0.15 + 1.4
  defp health_per_tick(@class_shaman, spirit), do: spirit * 0.28 - 3.6
  defp health_per_tick(@class_mage, spirit), do: spirit * 0.11 + 1
  defp health_per_tick(@class_warlock, spirit), do: spirit * 0.12 + 1.5
  defp health_per_tick(@class_druid, spirit), do: spirit * 0.11 + 1
  defp health_per_tick(_class, _spirit), do: 0

  defp mana_per_tick(@class_mage, spirit), do: spirit / 4 + 12.5
  defp mana_per_tick(@class_priest, spirit), do: spirit / 4 + 12.5
  defp mana_per_tick(@class_shaman, spirit), do: spirit / 5 + 17
  defp mana_per_tick(@class_paladin, spirit), do: spirit / 5 + 15
  defp mana_per_tick(@class_hunter, spirit), do: spirit / 5 + 15
  defp mana_per_tick(@class_warlock, spirit), do: spirit / 5 + 15
  defp mana_per_tick(@class_druid, spirit), do: spirit / 5 + 15
  defp mana_per_tick(_class, _spirit), do: 0
end
