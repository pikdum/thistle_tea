defmodule ThistleTea.Game.Entity.Logic.Paladin do
  @moduledoc """
  Pure Paladin-specific transitions that raw spell data cannot express.
  """
  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Scripts

  @righteousness_damage_spells %{
    20_154 => 25_742,
    21_084 => 25_742,
    20_287 => 25_740,
    20_288 => 25_739,
    20_289 => 25_738,
    20_290 => 25_737,
    20_291 => 25_736,
    20_292 => 25_735,
    20_293 => 25_713
  }
  @spell_family 10
  @blessing_of_light_family_mask 0x10000000
  @holy_light_family_mask 0x80000000
  @flash_of_light_family_mask 0x40000000
  @seal_of_command_family_mask 0x02000000

  def release_seal(
        %{object: %{guid: caster_guid}, unit: %Unit{auras: holders}} = entity,
        %Spell{} = spell,
        target_guid,
        now
      )
      when is_list(holders) and is_integer(target_guid) and is_integer(now) do
    if Scripts.paladin_judgement?(spell) do
      do_release_seal(entity, holders, caster_guid, target_guid, now)
    else
      entity
    end
  end

  def release_seal(entity, _spell, _target_guid, _now), do: entity

  defp do_release_seal(entity, holders, caster_guid, target_guid, now) do
    case Enum.find(holders, &seal?/1) do
      %Holder{spell: %Spell{id: seal_id}, auras: auras} ->
        case judgement_spell_id(auras) do
          judgement_id when is_integer(judgement_id) and judgement_id > 1 ->
            {entity, aura_events} = AuraLogic.remove_spells(entity, [seal_id], now)
            level = entity.unit.level || 1

            entity
            |> Event.enqueue(aura_events)
            |> Event.enqueue(Event.trigger_spell(caster_guid, level, target_guid, judgement_id))

          _no_judgement ->
            entity
        end

      _no_seal ->
        entity
    end
  end

  def trigger_seal(entity, %{outcome: outcome, victim_guid: victim_guid}) when outcome in [:normal, :crit] do
    case active_seal(entity) do
      %Holder{spell: %Spell{id: seal_id}, auras: auras} = holder ->
        case Map.get(@righteousness_damage_spells, seal_id) do
          spell_id when is_integer(spell_id) -> trigger_righteousness(entity, holder, victim_guid, spell_id)
          _other_seal -> trigger_proc_aura(entity, holder, auras, victim_guid)
        end

      _no_seal ->
        entity
    end
  end

  def trigger_seal(entity, _payload), do: entity

  def active_seal?(entity), do: not is_nil(active_seal(entity))

  def blessing_of_light_bonus(%{unit: %Unit{auras: holders}}, %Spell{} = spell) when is_list(holders) do
    aura_index = healing_bonus_index(spell)

    Enum.find_value(holders, 0, fn
      %Holder{spell: %Spell{} = blessing, auras: auras} when is_integer(aura_index) ->
        blessing_of_light_bonus(blessing, auras, aura_index)

      _holder ->
        nil
    end)
  end

  def blessing_of_light_bonus(_entity, _spell), do: 0

  defp blessing_of_light_bonus(blessing, auras, aura_index) do
    if Spell.family_flag?(blessing, @spell_family, @blessing_of_light_family_mask) do
      case Enum.find(auras, &match?(%Aura{index: ^aura_index, type: :dummy}, &1)) do
        %Aura{amount: amount} when is_integer(amount) -> amount
        _ -> nil
      end
    end
  end

  defp healing_bonus_index(spell) do
    cond do
      Spell.family_flag?(spell, @spell_family, @holy_light_family_mask) -> 0
      Spell.family_flag?(spell, @spell_family, @flash_of_light_family_mask) -> 1
      true -> nil
    end
  end

  defp seal?(%Holder{spell: %Spell{exclusive_category: :paladin_seal}}), do: true
  defp seal?(_holder), do: false

  defp judgement_spell_id(auras) do
    Enum.find_value(auras, fn
      %Aura{index: 2, type: :dummy, amount: amount} when is_integer(amount) -> amount
      _aura -> nil
    end)
  end

  defp active_seal(%{unit: %Unit{auras: holders}}) when is_list(holders), do: Enum.find(holders, &seal?/1)
  defp active_seal(_entity), do: nil

  defp trigger_righteousness(entity, %Holder{auras: auras}, victim_guid, spell_id) do
    case Enum.find(auras, &match?(%Aura{index: 0}, &1)) do
      %Aura{amount: amount} when is_integer(amount) ->
        speed = max((entity.unit.base_attack_time || 2_000) / 1_000, 1.5)
        damage = trunc(amount / 87 + (amount / 25 - amount / 87) * ((min(speed, 4.0) - 1.5) / 2.5))

        spell = %Spell{
          id: spell_id,
          name: "Seal of Righteousness",
          school: :holy,
          effects: [
            %Effect{index: 0, type: :school_damage, base_points: max(damage, 0), implicit_target_a: :target_enemy}
          ]
        }

        context = CastContext.from_caster(entity, spell, victim_guid)
        Event.enqueue(entity, Event.deliver_spell(victim_guid, context, spell))

      _no_damage_aura ->
        entity
    end
  end

  defp trigger_proc_aura(entity, %Holder{} = holder, auras, victim_guid) do
    case Enum.find(auras, &match?(%Aura{type: :proc_trigger_spell, trigger_spell_id: id} when is_integer(id), &1)) do
      %Aura{trigger_spell_id: spell_id} ->
        maybe_trigger_proc(entity, holder.spell, victim_guid, spell_id)

      _no_proc ->
        entity
    end
  end

  defp maybe_trigger_proc(entity, spell, victim_guid, spell_id) do
    if seal_proc?(entity, spell) do
      Event.enqueue(entity, Event.trigger_spell(entity.object.guid, entity.unit.level || 1, victim_guid, spell_id))
    else
      entity
    end
  end

  defp seal_proc?(entity, %Spell{} = spell) do
    if Spell.family_flag?(spell, @spell_family, @seal_of_command_family_mask) do
      :rand.uniform() <= min((entity.unit.base_attack_time || 2_000) * 7 / 60_000, 1.0)
    else
      true
    end
  end

  defp seal_proc?(_entity, _spell), do: true
end
