defmodule ThistleTea.Game.Entity.Logic.TemporarySpellPowerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:caster]

  describe "from_caster/3" do
    test "adds stacked temporary power to equipment and respects schools and weapon restrictions", %{caster: caster} do
      {buffed, _} = Aura.apply_spell(caster, 1, 60, buff(), 0)
      {buffed, _} = Aura.apply_spell(buffed, 1, 60, buff(), 0)
      context = context(buffed, spell(:school_damage))
      assert context.spell_damage_bonus.fire == 110
      assert context.spell_damage_bonus.frost == 0
      assert context.healing_bonus == 220

      for restriction <- [
            %{buff() | equipped_item_class: 2},
            %{buff() | equipped_item_inventory_type_mask: 1}
          ] do
        {restricted, _} = Aura.apply_spell(caster, 1, 60, restriction, 0)
        assert context(restricted, spell(:school_damage)).spell_damage_bonus.fire == 10
      end

      assert context(buffed, %{spell(:heal) | school: :frost}).healing_bonus == 20
    end

    test "removal changes new snapshots while preserving spells already cast", %{caster: caster} do
      {buffed, _} = Aura.apply_spell(caster, 1, 60, buff(), 0)
      saved = context(buffed, spell(:school_damage))
      {cancelled, _} = Aura.cancel_spell(buffed, buff().id, 500)
      {expired, _} = Aura.tick(buffed, 1_000)
      dead = Core.take_damage(buffed, 1_000, 500)

      for entity <- [cancelled, expired, dead] do
        fresh = context(entity, spell(:school_damage))
        assert fresh.spell_damage_bonus.fire == 10
        assert fresh.healing_bonus == 20
      end

      assert saved.spell_damage_bonus.fire == 60
      assert saved.healing_bonus == 120
    end
  end

  describe "receive/4" do
    test "direct damage and healing scale temporary power by their coefficient", %{caster: caster} do
      {buffed, _} = Aura.apply_spell(caster, 1, 60, buff(), 0)
      {damaged, _} = SpellEffect.receive(caster, context(buffed, spell(:school_damage)), spell(:school_damage), 0)
      assert damaged.unit.health == 370
      {healed, _} = SpellEffect.receive(caster, context(buffed, spell(:heal)), spell(:heal), 0)
      assert healed.unit.health == 660
    end

    test "periodic damage and healing retain their launch bonus after the buff expires", %{caster: caster} do
      {buffed, _} = Aura.apply_spell(caster, 1, 60, buff(), 0)

      for {aura, amount, health} <- [{:periodic_damage, 115, 385}, {:periodic_heal, 130, 630}] do
        spell = %{
          spell(:apply_aura)
          | duration_ms: 3_000,
            effects: [%{hd(spell(:apply_aura).effects) | aura: aura, amplitude_ms: 2_000, bonus_coefficient: 0.25}]
        }

        {affected, _} = SpellEffect.receive(caster, context(buffed, spell), spell, 0)
        assert [%Holder{auras: [%{amount: ^amount}]}] = affected.unit.auras
        {ticked, _} = Aura.tick(affected, 2_000)
        assert ticked.unit.health == health
      end
    end
  end

  defp caster(_context) do
    %{
      caster: %Character{
        object: %Object{guid: 1},
        unit: %Unit{
          health: 500,
          max_health: 1_000,
          level: 60,
          class: 8,
          equipment_bonuses: %{spell_fire: 10, healing: 20},
          auras: []
        },
        player: %Player{},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp buff do
    %Spell{
      id: 900_030,
      duration_ms: 1_000,
      stack_amount: 5,
      effects: [
        %Effect{index: 0, type: :apply_aura, aura: :mod_damage_done, base_points: 50, misc_value: 4},
        %Effect{index: 1, type: :apply_aura, aura: :mod_healing_done, base_points: 100, misc_value: 4}
      ]
    }
  end

  defp spell(type) do
    %Spell{
      id: 900_031,
      school: :fire,
      dmg_class: 1,
      effects: [%Effect{index: 0, type: type, base_points: 100, bonus_coefficient: 0.5}]
    }
  end

  defp context(caster, spell), do: %{CastContext.from_caster(caster, spell, 1) | spell_crit_chance: 0}
end
