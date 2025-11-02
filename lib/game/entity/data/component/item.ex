defmodule ThistleTea.Game.Entity.Data.Component.Item do
  use ThistleTea.Game.Entity.UpdateMask,
    owner: {0x0006, 2, :guid},
    contained: {0x0008, 2, :guid},
    creator: {0x000A, 2, :guid},
    gift_creator: {0x000C, 2, :guid},
    stack_count: {0x000E, 1, :int},
    duration: {0x000F, 1, :int},
    spell_charges: {0x0010, 5, :int},
    flags: {0x0015, 1, :int},
    enchantment: {0x0016, 21, :int},
    property_seed: {0x002B, 1, :int},
    random_properties_id: {0x002C, 1, :int},
    item_text_id: {0x002D, 1, :int},
    durability: {0x002E, 1, :int},
    max_durability: {0x002F, 1, :int}
end
