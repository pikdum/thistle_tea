defmodule ThistleTea.Game.World.Loader.MountTransformationDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.CreatureTemplate
  alias ThistleTea.Game.Entity.EffectResolver
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Mount
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.CreatureTemplate, as: CreatureTemplateLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  setup [:cached_models, :character]

  describe "load/1" do
    test "Holly preserves both speed tiers through resolved triggered spells", %{character: c} do
      holly = SpellLoader.load(25_860)
      assert Spell.attribute?(holly, :allow_while_mounted)
      assert Mount.validate(c, holly, []) == {:error, :only_mounted}

      for {mount_id, reindeer_id, speed} <- [{458, 25_858, 11.2}, {23_228, 25_859, 14.0}] do
        {mounted, _} = Aura.apply_spell(c, 1, 60, SpellLoader.load(mount_id), 1_000)
        context = %{CastContext.from_caster(mounted, holly, 1) | cast_item_guid: 123}
        {changed, events} = SpellEffect.receive(mounted, context, holly, 2_000)
        resolved = EffectResolver.resolve(changed, events)

        assert [%Effects.DeliverSpell{target_guid: 1, spell: spell, cast_context: context}] =
                 Enum.filter(resolved, &is_struct(&1, Effects.DeliverSpell))

        assert spell.id == reindeer_id
        assert context.triggered?
        assert context.cast_item_guid == 123
        {reindeer, _} = SpellEffect.receive(changed, context, spell, 2_000)
        assert reindeer.unit.mount_display_id == 15_960
        assert_in_delta reindeer.movement_block.run_speed, speed, 0.00001
        refute Aura.has_spell?(reindeer, mount_id)
        assert Enum.count(reindeer.unit.auras, &Holder.has_aura_type?(&1, :mounted)) == 1

        {cancelled, _} = Aura.cancel_spell(reindeer, reindeer_id, 3_000)
        assert cancelled.unit.mount_display_id == 0
        assert cancelled.movement_block.run_speed == 7.0
        {swimming, _} = Aura.remove_with_interrupt_flags(reindeer, Aura.interrupt_mask(:under_water), 3_000)
        assert swimming.unit.mount_display_id == 0
        assert swimming.movement_block.run_speed == 7.0
        dead = Core.take_damage(reindeer, 100, 3_000)
        assert dead.unit.mount_display_id == 0
        assert dead.movement_block.run_speed == 7.0
      end
    end

    test "Discombobulate removes the whole mount and expires normally", %{character: c} do
      {mounted, _} = Aura.apply_spell(c, 1, 60, SpellLoader.load(23_228), 1_000)
      spell = SpellLoader.load(4060)
      {changed, _} = SpellEffect.receive(mounted, 2, spell, 2_000)
      assert changed.unit.mount_display_id == 0
      assert changed.unit.display_id == 1_159
      assert_in_delta changed.movement_block.run_speed, 5.6, 0.00001
      assert Aura.has_aura?(changed, :mod_damage_done)
      refute Aura.has_aura?(changed, :mounted)
      {expired, _} = Aura.expire_due(changed, 2_000 + spell.duration_ms)
      assert expired.unit.display_id == 49
      assert expired.unit.mount_display_id == 0
      assert expired.movement_block.run_speed == 7.0
    end
  end

  defp cached_models(_context) do
    for {entry, display} <- [{284, 2404}, {14_560, 14_337}, {15_665, 15_960}, {1211, 1_159}] do
      previous = :ets.lookup(CreatureTemplateLoader, entry)

      :ets.insert(
        CreatureTemplateLoader,
        {entry,
         %CreatureTemplate{
           entry: entry,
           display_ids: [display],
           display_scales: [1.0]
         }}
      )

      on_exit(fn ->
        :ets.delete(CreatureTemplateLoader, entry)
        :ets.insert(CreatureTemplateLoader, previous)
      end)
    end

    :ok
  end

  defp character(_context) do
    spells = Map.new([25_858, 25_859], &{&1, SpellLoader.load(&1)})

    %{
      character: %Character{
        object: %Object{guid: 1, scale_x: 1.0, base_scale_x: 1.0},
        unit: %Unit{
          health: 100,
          max_health: 100,
          level: 60,
          auras: [],
          display_id: 49,
          native_display_id: 49
        },
        player: %Player{},
        internal: %Internal{world: %WorldRef{map_id: 0}, spellbook: spells},
        movement_block: struct!(%MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}, MovementBlock.player_speeds())
      }
    }
  end
end
