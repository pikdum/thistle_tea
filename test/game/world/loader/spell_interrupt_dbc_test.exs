defmodule ThistleTea.Game.World.Loader.SpellInterruptDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  setup [:caster]

  describe "receive/4" do
    test "class interrupts use their real school-lock durations", %{entity: entity} do
      fireball = SpellLoader.load(133)

      for {id, duration} <- [{2139, 10_000}, {1766, 5_000}, {6552, 4_000}, {72, 6_000}, {8042, 2_000}] do
        spell = SpellLoader.load(id)
        casting = Casting.start(entity, fireball, Target.self(entity.object.guid), 1_000)
        {stopped, events} = SpellEffect.receive(casting, attacker(), spell, 1_500)
        assert stopped.internal.casting == nil
        assert Cooldowns.school_locked?(stopped, 4, 1_500 + duration - 1)
        refute Cooldowns.school_locked?(stopped, 4, 1_500 + duration)
        assert Enum.any?(events, &match?(%Effects.SpellInterrupted{interrupted_spell_id: 133}, &1))
      end
    end

    test "Counterspell cancels the real Drain Life channel", %{entity: entity} do
      casting = Casting.start(entity, SpellLoader.load(689), Target.unit(2), 1_000)
      assert casting.unit.channel_spell == 689
      {stopped, _events} = SpellEffect.receive(casting, attacker(), SpellLoader.load(2139), 2_000)
      assert stopped.internal.casting == nil
      assert stopped.unit.channel_spell == 0
      assert Cooldowns.school_locked?(stopped, 32, 11_999)
      assert Enum.any?(stopped.internal.events, &match?(%Effects.RemoveAura{target_guid: 2, spell_id: 689}, &1))
    end

    test "interrupt-immune creatures take Kick damage without losing their cast", %{entity: entity} do
      entity = %{entity | internal: %{entity.internal | creature: %Creature{mechanic_immune_mask: 33_554_432}}}
      casting = Casting.start(entity, SpellLoader.load(133), Target.self(entity.object.guid), 1_000)
      {damaged, events} = SpellEffect.receive(casting, attacker(), SpellLoader.load(1766), 1_500)
      assert damaged.unit.health < entity.unit.health
      assert damaged.internal.casting != nil
      refute Cooldowns.school_locked?(damaged, 4, 1_500)
      refute Enum.any?(events, &match?(%Effects.SpellInterrupted{}, &1))
    end
  end

  defp attacker do
    %CastContext{caster_guid: 2, caster_level: 60, attack_skill: 300, hit_chance_bonus: 100, target_role: :other}
  end

  defp caster(_context) do
    %{
      entity: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 10_000, max_health: 10_000, level: 1},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end
end
