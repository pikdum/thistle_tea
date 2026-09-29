defmodule ThistleTea.Game.Core.Spell.CastingImmunityTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Casting
  alias ThistleTea.Game.Core.Spell.Cooldowns
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef

  setup [:caster]

  describe "complete/2" do
    test "rechecks school lockouts before paying costs or launching", %{caster: caster} do
      spell = %Spell{
        id: 900_863,
        cast_time_ms: 1_000,
        school: :holy,
        prevention_type: 1,
        mana_cost: 30,
        power_type: 0,
        effects: [%Effect{index: 0, type: :heal, implicit_target_a: :caster, base_points: 10}]
      }

      finished =
        caster
        |> Casting.start(spell, Target.self(caster.object.guid), 1_000)
        |> Cooldowns.lock_schools(Spell.school_mask(:holy), 5_000, 1_500)
        |> Casting.complete(2_000)

      assert finished.internal.casting == nil
      assert finished.unit.power1 == 100
      assert finished.unit.health == 50
      assert Enum.any?(finished.internal.events, &match?(%Effects.SpellCastFailed{reason: :silenced}, &1))
      refute Enum.any?(finished.internal.events, &is_struct(&1, Effects.SpellGo))
    end

    test "school immunity escapes control and a self stun does not interrupt its own completed cast", %{caster: caster} do
      stun = %Spell{
        id: 900_864,
        school: :physical,
        duration_ms: 5_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stun, implicit_target_a: :target_enemy}]
      }

      {caster, _} = Aura.apply_spell(caster, 10, 10, stun, 0)
      assert caster.internal.rooted?

      ice = %Spell{
        id: 900_865,
        school: :frost,
        prevention_type: 1,
        duration_ms: 1_000,
        attributes: MapSet.new([:immunity_purges_effect]),
        effects: [
          %Effect{index: 0, type: :apply_aura, aura: :mod_stun, implicit_target_a: :caster},
          %Effect{index: 1, type: :apply_aura, aura: :school_immunity, misc_value: 1, implicit_target_a: :caster},
          %Effect{index: 2, type: :apply_aura, aura: :school_immunity, misc_value: 126, implicit_target_a: :caster}
        ]
      }

      finished = caster |> Casting.start(ice, Target.self(caster.object.guid), 100) |> Casting.complete(100)
      assert finished.internal.casting == nil
      refute Aura.has_spell?(finished, stun.id)
      assert Aura.has_spell?(finished, ice.id)
      assert finished.internal.rooted?
      assert Bitwise.band(finished.unit.flags, 0x80000000) != 0
      assert Enum.any?(finished.internal.events, &is_struct(&1, Effects.SpellGo))
      refute Enum.any?(finished.internal.events, &is_struct(&1, Effects.SpellCastFailed))
      {expired, events} = Aura.expire_due(finished, 1_100)
      refute expired.internal.rooted?
      assert Enum.any?(events, &match?(%Effects.MovementRootChanged{rooted?: false}, &1))
      assert Bitwise.band(expired.unit.flags, 0x80000000) == 0
    end
  end

  defp caster(_context) do
    %{
      caster: %Character{
        object: %Object{guid: 91_986_300},
        unit: %Unit{level: 10, health: 50, max_health: 100, power1: 100, max_power1: 100, auras: []},
        player: %Player{},
        movement_block: %MovementBlock{movement_flags: 0, position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: WorldRef.open(0)}
      }
    }
  end
end
