defmodule ThistleTea.Game.World.Loader.ResistanceDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "Mark of the Wild coexists with stronger school protection and survives its removal" do
      mark = SpellLoader.load(9885)
      fire = SpellLoader.load(19_891)
      character = character()

      for spells <- [[mark, fire], [fire, mark]] do
        active =
          Enum.reduce(spells, character, fn spell, entity ->
            {entity, _events} = Aura.apply_spell(entity, 1, 60, spell, 1_000)
            entity
          end)

        assert Aura.has_spell?(active, mark.id)
        assert Aura.has_spell?(active, fire.id)
        assert active.unit.fire_resistance == 30
        assert active.unit.frost_resistance == 20
        assert active.unit.normal_resistance == 285
        assert active.unit.intellect == 112

        {fallback, _events} = Aura.cancel_spell(active, fire.id, 2_000)
        assert fallback.unit.fire_resistance == 20
        assert fallback.unit.normal_resistance == 285
        assert fallback.internal.broadcast_update?

        {expired, _events} = Aura.expire_due(fallback, 2_000_000)
        assert expired.unit.auras == []
        assert expired.unit.fire_resistance == 0
        assert expired.unit.normal_resistance == 0
        assert expired.unit.intellect == 100
      end
    end
  end

  defp character do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 100, max_health: 100, base_intellect: 100, auras: []},
      player: %Player{},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end
end
