defmodule ThistleTea.Game.World.Loader.PercentManaRecoveryDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "food and drinks restore their actual percentages of both resources" do
      for {id, health_gain, mana_gain} <- [
            {24_355, 0, 20},
            {24_707, 30, 30},
            {25_990, 50, 50},
            {26_263, 40, 30},
            {29_055, 40, 30}
          ] do
        spell = SpellLoader.load(id)

        entity = %Mob{
          object: %Object{guid: 1},
          unit: %Unit{health: 100, max_health: 1_000, power1: 100, max_power1: 1_000, auras: []}
        }

        {entity, _events} = Aura.apply_spell(entity, 2, 60, spell, 0)
        assert Aura.next_event_at(entity) == 1_000
        {entity, events} = Aura.tick(entity, 1_000)
        assert entity.unit.health == 100 + health_gain
        assert entity.unit.power1 == 100 + mana_gain
        assert Enum.any?(events, &match?(%Effects.PeriodicAuraLog{aura_type: :obs_mod_mana}, &1))
      end
    end

    test "Fel Energy and Resurgence retain their slower tick rates" do
      for {id, amplitude, amount} <- [{18_792, 4_000, 20}, {23_779, 3_000, 10}] do
        spell = SpellLoader.load(id)

        entity = %Mob{
          object: %Object{guid: 1},
          unit: %Unit{health: 100, max_health: 1_000, power1: 100, max_power1: 1_000, auras: []}
        }

        {entity, _events} = Aura.apply_spell(entity, 2, 60, spell, 0)
        assert Aura.next_event_at(entity) == amplitude
        {entity, _events} = Aura.tick(entity, amplitude)
        assert entity.unit.power1 == 100 + amount
      end
    end
  end
end
