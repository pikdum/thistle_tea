defmodule ThistleTea.Game.Entity.Logic.InvisibilityTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Invisibility
  alias ThistleTea.Game.Entity.Logic.StealthDetection
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:character]

  describe "detectable?/2" do
    test "requires sufficient detection in a matching type" do
      target = %{invisibility: %{0 => 200}}
      refute Invisibility.detectable?(%{}, target)
      refute Invisibility.detectable?(%{invisibility_detection: %{0 => 100, 1 => 1000}}, target)
      assert Invisibility.detectable?(%{invisibility_detection: %{0 => 200}}, target)
      assert Invisibility.detectable?(%{invisibility: %{0 => 1}}, target)
      assert Invisibility.detectable?(%{}, %{})
    end

    test "detecting any invisibility type suffices" do
      assert Invisibility.detectable?(%{invisibility_detection: %{1 => 1000}}, %{invisibility: %{0 => 200, 1 => 1000}})
    end

    test "collision range does not reveal invisibility" do
      refute StealthDetection.detectable?(%{level: 60}, %{invisibility: %{0 => 200}}, 0.1, 1000)
    end

    test "world bosses detect all types" do
      boss = %Mob{internal: %Internal{creature: %Creature{rank: 3}}}
      assert Invisibility.detectable?(Invisibility.metadata(boss), %{invisibility: %{0 => 10_000}})
    end

    test "drunkenness reveals drunk-only targets", %{character: character} do
      drunk = %{character | player: %{character.player | drunk_value: 512}}
      assert Invisibility.detectable?(Invisibility.metadata(drunk), %{invisibility: %{6 => 512}})
      refute Invisibility.detectable?(Invisibility.metadata(character), %{invisibility: %{6 => 512}})
    end
  end

  describe "metadata/1" do
    test "keeps the strongest level and restores weaker detection on removal", %{character: character} do
      weak = buff(1, :mod_invisibility_detect, 100)
      strong = buff(2, :mod_invisibility_detect, 200)
      character = character |> apply_spell(weak) |> apply_spell(strong)
      assert Invisibility.metadata(character).invisibility_detection[0] == 200
      {character, _} = Aura.cancel_spell(character, 2, 2000)
      assert Invisibility.metadata(character).invisibility_detection[0] == 100
    end
  end

  describe "apply_spell/5" do
    test "projects glow and restores it on expiry and death", %{character: character} do
      spell = %{buff(1, :mod_invisibility, 200) | duration_ms: 1000}
      hidden = apply_spell(character, spell)
      assert hidden.player.field_bytes2_flags == 0x40
      assert Invisibility.metadata(hidden).invisibility == %{0 => 200}
      {visible, _} = Aura.expire_due(hidden, 2000)
      assert visible.player.field_bytes2_flags == 0
      assert Invisibility.metadata(visible).invisibility == %{}
      dead = Core.take_damage(hidden, 100, 1500)
      assert dead.player.field_bytes2_flags == 0
      assert Invisibility.metadata(dead).invisibility == %{}
    end

    test "preserves stealth and unrelated flags on cancellation", %{character: character} do
      character = %{character | player: %{character.player | field_bytes2_flags: 0x01}}
      character = character |> apply_spell(buff(2, :mod_stealth, 5)) |> apply_spell(buff(1, :mod_invisibility, 200))
      assert character.player.field_bytes2_flags == 0x61
      {character, _} = Aura.cancel_spell(character, 1, 2000)
      assert character.player.field_bytes2_flags == 0x21
    end

    test "interrupts incompatible auras and breaks on casting", %{character: character} do
      incompatible = %{buff(2, :dummy, 1) | aura_interrupt_flags: 0x100000}
      invisible = %{buff(1, :mod_invisibility, 200) | aura_interrupt_flags: 1}
      character = character |> apply_spell(incompatible) |> apply_spell(invisible)
      refute Aura.has_spell?(character, 2)
      {character, _} = Aura.remove_with_interrupt_flags(character, Aura.interrupt_mask(:cast), 2000)
      assert Invisibility.metadata(character).invisibility == %{}
    end
  end

  defp character(_context) do
    %{
      character: %Character{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100, level: 60, auras: []},
        player: %Player{},
        internal: %Internal{},
        movement_block: struct!(%MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}, MovementBlock.player_speeds())
      }
    }
  end

  defp apply_spell(character, spell), do: character |> Aura.apply_spell(1, 60, spell, 1000) |> elem(0)

  defp buff(id, type, amount) do
    %Spell{id: id, effects: [%Effect{index: 0, type: :apply_aura, aura: type, base_points: amount, misc_value: 0}]}
  end
end
