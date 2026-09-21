defmodule ThistleTea.Game.Spell.Focus do
  @moduledoc """
  A nearby spell focus and the pure rules for its required identity and range.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Spell

  @object_radius 0.388999998569489

  defstruct [:guid, :id, :position]

  def required?(%Spell{required_focus_id: id} = spell),
    do: is_integer(id) and id > 0 and not Spell.attribute?(spell, :passive)

  def required?(%Character{}, %Spell{} = spell), do: required?(spell)
  def required?(_caster, _spell), do: false

  def validate(_caster, %Spell{required_focus_id: id}, %__MODULE__{id: id}), do: :ok

  def validate(caster, %Spell{} = spell, _focus) do
    if required?(caster, spell), do: {:error, :requires_spell_focus}, else: :ok
  end

  def definition(%GameObjectTemplate{type: 8, data: [id, radius | _]})
      when is_integer(id) and id > 0 and is_number(radius) and radius >= 0, do: {id, radius}

  def definition(_template), do: nil

  def range(radius, caster_radius) when is_number(radius) do
    caster_radius = if is_number(caster_radius) and caster_radius >= 0, do: caster_radius, else: @object_radius
    radius + caster_radius + @object_radius
  end
end
