defmodule ThistleTea.Game.World.Loader.TargetAttackPowerDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.TargetAttackPower
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "slaying items load masks and distinct melee and ranged amounts" do
      for {id, mask_types, melee, ranged} <- [
            {11_406, [3], 265, 0},
            {23_930, [6], 81, 81},
            {29_112, [3, 6], 150, 150},
            {17_352, [6], 200, 0}
          ] do
        spell = SpellLoader.load(id)
        entity = %Mob{unit: %Unit{health: 1_000, max_health: 1_000, auras: []}}
        {entity, _events} = Aura.apply_spell(entity, 1, 60, spell, 0)
        snapshot = TargetAttackPower.snapshot(entity)

        for type <- 1..9 do
          target = %{entity | internal: %Internal{creature: %Creature{creature_type: type}}}
          assert TargetAttackPower.bonus(target, snapshot, :melee) == if(type in mask_types, do: melee, else: 0)
          assert TargetAttackPower.bonus(target, snapshot, :ranged) == if(type in mask_types, do: ranged, else: 0)
        end
      end
    end
  end
end
