defmodule ThistleTea.Game.World.Loader.ConsumableDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.CreatureTemplate
  alias ThistleTea.Game.Entity.EffectResolver
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Effects.RandomChoice
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.CreatureTemplate, as: CreatureTemplateLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellScriptName
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db
  @children [8064, 8065, 8066, 8067, 8068, 8070, 8219, 8220, 8221, 8222, 16_591, 16_593, 16_595]

  setup [:cached_reference_data, :character]

  describe "load/1" do
    test "Noggenfogger outcomes coexist and cancel through ordinary aura projections", %{character: c} do
      {small, _} = consume(c, 16_589, 1, 0)
      assert_in_delta small.object.scale_x, 0.5, 0.0001
      {floating, events} = consume(small, 16_589, 3, 1_000)
      assert Aura.has_aura?(floating, :feather_fall)
      assert Enum.any?(events, &match?(%Effects.FeatherFallChanged{enabled?: true}, &1))
      {skeleton, _} = consume(floating, 16_589, 5, 2_000)
      assert skeleton.unit.display_id == 7550
      assert_in_delta skeleton.object.scale_x, 0.5, 0.0001
      assert Aura.has_aura?(skeleton, :water_breathing)
      assert Enum.sort(Enum.map(skeleton.unit.auras, & &1.spell.id)) == [16_591, 16_593, 16_595]
      {restored, _} = Aura.cancel_spell(skeleton, 16_591, 3_000)
      assert restored.unit.display_id == 49
      refute Aura.has_aura?(restored, :water_breathing)
      assert restored.object.scale_x == 0.5
      {restored, _} = Aura.cancel_spell(restored, 16_595, 4_000)
      assert restored.object.scale_x == 1.0
      {expired, events} = Aura.tick(restored, 121_000)
      assert expired.unit.auras == []
      assert Enum.any?(events, &match?(%Effects.FeatherFallChanged{enabled?: false}, &1))
    end

    test "both costumes project the proper model for both genders and restore the native appearance", %{character: c} do
      for {gender, roll, spell_id, display_id} <- [
            {0, 1, 8219, 4617},
            {0, 2, 8221, 4620},
            {1, 1, 8220, 4618},
            {1, 2, 8222, 4619}
          ] do
        character = %{c | unit: %{c.unit | gender: gender}}
        {costumed, _} = consume(character, 8213, roll, 1_000)
        assert costumed.unit.display_id == display_id
        assert hd(costumed.unit.auras).spell.id == spell_id
        assert hd(costumed.unit.auras).expires_at == 3_601_000
        assert costumed.unit.gender == gender
        {restored, _} = Aura.cancel_spell(costumed, spell_id, 2_000)
        assert restored.unit.display_id == 49
        assert restored.unit.auras == []
      end
    end

    test "raw fish outcomes apply sleep, healing, shrinking, spirit and periodic recovery", %{character: c} do
      {sleepy, _} = consume(c, 8063, 1, 0)
      assert Aura.has_aura?(sleepy, :mod_stun)
      {invigorated, _} = consume(c, 8063, 2, 0)
      assert invigorated.unit.health > c.unit.health
      {small, _} = consume(c, 8063, 3, 0)
      assert_in_delta small.object.scale_x, 0.7, 0.0001
      {healthy, _} = consume(c, 8063, 5, 0)
      assert healthy.unit.spirit == 25
      {rejuvenating, _} = consume(c, 8063, 6, 0)
      assert Aura.has_aura?(rejuvenating, :periodic_heal)
      {healed, _} = Aura.tick(rejuvenating, Aura.next_event_at(rejuvenating))
      assert healed.unit.health > c.unit.health
    end

    test "Party Time compiles the missing periodic interval and emits one animation at ten seconds", %{character: c} do
      spell = SpellLoader.load(8067)
      assert [%Effect{aura: :periodic_emote, amplitude_ms: 10_000} = effect] = spell.effects
      assert Effect.periodic?(effect)
      assert spell.duration_ms == 120_000
      {partying, _} = consume(c, 8063, 4, 0)
      assert Aura.next_event_at(partying) == 10_000
      {_, [%RandomChoice{} = choice]} = Aura.tick(partying, 10_000)
      assert [%Effects.EmoteAnimation{emote_id: id}] = EffectResolver.resolve(partying, choice)
      assert id in [21, 4, 19, 11, 94]
    end
  end

  defp consume(character, spell_id, roll, now) do
    parent = SpellLoader.load(spell_id)
    context = CastContext.from_caster(character, parent, character.object.guid)
    {character, [%RandomChoice{} = choice]} = SpellEffect.receive(character, context, parent, now)
    events = EffectResolver.resolve(character, RandomChoice.select(choice, roll))
    [delivery] = Enum.filter(events, &is_struct(&1, Effects.DeliverSpell))
    assert delivery.target_guid == character.object.guid
    assert delivery.cast_context.triggered?
    SpellEffect.receive(character, delivery.cast_context, delivery.spell, now)
  end

  defp cached_reference_data(_context) do
    for {id, script} <- [
          {8063, "spell_deviate_fish"},
          {8213, "spell_cooked_deviate_fish"},
          {16_589, "spell_noggenfogger_elixir"}
        ] do
      cache(SpellScriptName, id, script)
    end

    for {entry, display} <- [{531, 7550}, {5946, 4617}, {5947, 4618}, {5948, 4619}, {5949, 4620}] do
      cache(CreatureTemplateLoader, entry, %CreatureTemplate{
        entry: entry,
        display_ids: [display],
        display_scales: [1.0]
      })
    end

    :ok
  end

  defp cache(table, key, value) do
    previous = :ets.lookup(table, key)
    :ets.insert(table, {key, value})

    on_exit(fn ->
      :ets.delete(table, key)
      :ets.insert(table, previous)
    end)
  end

  defp character(_context) do
    spells = Map.new(@children, &{&1, SpellLoader.load(&1)})

    %{
      character: %Character{
        object: %Object{guid: 1, scale_x: 1.0, base_scale_x: 1.0},
        unit: %Unit{
          race: 1,
          class: 8,
          gender: 0,
          level: 60,
          health: 100,
          max_health: 1000,
          base_spirit: 20,
          spirit: 20,
          auras: [],
          display_id: 49,
          native_display_id: 49
        },
        player: %Player{},
        internal: %Internal{world: %WorldRef{map_id: 0}, spellbook: spells},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0}
      }
    }
  end
end
