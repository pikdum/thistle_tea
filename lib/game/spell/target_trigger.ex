defmodule ThistleTea.Game.Spell.TargetTrigger do
  @moduledoc """
  Snapshots matching target-trigger auras with a cast and rolls them only after
  its recipient resolves a successful impact. Combo-point chances use that
  cast's points, before the caster consumes them.
  """
  import Bitwise, only: [&&&: 2, |||: 2, <<<: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  @enforce_keys [:spell_id, :aura_spell_id, :chance, :points_per_combo]
  defstruct [:spell_id, :aura_spell_id, :chance, :points_per_combo, :cast_item_guid, caster_only?: false]

  def snapshot(%{unit: %{auras: holders}}, %Spell{} = spell) when is_list(holders) do
    for %Holder{spell: %Spell{spell_family: family}} = holder <- holders,
        family == spell.spell_family,
        %Aura{type: :add_target_trigger, trigger_spell_id: trigger} = aura <- holder.auras,
        is_integer(trigger) and trigger > 0 and trigger != spell.id,
        matches?(aura.class_mask, spell),
        do: candidate(holder, aura)
  end

  def snapshot(_caster, _spell), do: []

  def events(context, target_guid, roll \\ &:rand.uniform/0)

  def events(%CastContext{} = context, target_guid, roll) do
    for %__MODULE__{} = trigger <- context.target_triggers,
        not trigger.caster_only? or target_guid == context.caster_guid,
        roll?(trigger, context.combo_points, roll),
        do:
          Effects.trigger_spell(context.caster_guid, context.caster_level || 1, target_guid, trigger.spell_id,
            cast_item_guid: trigger.cast_item_guid,
            triggered_by_spell_id: trigger.aura_spell_id,
            resolve_targets?: true,
            requires_living_target?: true
          )
  end

  def events(_context, _target_guid, _roll), do: []

  defp candidate(%Holder{} = holder, %Aura{} = aura) do
    effect = Enum.find(holder.spell.effects, &(&1.index == aura.index))

    %__MODULE__{
      spell_id: aura.trigger_spell_id,
      aura_spell_id: holder.spell.id,
      cast_item_guid: holder.cast_item_guid,
      chance: aura.amount || 0,
      caster_only?: Spell.attribute?(holder.spell, :class_trigger_only_on_caster),
      points_per_combo: points_per_combo(effect)
    }
  end

  defp points_per_combo(%Effect{points_per_combo: points}) when is_number(points), do: points
  defp points_per_combo(_effect), do: 0

  defp matches?(mask, %Spell{} = spell) when is_integer(mask) and mask > 0 do
    (mask &&& ((spell.family_flags_0 || 0) ||| (spell.family_flags_1 || 0) <<< 32)) != 0
  end

  defp matches?(_mask, _spell), do: false

  defp roll?(%__MODULE__{} = trigger, points, roll) do
    chance = trigger.chance + trunc(trigger.points_per_combo * max(points || 0, 0))
    chance >= 100 or (chance > 0 and roll.() * 100 <= chance)
  end
end
