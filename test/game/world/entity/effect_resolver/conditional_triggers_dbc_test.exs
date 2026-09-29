defmodule ThistleTea.Game.World.Entity.EffectResolver.ConditionalTriggersDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Combat
  alias ThistleTea.Game.Core.Combat.Disarm
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Effects.RandomChoice
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Power.Regen
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Stats
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.EffectResolver.Spells
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellScriptName
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  @moduletag :dbc_db
  @spells [6410, 6411, 15_712, 15_752, 15_753]

  setup [:script_labels, :entities]

  describe "resolve/2" do
    test "boomerang damage permits all four control outcomes and normal recovery", %{caster: caster, target: target} do
      spell = caster.internal.spellbook[15_712]
      context = CastContext.from_caster(caster, spell, target.object.guid)
      {damaged, events} = SpellEffect.receive(target, context, spell, 1_000)
      assert damaged.unit.health < target.unit.health
      assert [disarm, stun] = Enum.filter(events, &is_struct(&1, RandomChoice))

      for {disarm_roll, stun_roll} <- [{31, 11}, {1, 11}, {31, 1}, {1, 1}] do
        triggers = RandomChoice.select(disarm, disarm_roll) ++ RandomChoice.select(stun, stun_roll)
        controlled = Enum.reduce(triggers, damaged, &deliver(caster, &2, &1, 1_000))
        assert Disarm.active?(controlled) == (disarm_roll == 1)
        assert Aura.has_aura?(controlled, :mod_stun) == (stun_roll == 1)

        if disarm_roll == 1 do
          assert Combat.damage_range(controlled) != Combat.damage_range(target)
          assert Combat.attack_speed_ms(controlled) == 2_000
        end

        {recovered, _} = Aura.tick(controlled, 3_001)
        refute Aura.has_aura?(recovered, :mod_stun)
        assert Disarm.active?(recovered) == (disarm_roll == 1)
        {recovered, _} = Aura.tick(recovered, 11_001)
        refute Disarm.active?(recovered)
        assert Combat.damage_range(recovered) == Combat.damage_range(target)
        assert Combat.attack_speed_ms(recovered) == 3_000

        dead = Entity.take_damage(controlled, 10_000, 1_500)
        refute Aura.has_aura?(dead, :mod_stun)
        refute Disarm.active?(dead)
      end
    end

    test "Scorpid Surprise always feeds the player and optionally applies real periodic poison", %{caster: caster} do
      spell = caster.internal.spellbook[6410]
      context = CastContext.from_caster(caster, spell, caster.object.guid)
      {eating, events} = SpellEffect.receive(caster, context, spell, 1_000)
      assert Aura.has_spell?(eating, 6410)
      assert hd(hd(eating.unit.auras).auras).amplitude_ms == 5_000
      assert [choice] = Enum.filter(events, &is_struct(&1, RandomChoice))
      assert RandomChoice.select(choice, 11) == []
      refute Aura.has_spell?(eating, 6411)
      assert Regen.tick(eating, 3_000).unit.health == eating.unit.health + 28

      [trigger] = RandomChoice.select(choice, 1)
      poisoned = deliver(caster, eating, trigger, 1_000)
      assert Aura.has_spell?(poisoned, 6410)
      assert Aura.has_spell?(poisoned, 6411)
      {ticked, events} = Aura.tick(poisoned, 4_000)
      assert ticked.unit.health == poisoned.unit.health - 10
      assert Enum.any?(events, &match?(%Effects.SpellDamage{spell_id: 6411, damage: 10, periodic?: true}, &1))
      {expired, _} = Aura.tick(ticked, 22_001)
      refute Aura.has_spell?(expired, 6411)
      refute Aura.has_spell?(expired, 6410)
    end
  end

  defp deliver(caster, target, trigger, now) do
    deliveries = Spells.resolve(caster, trigger) |> Enum.filter(&is_struct(&1, Effects.DeliverSpell))
    assert [%Effects.DeliverSpell{cast_context: context, spell: spell, target_guid: guid}] = deliveries
    assert guid == target.object.guid
    {target, _events} = SpellEffect.receive(target, context, spell, now)
    target
  end

  defp script_labels(_context) do
    for {id, label} <- [{6410, "spell_scorpid_surprise"}, {15_712, "spell_linkens_boomerang"}] do
      previous = :ets.lookup(SpellScriptName, id)
      :ets.insert(SpellScriptName, {id, label})

      on_exit(fn ->
        :ets.delete(SpellScriptName, id)
        :ets.insert(SpellScriptName, previous)
      end)
    end

    :ok
  end

  defp entities(_context) do
    world = WorldRef.instance(0, System.unique_integer([:positive]))
    spells = Map.new(@spells, &{&1, SpellLoader.load(&1)})

    unit =
      %Unit{
        health: 600,
        max_health: 1_000,
        level: 60,
        class: 2,
        base_spirit: 0,
        auras: [],
        stand_state: 1,
        base_min_damage: 40.0,
        base_max_damage: 60.0,
        base_melee_attack_time: 3_000
      }
      |> Stats.recompute()

    characters =
      for _ <- 1..2 do
        guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))

        character = %Character{
          object: %Object{guid: guid},
          unit: unit,
          player: %Player{},
          internal: %Internal{world: world, spellbook: spells},
          movement_block: struct!(%MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}, MovementBlock.player_speeds())
        }

        SpatialHash.insert(:players, guid, world, 0.0, 0.0, 0.0)
        Metadata.put(guid, %{alive?: true, level: 60, no_spell_defense?: true})

        on_exit(fn ->
          SpatialHash.remove(:players, guid)
          Metadata.delete(guid)
        end)

        character
      end

    [caster, target] = characters
    %{caster: caster, target: target}
  end
end
