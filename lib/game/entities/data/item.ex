defmodule ThistleTea.Game.Entities.Data.Item do
  use ThistleTea.Game.FieldStruct,
    owner: {0x0006, 2, :guid},
    contained: {0x0008, 2, :guid},
    creator: {0x000a, 2, :guid},
    gift_creator: {0x000c, 2, :guid},
    stack_count: {0x000e, 1, :int},
    duration: {0x000f, 1, :int},
    spell_charges: {0x0010, 5, :int},
    flags: {0x0015, 1, :int},
    enchantment: {0x0016, 21, :int},
    property_seed: {0x002b, 1, :int},
    random_properties_id: {0x002c, 1, :int},
    item_text_id: {0x002d, 1, :int},
    durability: {0x002e, 1, :int},
    max_durability: {0x002f, 1, :int}
end