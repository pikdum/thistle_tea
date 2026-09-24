defmodule ThistleTea.Game.Entity.FeignDeathTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.FeignDeath
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.FeignDeath, as: FeignLogic
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.SpellReception
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  setup [:opponents]

  describe "prepare/5" do
    test "self casts reach owner preparation before applying the aura", ctx do
      character = ctx.character |> Casting.start(ctx.spell, Target.self(ctx.guid), 1_000) |> Casting.complete(1_000)
      assert character.unit.auras == []

      assert %Effects.DeliverSpell{cast_context: context, spell: spell} =
               Enum.find(character.internal.events, &is_struct(&1, Effects.DeliverSpell))

      Metadata.update(ctx.mob, %{no_spell_defense?: true})
      {character, _events} = SpellReception.receive(character, context, spell, 1_000)
      assert FeignLogic.successful?(character)
      refute character.internal.in_combat
    end

    test "one nearby opponent's resistance retains every threat reference", ctx do
      Metadata.update(ctx.mob, %{level: 60})
      context = prepare(ctx, 9_800)
      assert context.feign_death.resisted?
      {character, events} = SpellEffect.receive(ctx.character, context, ctx.spell, 1_000)
      refute FeignLogic.successful?(character)
      assert character.internal.threat_refs == ctx.character.internal.threat_refs
      assert Enum.any?(events, &is_struct(&1, Effects.FeignDeathResisted))
      assert [%Holder{cast_context: %{feign_death: attempt}}] = character.unit.auras
      assert attempt == context.feign_death
    end

    test "rolls the hunter's spell hit against the opponent's level", ctx do
      refute prepare(ctx, 9_599).feign_death.resisted?
      assert prepare(ctx, 9_600).feign_death.resisted?
      Metadata.update(ctx.mob, %{level: 53})
      assert prepare(ctx, 9_000).feign_death.resisted?
    end

    test "ignores distant, stale, dead and player-controlled references", ctx do
      for overrides <- [%{alive?: false}, %{incarnation_id: 2}, %{owner_guid: 7}] do
        Metadata.put(ctx.mob, Map.merge(ctx.metadata, overrides))
        refute prepare(ctx, 9_999).feign_death.resisted?
      end

      Metadata.put(ctx.mob, ctx.metadata)
      SpatialHash.update(:mobs, ctx.mob, ctx.world, 20.01, 0.0, 0.0)
      refute prepare(ctx, 9_999).feign_death.resisted?
      SpatialHash.update(:mobs, ctx.mob, WorldRef.open(1), 0.0, 0.0, 0.0)
      refute prepare(ctx, 9_999).feign_death.resisted?
    end

    test "only checks creatures already on the hunter's hostile reference list", ctx do
      character = %{ctx.character | internal: %{ctx.character.internal | threat_refs: MapSet.new()}}
      refute prepare(%{ctx | character: character}, 9_999).feign_death.resisted?
      Metadata.update(ctx.mob, %{detect_range_modifier: -15})
      SpatialHash.update(:mobs, ctx.mob, ctx.world, 6.0, 0.0, 0.0)
      refute prepare(ctx, 9_999).feign_death.resisted?
    end

    test "snapshots a fighting pet independently of resistance", ctx do
      character = Companion.activate(ctx.character, :hunter_pet, %EntityRef{guid: ctx.pet, entry: 1, spell_id: 1515})
      Metadata.put(ctx.pet, %{alive?: true, in_combat: true, victim_guid: ctx.mob})
      assert prepare(%{ctx | character: character}, 0).feign_death.pet_in_combat?
      Metadata.update(ctx.pet, %{victim_guid: 0})
      refute prepare(%{ctx | character: character}, 0).feign_death.pet_in_combat?
    end

    @tag :dbc_db
    test "uses the real Feign Death and Improved Feign Death ranks", ctx do
      spell = SpellLoader.load(5384)
      ctx = %{ctx | spell: spell}
      assert prepare(ctx, 9_700).feign_death.resisted?

      {rank_one, _} = Aura.apply_spell(ctx.character, ctx.guid, 50, SpellLoader.load(19_286), 0)
      {rank_two, _} = Aura.apply_spell(ctx.character, ctx.guid, 50, SpellLoader.load(19_287), 0)
      refute prepare(%{ctx | character: rank_one}, 9_700).feign_death.resisted?
      assert prepare(%{ctx | character: rank_one}, 9_850).feign_death.resisted?
      refute prepare(%{ctx | character: rank_two}, 9_850).feign_death.resisted?
      assert prepare(%{ctx | character: rank_two}, 9_999).feign_death.resisted?
    end
  end

  defp prepare(ctx, roll) do
    FeignDeath.prepare(ctx.character, %CastContext{caster_guid: ctx.guid, caster_level: 50}, ctx.spell, 1_000,
      roll: roll
    )
  end

  defp opponents(_ctx) do
    guid = System.unique_integer([:positive])
    mob = Guid.from_low_guid(:mob, 1, guid)
    pet = Guid.from_low_guid(:pet, 1, guid)
    world = WorldRef.open(0)
    metadata = %{level: 50, alive?: true, incarnation_id: 1, detection_range: 20.0}
    Metadata.put(mob, metadata)
    SpatialHash.update(:mobs, mob, world, 4.0, 0.0, 0.0)

    on_exit(fn ->
      for actor <- [guid, mob, pet] do
        Metadata.delete(actor)
        SpatialHash.remove(:mobs, actor)
      end
    end)

    character = %Character{
      object: %Object{guid: guid},
      player: %Player{},
      unit: %Unit{level: 50, health: 100, max_health: 100, auras: []},
      internal: %Internal{world: world, in_combat: true, threat_refs: MapSet.new([{mob, 1}])},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    spell = %Spell{
      id: 5384,
      spell_family: 9,
      family_flags_0: 256,
      duration_ms: 360_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :feign_death}]
    }

    %{guid: guid, mob: mob, pet: pet, world: world, metadata: metadata, character: character, spell: spell}
  end
end
