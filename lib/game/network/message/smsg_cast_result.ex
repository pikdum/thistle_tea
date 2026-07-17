defmodule ThistleTea.Game.Network.Message.SmsgCastResult do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_CAST_RESULT

  @simple_spell_cast_result_failure 2

  @cast_failure_reason_requires_spell_focus 0x5E
  @cast_failure_reason_requires_area 0x5D
  @cast_failure_reason_equipped_item_class 0x19

  @cast_failure_reasons %{
    affecting_combat: 0x00,
    already_have_summon: 0x05,
    aura_bounced: 0x07,
    bad_implicit_targets: 0x09,
    bad_targets: 0x0A,
    cant_do_that_yet: 0x12,
    caster_dead: 0x13,
    equipped_item_class: @cast_failure_reason_equipped_item_class,
    fizzle: 0x1D,
    immune: 0x22,
    item_not_ready: 0x28,
    line_of_sight: 0x2A,
    not_known: 0x38,
    not_behind: 0x33,
    not_infront: 0x36,
    not_fishable: 0x34,
    not_ready: 0x3C,
    no_ammo: 0x48,
    not_shapeshift: 0x3D,
    no_power: 0x4D,
    only_shapeshift: 0x56,
    out_of_range: 0x59,
    reagents: 0x5C,
    requires_area: @cast_failure_reason_requires_area,
    requires_spell_focus: @cast_failure_reason_requires_spell_focus,
    spell_in_progress: 0x61,
    target_aurastate: 0x67,
    targets_dead: 0x65,
    target_enemy: 0x69,
    target_friendly: 0x6B,
    target_not_dead: 0x6E
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
