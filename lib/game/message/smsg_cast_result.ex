defmodule ThistleTea.Game.Message.SmsgCastResult do
  use ThistleTea.Game.ServerMessage, :SMSG_CAST_RESULT

  @simple_spell_cast_result_failure 2

  @cast_failure_reason_requires_spell_focus 0x5E
  @cast_failure_reason_requires_area 0x5D
  @cast_failure_reason_equipped_item_class 0x19

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
                <<equipped_item_class::little-size(32),
                  equipped_item_subclass_mask::little-size(32),
                  equipped_item_inventory_type_mask::little-size(32)>>

              _ ->
                <<>>
            end

        _ ->
          <<>>
      end
  end
end
