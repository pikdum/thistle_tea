defmodule ThistleTea.Game.Entity.Logic.AI.BT.CreaturePetTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.CreaturePet
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.WorldRef

  setup [:pet]

  describe "lifetime/3" do
    test "living owners retain their single pet at the visibility boundary", %{pet: pet} do
      assert {:failure, ^pet, _} = tick(pet, %{owner() | distance: 120.0})
    end

    test "owner death retains fighting pets and corpses but removes idle pets", %{pet: pet} do
      owner = %{owner() | metadata: %{alive?: false, pet_guid: 2}}
      fighting = %{pet | internal: %{pet.internal | in_combat: true}}
      corpse = %{pet | unit: %{pet.unit | health: 0}}
      assert {:failure, ^fighting, _} = tick(fighting, owner)
      assert {:failure, ^corpse, _} = tick(corpse, owner)
      assert {:success, removed, _} = tick(pet, owner)
      assert [%Effects.DespawnSelf{}] = removed.internal.events
    end

    test "missing distant other-world and replaced owners remove combatants", %{pet: pet} do
      fighting = %{pet | internal: %{pet.internal | in_combat: true}}

      for observation <- [
            nil,
            %{owner() | distance: 120.1},
            %{owner() | position: {WorldRef.open(1), 0.0, 0.0, 0.0}},
            %{owner() | metadata: %{alive?: true, pet_guid: 3}}
          ] do
        assert {:success, removed, _} = tick(fighting, observation)
        assert [%Effects.DespawnSelf{}] = removed.internal.events
      end
    end
  end

  defp pet(_context) do
    %{
      pet: %Mob{
        object: %Object{guid: 2},
        unit: %Unit{health: 100},
        internal: %Internal{world: WorldRef.open(0), pet: %Pet{owner_guid: 1, kind: :creature_pet}}
      }
    }
  end

  defp owner do
    %Observation{
      guid: 1,
      position: {WorldRef.open(0), 0.0, 0.0, 0.0},
      distance: 2.0,
      metadata: %{alive?: true, pet_guid: 2}
    }
  end

  defp tick(pet, owner) do
    entities = if owner, do: %{1 => owner}, else: %{}
    context = Context.new(1000, perception: Perception.new(1000, nil, entities, %{}))
    CreaturePet.lifetime(pet, %Blackboard{}, context)
  end
end
