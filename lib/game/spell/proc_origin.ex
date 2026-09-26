defmodule ThistleTea.Game.Spell.ProcOrigin do
  @moduledoc "Classifies casts for vanilla proc chaining without changing ordinary periodic tick eligibility."

  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext

  def classify(%Spell{} = spell, %CastContext{} = context) do
    cond do
      not can_trigger?(spell, context) -> :suppressed
      context.triggered_by_aura? or (context.triggered? and is_integer(context.cast_item_guid)) -> :aura_or_item
      true -> :cast
    end
  end

  def allowed?(_holder_spell, _triggering_spell, %{proc_origin: :suppressed}), do: false

  def allowed?(%Spell{} = holder_spell, %Spell{} = triggering_spell, %{proc_origin: :aura_or_item}) do
    Spell.attribute?(triggering_spell, :not_a_proc) or Spell.attribute?(holder_spell, :can_proc_from_procs)
  end

  def allowed?(%Spell{} = holder_spell, nil, %{proc_origin: :aura_or_item}),
    do: Spell.attribute?(holder_spell, :can_proc_from_procs)

  def allowed?(_holder_spell, _triggering_spell, _context), do: true

  defp can_trigger?(spell, context) do
    ordinary_trigger?(spell, context) or class_exception?(spell)
  end

  defp ordinary_trigger?(spell, context) do
    cond do
      Spell.attribute?(spell, :suppress_caster_procs) and Spell.attribute?(spell, :suppress_target_procs) -> false
      is_integer(context.cast_item_guid) -> Spell.harmful?(spell)
      game_object?(context.caster_guid) -> false
      not context.triggered? -> true
      not context.triggered_by_aura? -> true
      true -> Spell.attribute?(spell, :not_a_proc)
    end
  end

  defp game_object?(guid) when is_integer(guid), do: Guid.entity_type(guid) == :game_object
  defp game_object?(_guid), do: false

  defp class_exception?(%Spell{spell_family: 3} = spell), do: Spell.family_flag?(spell, 3, 0x200080)
  defp class_exception?(%Spell{spell_family: 5} = spell), do: Spell.family_flag?(spell, 5, 0x60)
  defp class_exception?(%Spell{spell_family: 9} = spell), do: Spell.family_flag?(spell, 9, 0x14)
  defp class_exception?(%Spell{spell_family: 6} = spell), do: Spell.family_flag?(spell, 6, 0x02080000)

  defp class_exception?(%Spell{spell_family: 10} = spell) do
    spell.id in [20_424, 25_997] or Spell.family_flag?(spell, 10, 0x200000) or
      (spell.family_flags_0 == 0 and spell.family_flags_1 == 0 and spell.spell_icon == 25)
  end

  defp class_exception?(_spell), do: false
end
