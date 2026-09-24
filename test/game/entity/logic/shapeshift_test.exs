defmodule ThistleTea.Game.Entity.Logic.ShapeshiftTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Shapeshift
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target

  setup [:character]

  describe "interrupt_holders/2" do
    test "cleanses roots and snares on entry, replacement and exit", %{character: character} do
      for form <- [1, 2, 3, 4, 5, 8, 31] do
        {rooted, _} = apply_aura(character, root())
        {rooted, _} = apply_aura(rooted, snare())
        assert rooted.internal.rooted?
        assert rooted.movement_block.run_speed == 3.5

        {shifted, events} = apply_aura(rooted, form(form))
        refute Aura.has_spell?(shifted, 339)
        refute Aura.has_spell?(shifted, 116)
        refute shifted.internal.rooted?
        assert shifted.movement_block.run_speed == 7.0
        assert Enum.any?(events, &match?(%Effects.MovementRootChanged{rooted?: false}, &1))
        assert Enum.any?(events, &match?(%Effects.MovementSpeedChanged{speed: 7.0}, &1))

        {trapped, _} = apply_aura(shifted, root())
        {trapped, _} = apply_aura(trapped, snare())
        assert trapped.internal.rooted?
        assert Aura.has_spell?(trapped, 116)

        {cancelled, _} = Aura.cancel_spell(trapped, form(form).id, 2_000)
        assert cancelled.unit.auras == []
        refute cancelled.internal.rooted?
        assert cancelled.movement_block.run_speed == 7.0

        {replaced, _} = apply_aura(trapped, form(if(form == 1, do: 5, else: 1)))
        refute Aura.has_spell?(replaced, 339)
        refute Aura.has_spell?(replaced, 116)
      end
    end

    test "unrelated aura changes and holder updates do not repeat the cleanse", %{character: character} do
      {shifted, _} = apply_aura(character, form(1))
      {rooted, _} = apply_aura(shifted, root())
      {refreshed, _} = Aura.apply_spell(rooted, 7, 50, form(1), 2_000)
      assert refreshed.internal.rooted?
      assert Aura.has_spell?(refreshed, 339)

      {ticked, _} = Aura.tick(refreshed, 2_500)
      assert ticked.internal.rooted?
      assert Aura.has_spell?(ticked, 339)
    end

    test "other forms do not gain druid movement cleansing", %{character: character} do
      for form <- [16, 17, 18, 19, 28, 30, 32] do
        {rooted, _} = apply_aura(character, root())
        {shifted, _} = apply_aura(rooted, form(form))
        assert shifted.internal.rooted?
        assert Aura.has_spell?(shifted, 339)
      end
    end

    test "real shapeshifts cancel sensitive buffs while stances and Moonkin retain them", %{character: character} do
      for form <- [1, 2, 3, 4, 5, 8, 16, 17, 18, 19, 28, 30, 31, 32] do
        {buffed, _} = apply_aura(character, water_walk())
        {shifted, events} = apply_aura(buffed, form(form))
        assert Aura.has_spell?(shifted, 546) == not Spell.shapeshifted?(form)
        assert Enum.any?(events, &match?(%Effects.WaterWalkChanged{enabled?: false}, &1)) == Spell.shapeshifted?(form)
      end
    end
  end

  describe "removable_spells/1" do
    test "keeps mechanic-free effects and protected crowd controls" do
      for mechanic <- [0, 1, 2, 5, 8, 12, 13, 18, 20, 23, 24, 27, 30] do
        spell = %{snare() | mechanic: mechanic, effects: [%Effect{type: :apply_aura, aura: :mod_decrease_speed}]}
        assert Shapeshift.removable_spells([holder(spell)]) == []
      end

      mechanic_free_root = %{root() | mechanic: 0}
      assert Shapeshift.removable_spells([holder(mechanic_free_root)]) == []
      assert Shapeshift.removable_spells([holder(root()), holder(snare())]) == [339, 116]
    end

    test "checks mechanics on every effect and the legacy daze signature" do
      daze = %{snare() | spell_icon: 15, dispel_type: 0, effects: [%Effect{aura: :mod_decrease_speed, mechanic: 15}]}
      assert Shapeshift.removable_spells([holder(daze)]) == []
      assert Shapeshift.removable_spells([holder(%{daze | dispel_type: 1})]) == [116]

      concussive = %{daze | effects: [%Effect{aura: :mod_decrease_speed, mechanic: 11}]}
      assert Shapeshift.removable_spells([holder(concussive)]) == [116]

      protected = %{snare() | effects: snare().effects ++ [%Effect{mechanic: 27}]}
      assert Shapeshift.removable_spells([holder(protected)]) == []
    end

    test "removes the complete root spell including its damage aura", %{character: character} do
      roots = %{
        root()
        | effects: root().effects ++ [%Effect{type: :apply_aura, aura: :periodic_damage, amplitude_ms: 3_000}]
      }

      {rooted, _} = apply_aura(character, roots)
      assert Enum.any?(hd(rooted.unit.auras).auras, &(&1.type == :periodic_damage))
      {shifted, _} = apply_aura(rooted, form(1))
      refute Aura.has_spell?(shifted, roots.id)
    end
  end

  describe "validate_target/3" do
    test "enforces sensitive buffs for both self and external targets", %{character: character} do
      for form <- [0, 1, 5, 16, 17, 28, 30, 31] do
        expected = if Spell.shapeshifted?(form), do: {:error, :bad_targets}, else: :ok
        caster = %{character | unit: %{character.unit | shapeshift_form: form}}
        assert Shapeshift.validate_target(caster, water_walk(), :self) == expected
        assert Shapeshift.validate_target(character, water_walk(), %{shapeshift_form: form}) == expected
        assert CastValidation.validate_target(caster, water_walk(), Target.self(7), :self) == expected
      end
    end

    test "allows ordinary buffs and area spells", %{character: character} do
      target = %{shapeshift_form: 1}
      assert :ok = Shapeshift.validate_target(character, %{water_walk() | aura_interrupt_flags: 0}, target)
      area = %{water_walk() | effects: [%Effect{type: :apply_area_aura, aura: :water_walk, area_target?: true}]}
      assert :ok = Shapeshift.validate_target(character, area, target)
    end
  end

  describe "SpellEffect.receive/4" do
    test "the Shapeshift Form Effect uses the same cleansing rules", %{character: character} do
      {rooted, _} = apply_aura(character, root())
      spell = %Spell{id: 9033, spell_family: 7, effects: [%Effect{type: :dummy, implicit_target_a: :caster}]}
      context = %CastContext{caster_guid: 7, caster_level: 50, target_role: :caster}
      {cleansed, events} = SpellEffect.receive(rooted, context, spell, 2_000)
      refute cleansed.internal.rooted?
      assert cleansed.unit.auras == []
      assert Enum.any?(events, &match?(%Effects.MovementRootChanged{rooted?: false}, &1))
    end
  end

  defp character(_context) do
    character = %Character{
      object: %Object{guid: 7},
      unit: %Unit{class: 11, race: 4, level: 50, health: 1_000, max_health: 1_000, auras: []},
      player: %Player{},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, run_speed: 7.0, base_run_speed: 7.0}
    }

    %{character: character}
  end

  defp apply_aura(character, spell), do: Aura.apply_spell(character, 7, 50, spell, 1_000)

  defp root do
    %Spell{id: 339, mechanic: 7, duration_ms: 30_000, effects: [%Effect{type: :apply_aura, aura: :mod_root}]}
  end

  defp snare do
    %Spell{
      id: 116,
      duration_ms: 30_000,
      effects: [%Effect{type: :apply_aura, aura: :mod_decrease_speed, mechanic: 11, base_points: -50}]
    }
  end

  defp form(form) do
    %Spell{
      id: 9_000 + form,
      duration_ms: -1,
      effects: [%Effect{type: :apply_aura, aura: :mod_shapeshift, misc_value: form}]
    }
  end

  defp water_walk do
    %Spell{id: 546, aura_interrupt_flags: 0x8000, effects: [%Effect{type: :apply_aura, aura: :water_walk}]}
  end

  defp holder(spell), do: %Holder{spell: spell, auras: Enum.map(spell.effects, &%AuraData{type: &1.aura})}
end
