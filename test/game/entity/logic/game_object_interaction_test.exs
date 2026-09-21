defmodule ThistleTea.Game.Entity.Logic.GameObjectInteractionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.GameObjectInteraction
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  describe "prepare_questgiver_use/4" do
    test "removes only auras interrupted by object interaction" do
      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100},
        player: %Player{},
        internal: %Internal{},
        movement_block: %MovementBlock{}
      }

      spell = %Spell{id: 1, aura_interrupt_flags: 0x800, effects: [%Effect{index: 0, type: :apply_aura, aura: :dummy}]}
      {character, _effects} = Aura.apply_spell(character, 1, 60, spell, 1000)
      {character, _effects} = Aura.apply_spell(character, 1, 60, %{spell | id: 2, aura_interrupt_flags: 0}, 1000)

      assert {:ok, character} =
               GameObjectInteraction.prepare_questgiver_use(character, %GameObjectTemplate{type: 2}, 0, 2000)

      refute Aura.has_spell?(character, 1)
      assert Aura.has_spell?(character, 2)
    end

    test "honors immunity restrictions and no-interaction flags before mutation" do
      character = %Character{unit: %Unit{flags: 0x80000000}}
      restricted = %GameObjectTemplate{type: 2, data: [0, 0, 0, 0, 0, 1]}
      assert {:error, :immune} = GameObjectInteraction.prepare_questgiver_use(character, restricted, 0, 0)
      assert {:error, :not_interactable} = GameObjectInteraction.prepare_questgiver_use(character, restricted, 0x10, 0)
    end
  end

  describe "rotation/2" do
    test "uses facing when the stored z and w rotation fields are empty" do
      {x, y, z, w} = GameObjectInteraction.rotation({0.0, 0.0, 0.0, 0.0}, :math.pi())
      assert x == 0.0 and y == 0.0
      assert_in_delta z, 1.0, 0.00001
      assert_in_delta w, 0.0, 0.00001
      assert GameObjectInteraction.rotation({0.0, 0.0, 0.5, 0.5}, 0.0) == {0.0, 0.0, 0.5, 0.5}
    end
  end

  describe "within?/6" do
    test "uses three-dimensional origin distance without display bounds" do
      assert within?({3.0, 4.0, 0.0}, nil)
      refute within?({3.0, 4.0, 0.1}, nil)
      refute within?({0.0, 0.0, 5.1}, nil)
    end

    test "expands scaled bounds by an unscaled interaction radius" do
      bounds = {{-2.0, -1.0, 0.0}, {4.0, 1.0, 3.0}}
      assert within?({13.0, 0.0, 0.0}, bounds, 2.0)
      refute within?({13.1, 0.0, 0.0}, bounds, 2.0)
      assert within?({0.0, 0.0, 11.0}, bounds, 2.0)
      refute within?({0.0, 0.0, 11.1}, bounds, 2.0)
    end

    test "rotates asymmetric bounds around all three axes" do
      bounds = {{-1.0, -1.0, -1.0}, {10.0, 1.0, 1.0}}
      half = :math.sqrt(0.5)
      assert within?({0.0, 14.0, 0.0}, bounds, 1.0, {0.0, 0.0, half, half})
      refute within?({14.0, 0.0, 0.0}, bounds, 1.0, {0.0, 0.0, half, half})
      assert within?({0.0, 0.0, -14.0}, bounds, 1.0, {0.0, half, 0.0, half})
      refute within?({0.0, 0.0, 14.0}, bounds, 1.0, {0.0, half, 0.0, half})
    end

    test "translates the origin and tolerates an empty quaternion or degenerate bounds" do
      assert GameObjectInteraction.within?({12, 20, 30}, {10, 20, 30}, {0, 0, 0, 0}, 1, nil, 2)
      assert within?({5.0, 0.0, 0.0}, {{0, 0, 0}, {0, 0, 0}})
      refute within?({5.1, 0.0, 0.0}, {{0, 0, 0}, {0, 0, 0}})
      assert within?({14.0, 0.0, 0.0}, {{0, 0, 0}, {10, 0, 0}})
    end
  end

  defp within?(position, bounds, scale \\ 1.0, rotation \\ {0.0, 0.0, 0.0, 1.0}) do
    GameObjectInteraction.within?(position, {0.0, 0.0, 0.0}, rotation, scale, bounds, 5.0)
  end
end
