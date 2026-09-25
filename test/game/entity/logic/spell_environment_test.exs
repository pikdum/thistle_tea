defmodule ThistleTea.Game.Entity.Logic.SpellEnvironmentTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEnvironment
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:character]

  describe "reconcile/2" do
    test "does not restore outdoor passives on released ghosts", %{character: character, passive: passive} do
      passive = %{passive | stances: 0}

      ghost = %{
        character
        | unit: %{character.unit | health: 1},
          player: %{character.player | flags: 0x10},
          internal: %{character.internal | spellbook: %{passive.id => passive}}
      }

      assert SpellEnvironment.reconcile(ghost, 1000) == ghost
    end

    test "entering indoors dismounts and emits the restored speed without remounting on exit", %{character: character} do
      mount = %Spell{
        id: 458,
        attributes: MapSet.new([:only_outdoors]),
        effects: [
          %Effect{index: 0, type: :apply_aura, aura: :mounted, misc_value: 2404},
          %Effect{index: 1, type: :apply_aura, aura: :mod_increase_mounted_speed, base_points: 60}
        ]
      }

      mounted = apply_spell(character, mount)
      assert mounted.unit.mount_display_id == 2404
      assert_in_delta mounted.movement_block.run_speed, 11.2, 0.00001
      {inside, events} = mounted |> terrain(false) |> SpellEnvironment.reconcile(2000) |> Effects.drain()
      assert inside.unit.mount_display_id == 0
      assert inside.movement_block.run_speed == 7.0
      assert Enum.any?(events, &match?(%Effects.MovementSpeedChanged{speed: 7.0}, &1))
      refute Aura.has_spell?(inside, 458)
      assert SpellEnvironment.reconcile(terrain(inside, true), 3000).unit.mount_display_id == 0
    end

    test "restores learned outdoor passives only in their required form", %{character: character, passive: passive} do
      refute Aura.has_spell?(SpellEnvironment.reconcile(character, 1000), passive.id)
      cat = apply_spell(character, cat_form())
      outside = SpellEnvironment.reconcile(cat, 2000)
      assert Aura.has_spell?(outside, passive.id)
      assert_in_delta outside.movement_block.run_speed, 9.1, 0.00001
      assert SpellEnvironment.reconcile(outside, 3000) == outside

      inside = outside |> terrain(false) |> SpellEnvironment.reconcile(4000)
      assert inside.unit.shapeshift_form == 1
      assert inside.movement_block.run_speed == 7.0
      refute Aura.has_spell?(inside, passive.id)
      outside = inside |> terrain(true) |> SpellEnvironment.reconcile(5000)
      assert_in_delta outside.movement_block.run_speed, 9.1, 0.00001

      {unshifted, _events} = Aura.cancel_spell(outside, 768, 6000)
      unshifted = SpellEnvironment.reconcile(unshifted, 6000)
      assert unshifted.unit.shapeshift_form == 0
      refute Aura.has_spell?(unshifted, passive.id)
      assert unshifted.movement_block.run_speed == 7.0
    end

    test "missing terrain preserves active auras", %{character: character, passive: passive} do
      active = character |> apply_spell(cat_form()) |> SpellEnvironment.reconcile(1000)
      unknown = active |> terrain(nil) |> SpellEnvironment.reconcile(2000)
      assert unknown.unit.auras == active.unit.auras
      assert Aura.has_spell?(unknown, passive.id)
    end

    test "does not restore passives while dead or after unlearning", %{character: character, passive: passive} do
      active = character |> apply_spell(cat_form()) |> SpellEnvironment.reconcile(1000)
      dead = Core.take_damage(active, 1000, 2000)
      {dead, _events} = Aura.remove_spells(dead, [passive.id], 2000)
      dead = SpellEnvironment.reconcile(dead, 2000)
      refute Aura.has_spell?(dead, passive.id)
      {alive, _events} = Death.resurrect(dead, 1.0, 3000)
      alive = alive |> apply_spell(cat_form()) |> SpellEnvironment.reconcile(3000)
      assert Aura.has_spell?(alive, passive.id)

      inside = alive |> terrain(false) |> SpellEnvironment.reconcile(4000)
      unlearned = %{inside | internal: %{inside.internal | spellbook: %{}}}
      refute Aura.has_spell?(SpellEnvironment.reconcile(terrain(unlearned, true), 5000), passive.id)
    end
  end

  defp character(_context) do
    passive = %Spell{
      id: 24_866,
      stances: 1,
      attributes: MapSet.new([:only_outdoors, :passive]),
      effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_increase_speed, base_points: 30}]
    }

    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, level: 60, class: 11, auras: []},
      player: %Player{},
      internal: %Internal{outdoors?: true, spellbook: %{passive.id => passive}},
      movement_block: struct!(%MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}, MovementBlock.player_speeds())
    }

    %{character: character, passive: passive}
  end

  defp cat_form do
    %Spell{id: 768, effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_shapeshift, misc_value: 1}]}
  end

  defp apply_spell(character, spell), do: character |> Aura.apply_spell(1, 60, spell, 1000) |> elem(0)
  defp terrain(character, outdoors), do: %{character | internal: %{character.internal | outdoors?: outdoors}}
end
