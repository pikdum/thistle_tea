defmodule ThistleTea.Game.Entity.Logic.Regen do
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death

  @tick_ms 2_000
  @creature_tick_ms 5_000
  @regen_flag_health 0x1
  @regen_flag_power 0x2
  @five_second_rule_ms 5_000
  @energy_per_tick 20
  @rage_decay_per_tick 20
  @sitting_multiplier 1.5

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

  def tick_ms(%Mob{}), do: @creature_tick_ms
  def tick_ms(_entity), do: @tick_ms

  def tick(%Mob{} = entity, now) when is_integer(now) do
    if Death.alive?(entity) do
      entity
      |> creature_regen_health()
      |> creature_regen_mana()
    else
      entity
    end
  end

  def tick(entity, now) when is_integer(now) do
    if Death.alive?(entity) do
      entity
      |> regen_health()
      |> regen_power(now)
    else
      entity
    end
  end

  def needs_regen?(%Mob{} = entity) do
    Death.alive?(entity) and not in_combat?(entity) and
      ((missing_health?(entity) and creature_regenerates?(entity, @regen_flag_health)) or
         (creature_missing_mana?(entity) and creature_regenerates?(entity, @regen_flag_power)))
  end

  def needs_regen?(%{unit: %Unit{}} = entity) do
    Death.alive?(entity) and
      (missing_health?(entity) or missing_power?(entity))
  end

  def needs_regen?(_entity), do: false

  defp creature_regen_health(%{internal: %Internal{in_combat: true}} = entity), do: entity

  defp creature_regen_health(%{unit: %Unit{health: health, max_health: max_health}} = entity)
       when is_integer(health) and is_integer(max_health) and health < max_health do
    if creature_regenerates?(entity, @regen_flag_health) do
      Core.heal(entity, max(div(max_health, 3), 1))
    else
      entity
    end
  end

  defp creature_regen_health(entity), do: entity

  defp creature_regen_mana(%{internal: %Internal{in_combat: true}} = entity), do: entity

  defp creature_regen_mana(%{unit: %Unit{power1: mana, max_power1: max_mana}} = entity)
       when is_integer(mana) and is_integer(max_mana) and max_mana > 0 and mana < max_mana do
    if creature_regenerates?(entity, @regen_flag_power) do
      Core.restore_mana(entity, max(div(max_mana, 3), 1))
    else
      entity
    end
  end

  defp creature_regen_mana(entity), do: entity

  defp creature_missing_mana?(%{unit: %Unit{power1: mana, max_power1: max_mana}})
       when is_integer(mana) and is_integer(max_mana) and max_mana > 0 do
    mana < max_mana
  end

  defp creature_missing_mana?(_entity), do: false

  defp creature_regenerates?(%{internal: %Internal{} = internal}, flag) do
    case Map.get(internal, :regenerate_stats) do
      stats when is_integer(stats) -> (stats &&& flag) != 0
      _ -> true
    end
  end

  defp creature_regenerates?(_entity, _flag), do: true

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

  defp regen_health(%{unit: %Unit{health: health, max_health: max_health}} = entity)
       when is_integer(health) and is_integer(max_health) and health >= max_health do
    entity
  end

  defp regen_health(%{unit: %Unit{class: class, spirit: spirit}} = entity)
       when is_integer(class) and is_number(spirit) do
    value = spirit_health_portion(entity, class, spirit) + food_health_per_tick(entity) + flat_combat_health(entity)
    apply_health_regen(entity, value)
  end

  defp regen_health(entity), do: entity

  defp spirit_health_portion(entity, class, spirit) do
    base = health_per_tick(class, spirit)

    portion =
      cond do
        not in_combat?(entity) -> base * multiplier(entity, :mod_health_regen_percent)
        AuraLogic.has_aura?(entity, :mod_regen_during_combat) -> base * total(entity, :mod_regen_during_combat) / 100
        true -> 0.0
      end

    if standing?(entity), do: portion, else: portion * @sitting_multiplier
  end

  defp food_health_per_tick(entity) do
    if in_combat?(entity) do
      0.0
    else
      entity
      |> AuraLogic.auras_of_type(:mod_regen)
      |> Enum.reduce(0.0, fn
        %Aura{amount: amount, amplitude_ms: amplitude_ms}, acc
        when is_integer(amount) and is_integer(amplitude_ms) and amplitude_ms > 0 ->
          acc + amount * @tick_ms / amplitude_ms

        _aura, acc ->
          acc
      end)
    end
  end

  defp flat_combat_health(entity) do
    2 * total(entity, :mod_health_regen_in_combat) / 5
  end

  defp apply_health_regen(%{internal: %Internal{} = internal} = entity, value) do
    carried = value + (Map.get(internal, :health_regen_carry) || 0.0)
    carry = carried - trunc(carried)
    entity = %{entity | internal: Map.put(internal, :health_regen_carry, carry)}
    Core.heal(entity, max(trunc(carried), 0))
  end

  defp regen_power(%{unit: %Unit{power_type: @mana_power_type}} = entity, now), do: regen_mana(entity, now)
  defp regen_power(%{unit: %Unit{power_type: @rage_power_type}} = entity, _now), do: decay_rage(entity)
  defp regen_power(%{unit: %Unit{power_type: @energy_power_type}} = entity, _now), do: regen_energy(entity)
  defp regen_power(entity, _now), do: entity

  defp regen_mana(%{unit: %Unit{class: class, spirit: spirit}} = entity, now)
       when is_integer(class) and is_number(spirit) do
    mp5_per_tick = total_by_misc(entity, :mod_power_regen, @mana_power_type) / 5 * 2

    spirit_regen =
      mana_per_tick(class, spirit) * multiplier_by_misc(entity, :mod_power_regen_percent, @mana_power_type)

    spirit_regen =
      if under_five_second_rule?(entity, now) do
        spirit_regen * min(total(entity, :mod_mana_regen_interrupt), 100) / 100
      else
        spirit_regen
      end

    Core.restore_mana(entity, trunc(mp5_per_tick + spirit_regen))
  end

  defp regen_mana(entity, _now), do: entity

  defp decay_rage(%{internal: %Internal{in_combat: true}} = entity), do: entity

  defp decay_rage(%{unit: %Unit{power2: rage} = unit} = entity) when is_integer(rage) and rage > 0 do
    if AuraLogic.has_aura?(entity, :interrupt_regen) do
      entity
    else
      decay = trunc(@rage_decay_per_tick * multiplier_by_misc(entity, :mod_power_regen_percent, @rage_power_type))

      %{entity | unit: %{unit | power2: max(rage - decay, 0)}}
      |> Core.mark_broadcast_update()
    end
  end

  defp decay_rage(entity), do: entity

  defp regen_energy(%{unit: %Unit{power4: energy, max_power4: max_energy} = unit} = entity)
       when is_integer(energy) and is_integer(max_energy) and max_energy > 0 and energy < max_energy do
    gain = trunc(@energy_per_tick * multiplier_by_misc(entity, :mod_power_regen_percent, @energy_power_type))

    %{entity | unit: %{unit | power4: min(energy + gain, max_energy)}}
    |> Core.mark_broadcast_update()
  end

  defp regen_energy(entity), do: entity

  defp in_combat?(%{internal: %Internal{in_combat: true}}), do: true
  defp in_combat?(_entity), do: false

  defp standing?(%{unit: %Unit{stand_state: stand_state}}) when is_integer(stand_state) and stand_state != 0 do
    false
  end

  defp standing?(_entity), do: true

  defp total(entity, type) do
    entity
    |> AuraLogic.auras_of_type(type)
    |> Enum.reduce(0, &add_amount/2)
  end

  defp total_by_misc(entity, type, misc) do
    entity
    |> AuraLogic.auras_of_type(type)
    |> Enum.filter(&(&1.misc_value == misc))
    |> Enum.reduce(0, &add_amount/2)
  end

  defp add_amount(%Aura{amount: amount}, acc) when is_integer(amount), do: acc + amount
  defp add_amount(_aura, acc), do: acc

  defp multiplier(entity, type) do
    entity
    |> AuraLogic.auras_of_type(type)
    |> product()
  end

  defp multiplier_by_misc(entity, type, misc) do
    entity
    |> AuraLogic.auras_of_type(type)
    |> Enum.filter(&(&1.misc_value == misc))
    |> product()
  end

  defp product(auras) do
    Enum.reduce(auras, 1.0, fn
      %Aura{amount: amount}, acc when is_integer(amount) -> acc * (100 + amount) / 100
      _aura, acc -> acc
    end)
  end

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
