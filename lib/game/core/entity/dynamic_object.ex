defmodule ThistleTea.Game.Core.Entity.DynamicObject do
  @moduledoc """
  Dynamic object entity for ground-targeted area spells (e.g. Blizzard),
  built from the caster, spell, and target location.
  """
  import Bitwise, only: [|||: 2]

  alias ThistleTea.Game.Core.Entity.Component.DynamicObject, as: DynamicObjectComponent
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.WorldRef

  @update_flag_all 0x10
  @update_flag_has_position 0x40

  @bytes_area_spell <<0x01, 0x00, 0x00, 0x00>>

  defstruct object: %Object{},
            dynamic_object: %DynamicObjectComponent{},
            movement_block: %MovementBlock{},
            internal: %Internal{}

  def build(caster_guid, world, %Spell{} = spell, {x, y, z}, radius_yards, facing \\ 0.0) do
    %__MODULE__{
      object: %Object{
        guid: next_guid(),
        scale_x: 1.0
      },
      dynamic_object: %DynamicObjectComponent{
        caster: caster_guid,
        bytes: @bytes_area_spell,
        spell_id: spell.id,
        radius: radius_yards * 1.0,
        pos_x: x,
        pos_y: y,
        pos_z: z,
        facing: facing
      },
      movement_block: %MovementBlock{
        update_flag: @update_flag_all ||| @update_flag_has_position,
        position: {x, y, z, facing}
      },
      internal: %Internal{
        world: WorldRef.coerce(world),
        name: spell.name
      }
    }
  end

  defp next_guid do
    Guid.from_low_guid(:dynamic_object, :erlang.unique_integer([:positive, :monotonic]))
  end
end
