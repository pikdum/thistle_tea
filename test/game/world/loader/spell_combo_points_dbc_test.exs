defmodule ThistleTea.Game.World.Loader.SpellComboPointsDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.ComboPoints
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  setup [:entities]

  describe "load/1" do
    test "Premeditation grants two points for ten seconds", %{caster: caster, target: target} do
      spell = SpellLoader.load(14_183)
      assert spell.dmg_class == 0
      assert spell.duration_ms == 10_000
      context = context(caster, spell)
      {_target, events} = SpellEffect.receive(target, context, spell, 1_000)
      assert [%Effects.AddComboPoints{amount: 2} = award] = awards(events)
      caster = ComboPoints.award(caster, award, 1_000)
      assert caster.player.combo_points == 2
      assert Aura.has_aura?(caster, :retain_combo_points)
      {caster, _events} = Aura.tick(caster, 11_000)
      assert caster.player.combo_points == 0
      refute Aura.has_aura?(caster, :retain_combo_points)
    end

    test "rogue and druid triggered builders grant one point", %{caster: caster, target: target} do
      for id <- [13_977, 14_157, 14_189, 15_250, 16_953] do
        spell = SpellLoader.load(id)
        assert spell.dmg_class == 0
        {_target, events} = SpellEffect.receive(target, %{context(caster, spell) | triggered?: true}, spell, 1_000)
        assert [%Effects.AddComboPoints{amount: 1, retention: nil} = award] = awards(events)
        assert ComboPoints.award(caster, award, 1_000).player.combo_points == 1
      end
    end
  end

  defp awards(events), do: Enum.filter(events, &is_struct(&1, Effects.AddComboPoints))

  defp context(caster, spell) do
    %CastContext{
      caster_guid: caster.object.guid,
      caster_type: :player,
      caster_level: 60,
      spell: spell,
      target_role: :other
    }
  end

  defp entities(_context) do
    caster = %Character{
      object: %Object{guid: 5},
      unit: %Unit{class: 4, level: 60, health: 100, max_health: 100, auras: []},
      player: %Player{flags: 0},
      internal: %Internal{}
    }

    target = %Mob{object: %Object{guid: 9}, unit: %Unit{health: 100, max_health: 100, auras: []}}
    %{caster: caster, target: target}
  end
end
