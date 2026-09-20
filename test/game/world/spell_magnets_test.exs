defmodule ThistleTea.Game.World.SpellMagnetsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.SpellMagnets
  alias ThistleTea.Game.WorldRef

  setup [:world]

  describe "redirect/4" do
    test "one source intercepts exactly one concurrent party spell", context do
      %{caster: caster, spell: spell, totem: totem, target: target, ally: ally} = context

      results =
        [target, ally]
        |> Task.async_stream(&SpellMagnets.redirect(caster, spell, &1), ordered: true)
        |> Enum.map(fn {:ok, guid} -> guid end)

      assert Enum.count(results, &(&1 == totem)) == 1
      assert Enum.count(results, &(&1 in [target, ally])) == 1
      assert_receive {:"$gen_cast", {:remove_aura, 8178, ^totem}}
      assert SpellMagnets.redirect(caster, spell, target) == target
    end

    test "refreshing recipients or publishing the same source cannot refill a spent charge", context do
      %{caster: caster, spell: spell, totem: totem, target: target, magnet: magnet} = context
      assert SpellMagnets.redirect(caster, spell, target) == totem
      SpellMagnets.sync(totem, self(), [magnet])
      SpellMagnets.sync(target, self(), [%{magnet | applied_at: magnet.applied_at + 1}])
      assert SpellMagnets.redirect(caster, spell, target) == target
    end

    test "rejects abilities, poisons, area spells, beneficial spells and bypass attributes", context do
      %{caster: caster, spell: spell, target: target, totem: totem} = context

      spells =
        [
          %{spell | dmg_class: 2},
          %{spell | dmg_class: 3},
          %{spell | dispel_type: 4},
          %{spell | effects: [%Effect{type: :heal, implicit_target_a: :target_ally}]},
          %{spell | effects: [%Effect{type: :school_damage, implicit_target_a: :aoe_enemy_at_caster}]}
        ] ++
          Enum.map(
            [:ability, :no_redirection, :suppress_target_procs, :passive],
            &%{spell | attributes: MapSet.new([&1])}
          )

      for bypass <- spells, do: assert(SpellMagnets.redirect(caster, bypass, target) == target)
      assert SpellMagnets.redirect(caster, spell, target) == totem
    end

    test "redirects a non-damaging hostile spell and does not require reflectability", context do
      %{caster: caster, spell: spell, target: target, totem: totem} = context

      spell = %{
        spell
        | attributes: MapSet.new([:no_reflection]),
          effects: [%Effect{type: :apply_aura, aura: :mod_decrease_speed, implicit_target_a: :target_enemy}]
      }

      assert SpellMagnets.redirect(caster, spell, target) == totem
    end

    test "rejects dead, out-of-range and other-instance sources without spending", context do
      %{caster: caster, spell: spell, target: target, totem: totem} = context
      Metadata.update(totem, %{alive?: false})
      assert SpellMagnets.redirect(caster, spell, target) == target
      Metadata.update(totem, %{alive?: true})
      SpatialHash.update(:mobs, totem, 451, 100.0, 0.0, 0.0)
      assert SpellMagnets.redirect(caster, spell, target) == target
      SpatialHash.update(:mobs, totem, WorldRef.instance(451, 2), 2.0, 0.0, 0.0)
      assert SpellMagnets.redirect(caster, spell, target) == target
      SpatialHash.update(:mobs, totem, 451, 2.0, 0.0, 0.0)
      assert SpellMagnets.redirect(caster, spell, target) == totem
    end

    test "honors source and recipient removal and expiry", context do
      %{caster: caster, spell: spell, target: target, totem: totem, magnet: magnet} = context
      SpellMagnets.sync(target, self(), [])
      assert SpellMagnets.redirect(caster, spell, target) == target
      SpellMagnets.sync(target, self(), [magnet])
      SpellMagnets.sync(totem, self(), [])

      assert ExUnit.CaptureLog.capture_log(fn ->
               assert SpellMagnets.redirect(caster, spell, target) == target
             end) == ""

      SpellMagnets.sync(totem, self(), [%{magnet | expires_at: Time.now() - 1}])
      assert SpellMagnets.redirect(caster, spell, target) == target
      SpellMagnets.sync(totem, self(), [magnet])
      SpellMagnets.sync(target, self(), [%{magnet | expires_at: Time.now() - 1}])
      assert SpellMagnets.redirect(caster, spell, target) == target
    end

    test "source process exit retires protection even with stale metadata", context do
      %{caster: caster, spell: spell, target: target, totem: totem, magnet: magnet} = context
      server = start_supervised!({SpellMagnets, name: nil})

      owner =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      SpellMagnets.sync(totem, owner, [magnet], server)
      SpellMagnets.sync(target, self(), [magnet], server)
      monitor = Process.monitor(owner)
      send(owner, :stop)
      assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
      :sys.get_state(server)
      assert SpellMagnets.redirect(caster, spell, target, server) == target
    end
  end

  describe "resolve/3" do
    test "an intercepted chain stops at the magnet", context do
      %{caster: caster, spell: spell, target: target, totem: totem} = context
      spell = %{spell | effects: [%{hd(spell.effects) | chain_targets: 3}]}
      assert SpellTargetResolver.resolve(caster, spell, Target.unit(target)) == [totem]
    end

    test "launch resolution substitutes the magnet for every effect in a cast", context do
      %{caster: caster, spell: spell, target: target, totem: totem} = context

      spell = %{
        spell
        | effects:
            spell.effects ++ [%Effect{type: :apply_aura, aura: :periodic_damage, implicit_target_a: :target_enemy}]
      }

      assert SpellTargetResolver.resolve(caster, spell, Target.unit(target)) == [totem]
      assert SpellTargetResolver.resolve(caster, spell, Target.unit(target)) == [target]
    end
  end

  describe "complete/2" do
    test "launch packets and delivery use the redirected target while caster effects remain local", context do
      %{caster: caster, spell: spell, target: target, totem: totem} = context

      caster = %Mob{
        object: %Object{guid: caster.object.guid},
        unit: %Unit{health: 100, max_health: 100, level: 50, power1: 100, max_power1: 100, auras: []},
        internal: caster.internal,
        movement_block: caster.movement_block
      }

      spell = %{
        spell
        | attributes: MapSet.new([:ignore_line_of_sight]),
          effects:
            spell.effects ++ [%Effect{type: :energize, implicit_target_a: :caster, misc_value: 0, base_points: 1}]
      }

      now = Time.now()
      result = caster |> Casting.start(spell, Target.unit(target), now) |> Casting.complete(now)
      go = Enum.find(result.internal.events, &match?(%Effects.SpellGo{}, &1))
      assert totem in go.hit_guids
      refute target in go.hit_guids
      assert go.targets == Target.unit(totem)
      delivery = Enum.find(result.internal.events, &match?(%Effects.DeliverSpell{}, &1))
      assert delivery.target_guid == totem
      assert delivery.cast_context.selected_target_guid == totem
    end
  end

  defp world(_) do
    caster_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
    target = Guid.from_low_guid(:player, System.unique_integer([:positive]))
    ally = Guid.from_low_guid(:player, System.unique_integer([:positive]))
    totem = Guid.runtime(:mob, 5925)
    Entity.register(totem)

    for {table, guid, x, faction} <- [
          {:players, caster_guid, 0.0, 1},
          {:players, target, 3.0, 2},
          {:players, ally, 4.0, 2},
          {:mobs, totem, 2.0, 2}
        ] do
      SpatialHash.update(table, guid, 451, x, 0.0, 0.0)

      Metadata.put(guid, %{
        alive?: true,
        creature_type: 11,
        faction_template: %FactionTemplate{id: faction, faction: faction, enemies_1: 3 - faction},
        unit_flags: 0
      })

      on_exit(fn ->
        SpatialHash.remove(table, guid)
        Metadata.delete(guid)
      end)
    end

    caster = %{
      object: %{guid: caster_guid},
      internal: %Internal{world: WorldRef.open(451)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    magnet = %{source_guid: totem, spell_id: 8178, applied_at: Time.now(), expires_at: nil, charges: 1, radius: 30.0}
    for guid <- [totem, target, ally], do: SpellMagnets.sync(guid, self(), [magnet])

    spell = %Spell{id: 133, dmg_class: 1, effects: [%Effect{type: :school_damage, implicit_target_a: :target_enemy}]}
    %{caster: caster, spell: spell, totem: totem, target: target, ally: ally, magnet: magnet}
  end
end
