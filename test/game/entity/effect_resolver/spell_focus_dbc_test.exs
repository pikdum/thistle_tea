defmodule ThistleTea.Game.Entity.EffectResolver.SpellFocusDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: TemplateLoader
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  setup [:caster]

  describe "resolve/2" do
    test "checks the original player before projecting triggered effects", %{caster: caster} do
      effect = Effects.trigger_spell(caster.object.guid, 10, caster.object.guid, 18)

      assert [%Effects.SpellCastFailed{spell_id: 18, reason: :requires_spell_focus, required_focus_id: 1}] =
               Spells.resolve(caster, effect)

      old_radius = :ets.lookup(TemplateLoader, {:focus_radius, 1})

      template =
        TemplateLoader.put(%GameObjectTemplate{
          entry: 951_020,
          type: 8,
          size: 1.0,
          flags: 0,
          faction: 0,
          data: [1, 5]
        })

      object = GameObject.build_summoned(template, caster.internal.world, {1.0, 0.0, 0.0, 0.0})
      {:ok, pid} = World.start_entity(object)

      on_exit(fn ->
        if Process.alive?(pid), do: World.stop_entity(pid)
        :ets.delete(TemplateLoader, template.entry)
        :ets.delete(TemplateLoader, {:focus_radius, 1})
        :ets.insert(TemplateLoader, old_radius)
      end)

      assert Enum.any?(Spells.resolve(caster, effect), &is_struct(&1, Effects.DeliverSpell))
    end

    test "routes a foreign player's triggered focus spell to that owner", %{caster: caster} do
      guid = caster.object.guid
      effect = Effects.trigger_spell(guid, 10, guid, 18)

      assert [%Effects.TriggerSpellRequest{source_guid: ^guid, spell_id: 18}] =
               Spells.resolve(%Mob{object: %Object{guid: Guid.from_low_guid(:mob, 1, 951_102)}}, effect)
    end

    test "does not impose player focus requirements on creature triggers", %{caster: caster} do
      mob = %Mob{
        object: %Object{guid: Guid.from_low_guid(:mob, 1, 951_103)},
        unit: caster.unit,
        internal: caster.internal,
        movement_block: caster.movement_block
      }

      effect = Effects.trigger_spell(mob.object.guid, 10, mob.object.guid, 18)
      assert Enum.any?(Spells.resolve(mob, effect), &is_struct(&1, Effects.DeliverSpell))
    end
  end

  defp caster(_context) do
    %{
      caster: %Character{
        object: %Object{guid: 951_101},
        player: %Player{},
        unit: %Unit{level: 10, health: 50, max_health: 100},
        internal: %Internal{world: WorldRef.instance(999, 3)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end
end
