defmodule ThistleTea.Game.World.Entity.EffectResolver.CustomSpellTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.EffectResolver.Spells
  alias ThistleTea.Test.Unique

  setup [:caster]

  describe "resolve/2" do
    test "custom points preserve unmodified effects and the cached spell", %{caster: caster, spell: spell} do
      trigger =
        Effects.trigger_spell(caster.object.guid, 60, caster.object.guid, spell.id,
          effect_base_points: %{0 => 0, 2 => -15}
        )

      delivery = caster |> Spells.resolve(trigger) |> Enum.find(&is_struct(&1, Effects.DeliverSpell))
      [zero, original, negative] = delivery.spell.effects
      assert {zero.base_points, zero.base_dice, zero.die_sides} == {0, 0, 0}
      assert original == Enum.at(spell.effects, 1)
      assert {negative.base_points, negative.base_dice, negative.die_sides} == {-15, 0, 0}
      assert caster.internal.spellbook[spell.id] == spell
    end

    test "owner handoff retains every override and duration", %{caster: caster, spell: spell} do
      trigger =
        Effects.trigger_spell(2, 60, caster.object.guid, spell.id,
          resolve_targets?: true,
          effect_base_points: %{0 => 30, 1 => 20, 2 => 10},
          effect_index: 1,
          base_points: 25,
          duration_ms: 5000
        )

      assert [%Effects.TriggerSpellRequest{opts: opts}] = Spells.resolve(caster, trigger)
      assert opts[:effect_base_points] == %{0 => 30, 1 => 20, 2 => 10}
      assert opts[:duration_ms] == 5000

      returned =
        Effects.trigger_spell(
          caster.object.guid,
          60,
          caster.object.guid,
          spell.id,
          Keyword.delete(opts, :resolve_targets?)
        )

      delivery = caster |> Spells.resolve(returned) |> Enum.find(&is_struct(&1, Effects.DeliverSpell))
      assert Enum.map(delivery.spell.effects, & &1.base_points) == [30, 25, 10]
      assert delivery.spell.duration_ms == 5000
    end

    test "a permanent duration override does not change the cached spell", %{caster: caster, spell: spell} do
      trigger = Effects.trigger_spell(caster.object.guid, 60, caster.object.guid, spell.id, duration_ms: -1)
      delivery = caster |> Spells.resolve(trigger) |> Enum.find(&is_struct(&1, Effects.DeliverSpell))
      assert delivery.spell.duration_ms == -1
      assert delivery.spell.max_duration_ms == -1
      assert caster.internal.spellbook[spell.id].duration_ms == 10_000
    end
  end

  defp caster(_context) do
    guid = Unique.integer()

    spell = %Spell{
      id: 90_999_001,
      duration_ms: 10_000,
      effects:
        for(
          index <- 0..2,
          do: %Effect{
            index: index,
            type: :apply_aura,
            aura: :mod_stat,
            misc_value: index,
            base_points: 5,
            base_dice: 1,
            die_sides: 5,
            implicit_target_a: :caster
          }
        )
    }

    character = %Character{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 1000, level: 60, auras: []},
      player: %Player{},
      internal: %Internal{world: %WorldRef{map_id: 0}, spellbook: %{spell.id => spell}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{caster: character, spell: spell}
  end
end
