defmodule ThistleTea.Game.World.PresenceTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Position
  alias ThistleTea.Game.World.Position.ClientMotion
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  describe "enter/2" do
    test "publishes health deficits through entry and subsequent owner updates" do
      character = character(WorldRef.open(0), {1.0, 2.0, 3.0, 1.5}, 12)
      character = %{character | unit: %{character.unit | health: 300, max_health: 1_000}}
      on_exit(fn -> Presence.leave(character) end)
      Presence.enter(character, %{})
      assert Metadata.get(character.object.guid).health_deficit == 700
      Presence.sync(%{character | unit: %{character.unit | health: 1_000}}, %{})
      assert Metadata.get(character.object.guid).health_deficit == 0
    end

    test "publishes metadata and position from one character snapshot" do
      character = character(WorldRef.open(0), {1.0, 2.0, 3.0, 1.5}, 12)
      on_exit(fn -> Presence.leave(character) end)

      assert :ok = Presence.enter(character, %{name: "Alice"})

      assert Metadata.query(character.object.guid, [:name, :area, :orientation, :world]) == %{
               name: "Alice",
               area: 12,
               orientation: 1.5
             }

      assert SpatialHash.get_entity(character.object.guid) ==
               {character.object.guid, WorldRef.open(0), 1.0, 2.0, 3.0}
    end

    test "publishes the active farsight viewpoint" do
      character = character(WorldRef.open(0), {1.0, 2.0, 3.0, 1.5}, 12)
      character = %{character | player: %Player{farsight: 4321}}
      on_exit(fn -> Presence.leave(character) end)

      assert :ok = Presence.enter(character, %{})
      assert Metadata.query(character.object.guid, [:viewpoint]) == %{viewpoint: 4321}
    end

    test "player metadata admits Polymorph through validation and target resolution" do
      caster = character(WorldRef.open(0), {1.0, 2.0, 3.0, 0.0}, 12)
      target = character(WorldRef.open(0), {5.0, 2.0, 3.0, 0.0}, 12)
      on_exit(fn -> Presence.leave(target) end)
      Presence.enter(target, %{alive?: true, friendly?: false, hostile?: true, attackable?: true})

      spell = %Spell{
        id: 118,
        mechanic: 17,
        target_creature_type_mask: 0xC1,
        effects: [%Effect{type: :apply_aura, aura: :mod_confuse, implicit_target_a: :target_enemy}]
      }

      info = Map.put(Metadata.get(target.object.guid), :guid, target.object.guid)
      targets = Target.unit(target.object.guid)

      assert :ok = CastValidation.validate(caster, spell, targets, info, 1_000)
      assert SpellTargetResolver.resolve(caster, spell, targets) == [target.object.guid]

      undead_only = %{spell | target_creature_type_mask: 0x20}
      assert {:error, :bad_targets} = CastValidation.validate(caster, undead_only, targets, info, 1_000)
      assert SpellTargetResolver.resolve(caster, undead_only, targets) == []
    end
  end

  describe "sync/2" do
    test "derives creature type from the current form and restores humanoid on removal" do
      character = character(WorldRef.open(0), {1.0, 2.0, 3.0, 0.0}, 12)
      on_exit(fn -> Presence.leave(character) end)
      Presence.enter(character, %{})
      assert Metadata.query(character.object.guid, [:creature_type]) == %{creature_type: 7}

      for form <- [1, 3, 4, 5, 8, 14, 15, 16] do
        shifted = %{character | unit: %{character.unit | shapeshift_form: form}}
        Presence.sync(shifted, %{creature_type: 7})
        assert Metadata.query(character.object.guid, [:creature_type]) == %{creature_type: 1}
      end

      for form <- [0, 2, 17, 18, 19, 28, 30, 31, 32] do
        shifted = %{character | unit: %{character.unit | shapeshift_form: form}}
        Presence.sync(shifted, %{})
        assert Metadata.query(character.object.guid, [:creature_type]) == %{creature_type: 7}
      end
    end
  end

  describe "relocate/2" do
    test "moves spatial and metadata location together while preserving other metadata" do
      character = character(WorldRef.open(0), {1.0, 2.0, 3.0, 1.5}, 12)
      on_exit(fn -> Presence.leave(character) end)
      Presence.enter(character, %{name: "Alice"})

      relocated = character(WorldRef.instance(389, 7), {4.0, 5.0, 6.0, 2.5}, 43, character.object.guid)

      assert :ok = Presence.relocate(relocated, %{moving_until: 900})

      assert Metadata.query(character.object.guid, [:name, :area, :orientation, :moving_until]) == %{
               name: "Alice",
               area: 43,
               orientation: 2.5,
               moving_until: 900
             }

      assert SpatialHash.get_entity(character.object.guid) ==
               {character.object.guid, WorldRef.instance(389, 7), 4.0, 5.0, 6.0}
    end
  end

  describe "relocate_client/5" do
    test "publishes metadata, stationary origin, and bounded motion together" do
      character = character(WorldRef.open(0), {1.0, 2.0, 3.0, 0.0}, 12)
      on_exit(fn -> Presence.leave(character) end)

      assert :ok = Presence.relocate_client(character, %{moving_until: 1_750}, {70.0, 0.0, 0.0}, 1_000, 750)

      assert %ClientMotion{origin: origin, velocity: velocity} = Position.projection(character.object.guid)
      assert origin == {1.0, 2.0, 3.0}
      assert velocity == {70.0, 0.0, 0.0}

      assert Position.get(character.object.guid, 1_100) == {WorldRef.open(0), 8.0, 2.0, 3.0}
    end
  end

  describe "leave/1" do
    test "withdraws metadata and spatial position together" do
      character = character(WorldRef.open(0), {1.0, 2.0, 3.0, 1.5}, 12)
      Presence.enter(character, %{name: "Alice"})

      assert :ok = Presence.leave(character)
      assert Metadata.get(character.object.guid) == nil
      assert SpatialHash.get_entity(character.object.guid) == nil
    end
  end

  defp character(world, position, area, guid \\ nil) do
    %Character{
      object: %Object{guid: guid || Guid.from_low_guid(:player, System.unique_integer([:positive]))},
      unit: %Unit{health: 100, max_health: 100, auras: []},
      internal: %Internal{world: world, area: area},
      movement_block: %MovementBlock{position: position}
    }
  end
end
