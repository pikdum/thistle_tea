defmodule ThistleTea.Game.World.Loader.FlareDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.PersistentArea
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  describe "load/1" do
    test "Flare reveals both concealment types and protects only for its source lifetime" do
      flare = SpellLoader.load(1543)
      assert Spell.attribute?(flare, :immunity_purges_effect)
      assert Spell.harmful?(flare)

      effects = Enum.filter(flare.effects, &(&1.type == :persistent_area_aura))
      assert [%Effect{aura: :dispel_immunity, misc_value: 5}, %Effect{aura: :dispel_immunity, misc_value: 6}] = effects

      target = target()
      stealth = SpellLoader.load(1784)
      invisibility = SpellLoader.load(66)
      {target, _} = Aura.apply_spell(target, 1, 60, stealth, 0)
      {target, _} = Aura.apply_spell(target, 1, 60, invisibility, 0)
      assert Bitwise.band(target.player.field_bytes2_flags, 0x60) == 0x60

      target =
        Enum.reduce(effects, target, fn effect, target ->
          spell = %{flare | effects: [%{effect | type: :apply_aura, semantic: nil}]}

          context = %CastContext{
            caster_guid: 2,
            caster_level: 60,
            target_hostile?: true,
            spell: spell,
            persistent_area: %PersistentArea{
              guid: 100 + effect.index,
              position: {target.internal.world, 0.0, 0.0, 0.0},
              radius: effect.radius_yards,
              started_at: 100,
              expires_at: 100 + flare.duration_ms
            }
          }

          {target, _} = Aura.apply_spell(target, context, spell, 100)
          target
        end)

      assert [%Holder{spell: %Spell{id: 1543}, auras: [_, _]}] = target.unit.auras
      assert Bitwise.band(target.player.field_bytes2_flags, 0x60) == 0
      assert Bitwise.band(target.unit.vis_flag, 0x02) == 0

      for spell <- [stealth, invisibility] do
        {blocked, _} = Aura.apply_spell(target, 1, 60, spell, 200)
        refute Aura.has_spell?(blocked, spell.id)
      end

      {target, _} = Aura.tick(target, 100 + flare.duration_ms)
      assert target.unit.auras == []

      for spell <- [stealth, invisibility] do
        {restored, _} = Aura.apply_spell(target, 1, 60, spell, 101 + flare.duration_ms)
        assert Aura.has_spell?(restored, spell.id)
      end
    end
  end

  defp target do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 1_000, max_health: 1_000, auras: []},
      player: %Player{},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end
end
