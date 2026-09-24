defmodule ThistleTea.Game.Entity.Data.CreatureArchetype do
  @moduledoc "A loaded creature archetype, independent of spawn identity and live combat state."

  alias ThistleTea.Game.Entity.Data.Mob

  defstruct [:entry, :name, :scale, :unit, :movement, :creature, :loot, :spellbook, :invincibility_health_threshold]

  def from_mob(%Mob{} = mob) do
    %__MODULE__{
      entry: mob.object.entry,
      name: mob.internal.name,
      scale: mob.object.base_scale_x,
      unit: mob.unit,
      movement: mob.movement_block,
      creature: mob.internal.creature,
      loot: mob.internal.loot,
      spellbook: mob.internal.spellbook,
      invincibility_health_threshold: mob.internal.invincibility_health_threshold
    }
  end
end
