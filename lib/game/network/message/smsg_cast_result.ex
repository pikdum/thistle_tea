defmodule ThistleTea.Game.Network.Message.SmsgCastResult do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_CAST_RESULT

  alias ThistleTea.Game.Spell

  @simple_spell_cast_result_failure 2

  @cast_failure_reason_requires_spell_focus 0x5E
  @cast_failure_reason_requires_area 0x5D
  @cast_failure_reason_equipped_item_class 0x19

  @cast_failure_reasons %{
    affecting_combat: 0x00,
    already_have_summon: 0x05,
    already_open: 0x06,
    cant_be_disenchanted: 0x0C,
    aura_bounced: 0x07,
    bad_implicit_targets: 0x09,
    bad_targets: 0x0A,
    cant_do_that_yet: 0x12,
    caster_dead: 0x13,
    chest_in_use: 0x15,
    equipped_item: 0x18,
    equipped_item_class: @cast_failure_reason_equipped_item_class,
    confused: 0x16,
    dont_report: 0x17,
    fizzle: 0x1D,
    fleeing: 0x1E,
    food_lowlevel: 0x1F,
    immune: 0x22,
    interrupted: 0x23,
    item_not_ready: 0x28,
    item_gone: 0x26,
    lowlevel: 0x2B,
    line_of_sight: 0x2A,
    low_castlevel: 0x2C,
    target_not_looted: 0x70,
    target_unskinnable: 0x74,
    try_again: 0x7A,
    not_known: 0x38,
    not_on_taxi: 0x3A,
    no_mounts_allowed: 0x4B,
    only_abovewater: 0x50,
    not_behind: 0x33,
    not_infront: 0x36,
    not_here: 0x35,
    not_fishable: 0x34,
    not_ready: 0x3C,
    no_ammo: 0x43,
    no_edible_corpses: 0x86,
    no_charges_remain: 0x44,
    no_dueling: 0x47,
    no_pet: 0x4C,
    not_shapeshift: 0x3D,
    not_tradeable: 0x3F,
    not_trading: 0x40,
    no_power: 0x4D,
    nothing_to_dispel: 0x4E,
    only_shapeshift: 0x56,
    only_stealthed: 0x57,
    out_of_range: 0x59,
    pacified: 0x5A,
    reagents: 0x5C,
    silenced: 0x60,
    stunned: 0x64,
    too_close: 0x76,
    too_many_skills: 0x89,
    training_points: 0x79,
    spell_learned: 0x62,
    requires_area: @cast_failure_reason_requires_area,
    requires_spell_focus: @cast_failure_reason_requires_spell_focus,
    spell_in_progress: 0x61,
    target_aurastate: 0x67,
    target_dueling: 0x68,
    targets_dead: 0x65,
    target_enemy: 0x69,
    target_friendly: 0x6B,
    target_in_combat: 0x6C,
    target_not_dead: 0x6E,
    target_no_pockets: 0x72,
    target_not_in_instance: 0x7F,
    wrong_pet_food: 0x7D
  }

  defstruct [
    :spell,
    :result,
    :reason,
    :required_spell_focus,
    :area,
    :equipped_item_class,
    :equipped_item_subclass_mask,
    :equipped_item_inventory_type_mask
  ]

  def failure(%Spell{} = spell, reason) when is_atom(reason) do
    %{
      failure(spell.id, reason)
      | required_spell_focus: spell.required_focus_id,
        equipped_item_class: spell.equipped_item_class,
        equipped_item_subclass_mask: spell.equipped_item_subclass_mask,
        equipped_item_inventory_type_mask: 0
    }
  end

  def failure(spell_id, reason) when is_integer(spell_id) and is_atom(reason) do
    %__MODULE__{
      spell: spell_id,
      result: @simple_spell_cast_result_failure,
      reason: reason_code(reason)
    }
  end

  def reason_code(reason) when is_atom(reason), do: Map.fetch!(@cast_failure_reasons, reason)

  @impl ServerMessage
  def to_binary(%__MODULE__{
        spell: spell,
        result: result,
        reason: reason,
        required_spell_focus: required_spell_focus,
        area: area,
        equipped_item_class: equipped_item_class,
        equipped_item_subclass_mask: equipped_item_subclass_mask,
        equipped_item_inventory_type_mask: equipped_item_inventory_type_mask
      }) do
    <<spell::little-size(32), result::little-size(8)>> <>
      case result do
        @simple_spell_cast_result_failure ->
          <<reason::little-size(8)>> <>
            case reason do
              @cast_failure_reason_requires_spell_focus ->
                <<required_spell_focus::little-size(32)>>

              @cast_failure_reason_requires_area ->
                <<area::little-size(32)>>

              @cast_failure_reason_equipped_item_class ->
                <<equipped_item_class::little-size(32), equipped_item_subclass_mask::little-size(32),
                  equipped_item_inventory_type_mask::little-size(32)>>

              _ ->
                <<>>
            end

        _ ->
          <<>>
      end
  end
end
