defmodule ThistleTea.Game.World.Loader.ElementalCreatureVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackTable

  @moduletag :vmangos_db

  describe "build/1" do
    test "retains the real elemental and physical creature combat schools" do
      for {entry, attack_mask, immune_mask} <- [{575, 4, 4}, {691, 16, 16}, {703, 32, 32}, {92, 1, 8}] do
        template = Mangos.Repo.get!(Mangos.CreatureTemplate, entry)

        creature = %Mangos.Creature{
          guid: entry,
          id: entry,
          modelid: template.model_id1,
          curhealth: 100,
          creature_movement: [],
          equip_items: [nil, nil, nil],
          creature_template: template
        }

        mob = Mob.build(creature)
        assert AttackTable.attacker_context(mob).spell_school_mask == attack_mask
        assert mob.internal.creature.school_immune_mask == immune_mask
        assert Mob.respawn(mob).internal.creature.school_immune_mask == immune_mask
      end
    end
  end
end
