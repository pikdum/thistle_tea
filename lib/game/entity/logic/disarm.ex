defmodule ThistleTea.Game.Entity.Logic.Disarm do
  @moduledoc """
  Main-hand availability under disarm. Feral attacks use the form's natural
  weapons; off-hand and ranged weapons are unaffected by vanilla disarm.
  """
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Spell

  def active?(%{unit: %Unit{} = unit}), do: active?(unit)

  def active?(%Unit{auras: holders}) when is_list(holders),
    do: Enum.any?(holders, &Holder.has_aura_type?(&1, :mod_disarm))

  def active?(_entity), do: false

  def unarmed?(%{unit: %Unit{} = unit}), do: unarmed?(unit)
  def unarmed?(%Unit{class: 11, shapeshift_form: form}) when form in [1, 5, 8], do: false
  def unarmed?(%Unit{} = unit), do: active?(unit)
  def unarmed?(_entity), do: false

  def armed_creature?(%Mob{unit: %Unit{virtual_item_info: <<2, _rest::binary>>}}), do: true
  def armed_creature?(_entity), do: false

  def damage_multiplier(%Mob{} = entity) do
    if armed_creature?(entity) and unarmed?(entity), do: 0.4, else: 1.0
  end

  def damage_multiplier(_entity), do: 1.0

  def parry_disabled?(%Character{unit: %Unit{base_offhand_max_damage: offhand}} = entity) do
    unarmed?(entity) and not (is_number(offhand) and offhand > 0)
  end

  def parry_disabled?(_entity), do: false

  def validate(%Character{} = entity, %Spell{equipped_item_class: 2} = spell) do
    if active?(entity) and not ranged_weapon?(spell), do: {:error, :equipped_item}, else: :ok
  end

  defp ranged_weapon?(%Spell{equipped_item_subclass_mask: mask} = spell) do
    Spell.ranged_ability?(spell) or
      (is_integer(mask) and mask > 0 and Bitwise.band(mask, Bitwise.bnot(0xD000C)) == 0)
  end

  def validate(%Mob{} = entity, %Spell{effects: effects}) do
    weapon_attack? = Enum.any?(effects, &(&1.type in [:weapon_damage, :weapon_damage_noschool]))

    if armed_creature?(entity) and active?(entity) and weapon_attack?,
      do: {:error, :equipped_item},
      else: :ok
  end

  def validate(_entity, _spell), do: :ok
end
