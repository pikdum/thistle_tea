defmodule ThistleTea.Game.World.Entity.EffectResolver.MountTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.EffectResolver
  alias ThistleTea.Game.World.Loader.MapTemplate

  describe "resolve/2" do
    test "Black Qiraji chooses the destination map variant and replaces the old mount once" do
      map_id = System.unique_integer([:positive]) + 900_000
      :ets.insert(MapTemplate, {map_id, 2, nil})
      on_exit(fn -> :ets.delete(MapTemplate, map_id) end)

      spells = Map.new([458, 25_863, 26_655], &{&1, mount(&1)})

      c = %Character{
        object: %Object{guid: 1},
        unit: %Unit{level: 60, health: 100, max_health: 100, auras: []},
        player: %Player{},
        internal: %Internal{spellbook: spells, world: WorldRef.open(0)},
        movement_block: struct!(%MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}, MovementBlock.player_speeds())
      }

      parent = %Spell{id: 26_656, effects: [%Effect{index: 0, type: :script_effect, implicit_target_a: :caster}]}

      for {map, expected} <- [{0, 26_655}, {map_id, 25_863}] do
        c = %{c | internal: %{c.internal | world: WorldRef.open(map)}}
        {mounted, _} = Aura.apply_spell(c, 1, 60, spells[458], 1_000)
        context = %CastContext{caster_guid: 1, caster_level: 60, cast_item_guid: 123}
        {changed, events} = SpellEffect.receive(mounted, context, parent, 2_000)
        refute Aura.has_aura?(changed, :mounted)
        assert Enum.count(events, &is_struct(&1, Effects.SummonMount)) == 1
        resolved = EffectResolver.resolve(changed, events)

        assert [%Effects.DeliverSpell{target_guid: 1, spell: spell, cast_context: child_context}] =
                 Enum.filter(resolved, &is_struct(&1, Effects.DeliverSpell))

        assert spell.id == expected
        assert child_context.cast_item_guid == 123
        assert child_context.triggered?
        {qiraji, _} = SpellEffect.receive(changed, child_context, spell, 2_000)
        assert qiraji.unit.mount_display_id == 15_976
        assert qiraji.movement_block.run_speed == 14.0
        assert Enum.map(qiraji.unit.auras, & &1.spell.id) == [expected]
        {cancelled, _} = Aura.cancel_spell(qiraji, expected, 3_000)
        assert cancelled.unit.mount_display_id == 0
        assert cancelled.movement_block.run_speed == 7.0
      end
    end
  end

  defp mount(id) do
    %Spell{
      id: id,
      effects: [
        %Effect{index: 0, type: :apply_aura, aura: :mounted, misc_value: 15_976},
        %Effect{index: 1, type: :apply_aura, aura: :mod_increase_mounted_speed, base_points: 100}
      ]
    }
  end
end
