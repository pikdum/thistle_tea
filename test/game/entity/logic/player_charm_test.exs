defmodule ThistleTea.Game.Entity.Logic.PlayerCharmTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Charm
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Player, as: PlayerBT
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.PlayerCharm
  alias ThistleTea.Game.Entity.Logic.PlayerPossession
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:charmed_player]

  describe "spells/1" do
    test "chooses the highest learned harmful rank and excludes unsuitable abilities", %{character: character} do
      spells = [
        %{fireball() | id: 1, rank: 1},
        %{fireball() | id: 2, rank: 2},
        %{fireball() | id: 3, spell_family: 0},
        %{fireball() | id: 4, attributes: MapSet.new([:passive])},
        %{fireball() | id: 5, attributes: MapSet.new([:do_not_display])},
        %{fireball() | id: 6, attributes: MapSet.new([:no_autocast_ai])},
        %{fireball() | id: 7, aura_interrupt_flags: 2},
        %{fireball() | id: 8, effects: [%Effect{type: :heal, implicit_target_a: :target_ally}]}
      ]

      character = put_in(character.internal.spellbook, Map.new(spells, &{&1.id, &1}))
      assert Enum.map(PlayerCharm.spells(character), & &1.id) == [2]
    end
  end

  describe "tick/3" do
    test "initial casts and movement work with negative monotonic time", %{character: character} do
      context = %{context(character, 20.0) | now: -576_000_000}
      {_status, casting, blackboard} = tick(character, context)
      assert Enum.any?(casting.internal.events, &is_struct(&1, Effects.CharmCast))
      assert blackboard.charm.next_cast_at == context.now + 1_500

      character = put_in(character.unit.power1, 0)
      {_status, moving, blackboard} = tick(character, context)
      assert moving.internal.navigation_intents != []
      assert blackboard.charm.next_move_at == context.now + 500
    end

    test "the player tree gives charm control over ordinary combat", %{character: character} do
      {{:running, 100, :charm}, acting} = BT.tick(PlayerBT.tree(), character, context(character, 20.0))
      assert acting.unit.target == 2
      assert Enum.any?(acting.internal.events, &is_struct(&1, Effects.CharmCast))
    end

    test "casts a learned ability at the controller's enemy without also starting movement", %{character: character} do
      {_status, acting, _blackboard} = tick(character, context(character, 20.0))
      assert acting.unit.target == 2
      assert acting.internal.navigation_intents == []

      assert Enum.any?(acting.internal.events, &match?(%Effects.CharmCast{spell_id: 133, target_guid: 2}, &1))
    end

    test "out of mana casters approach for melee instead of waiting out of range", %{character: character} do
      character = put_in(character.unit.power1, 0)
      {_status, acting, blackboard} = tick(character, context(character, 20.0))
      assert blackboard.charm.melee_fallback?
      assert Enum.map(acting.internal.navigation_intents, & &1.destination) == [{18.5, 0.0, 0.0}]
      refute Enum.any?(acting.internal.events, &is_struct(&1, Effects.CharmCast))
    end

    test "melee attacks use the shared combat path", %{character: character} do
      character = put_in(character.internal.possession.spells, [])
      {_status, acting, blackboard} = tick(character, context(character, 1.0))
      assert blackboard.combat.auto_attacking
      assert Enum.any?(acting.internal.events, &match?(%Effects.DeliverAttack{target_guid: 2}, &1))
    end

    test "retains a valid victim after the controller changes targets", %{character: character} do
      character = put_in(character.unit.target, 2)
      context = context(character, 20.0)
      controller = character.internal.possession.caster_guid
      context = put_in(context.perception.entities[controller].metadata.combat_targets, [])
      {_status, acting, _blackboard} = tick(character, context)
      assert acting.unit.target == 2
    end

    test "never attacks another unit charmed by the same controller", %{character: character} do
      context = context(character, 20.0)
      owner = character.internal.possession.caster_guid
      metadata = Map.put(context.perception.entities[2].metadata, :owner_guid, owner)
      context = put_in(context.perception.entities[2].metadata, metadata)
      {_status, acting, _blackboard} = tick(character, context)
      assert acting.unit.target == 0
      refute Enum.any?(acting.internal.events, &is_struct(&1, Effects.CharmCast))
    end

    test "passive follow and stay commands control navigation", %{character: character} do
      character = PlayerCharm.command(character, :passive, 0, 1_000)
      {_status, following, _blackboard} = tick(character, context(character, 20.0))
      assert following.unit.target == 0
      assert Enum.map(following.internal.navigation_intents, & &1.destination) == [{-8.0, 0.0, 0.0}]

      character = PlayerCharm.command(character, :stay, 0, 1_000)
      {_status, staying, _blackboard} = tick(character, context(character, 20.0))
      assert staying.internal.navigation_intents == []

      character = PlayerCharm.command(character, :attack, 2, 1_000)
      {_status, attacking, _blackboard} = tick(character, context(character, 20.0))
      assert attacking.unit.target == 2
    end

    test "roots prevent navigation while allowing a ranged spell", %{character: character} do
      character = put_in(character.internal.rooted?, true)
      {_status, acting, _blackboard} = tick(character, context(character, 20.0))
      assert acting.internal.navigation_intents == []
      assert Enum.any?(acting.internal.events, &is_struct(&1, Effects.CharmCast))
      character = put_in(character.unit.power1, 0)
      {_status, acting, _blackboard} = tick(character, context(character, 20.0))
      assert acting.internal.navigation_intents == []
    end

    test "stuns suspend the charm AI", %{character: character} do
      stun = %Holder{spell: %Spell{id: 853}, auras: [%AuraData{type: :mod_stun}]}
      character = put_in(character.unit.auras, [stun | character.unit.auras])
      {_status, acting, _blackboard} = tick(character, context(character, 20.0))
      assert acting.unit.target == 0
      assert acting.internal.navigation_intents == []
      refute Enum.any?(acting.internal.events, &is_struct(&1, Effects.CharmCast))
    end
  end

  describe "maintain/3" do
    test "controller death, combat end, and world separation release the charm", %{character: character} do
      controller = character.internal.possession.caster_guid
      context = context(character, 20.0)

      for context <- [
            put_in(context.perception.entities[controller].metadata.alive?, false),
            put_in(context.perception.entities[controller].metadata.in_combat, false),
            put_in(context.perception.entities[controller].position, {WorldRef.open(1), 0.0, 0.0, 0.0}),
            %{
              context
              | perception: %{context.perception | entities: Map.delete(context.perception.entities, controller)}
            }
          ] do
        {:failure, released, blackboard} = Charm.maintain(character, character.internal.blackboard, context)
        assert released.internal.possession == nil
        assert released.unit.auras == []
        assert released.unit.faction_template == 1
        assert released.unit.flags == 8
        assert blackboard.charm == nil
        assert Enum.any?(released.internal.events, &match?(%Effects.ClientControlChanged{allow_movement?: true}, &1))
      end
    end
  end

  describe "sync/2" do
    test "only Chains of Kel'Thuzad activates area charm", %{character: character} do
      {character, _events} = Aura.remove_spells(character, [28_410], 1_000)

      for spell_id <- [26_740, 28_225, 28_410] do
        holder = charm_holder(spell_id)
        {controlled, events} = Aura.transition(character, %Change{holders: [holder], cause: :applied, now: 2_000})
        assert PlayerPossession.charmed?(controlled) == (spell_id == 28_410)
        assert Aura.crowd_controlled?(controlled) == (spell_id == 28_410)
        refute Enum.any?(events, &is_struct(&1, Effects.ControlGranted))
      end
    end

    test "fear expiry cannot restore control while charm remains", %{character: character} do
      fear = %Holder{spell: %Spell{id: 5782}, caster_guid: 2, auras: [%AuraData{type: :mod_fear}]}
      holders = [fear | character.unit.auras]
      {feared, _events} = Aura.transition(character, %Change{holders: holders, cause: :applied, now: 1_000})
      {charmed, events} = Aura.remove_spells(feared, [5782], 2_000)
      assert PlayerPossession.charmed?(charmed)
      refute Enum.any?(events, &match?(%Effects.ClientControlChanged{allow_movement?: true}, &1))
    end
  end

  describe "valid_attack_target?/2" do
    test "an NPC-controlled player attacks former party members without requiring PvP flags", %{character: character} do
      perception = context(character, 20.0).perception
      source = Perception.actor(perception, 1) |> Map.merge(%{group_id: 42, pvp?: false})
      target = Perception.actor(perception, 2) |> Map.merge(%{group_id: 42, pvp?: false})
      assert Hostility.valid_attack_target?(source, target)
      refute Hostility.valid_attack_target?(source, Map.put(target, :owner_guid, source.owner_guid))
    end
  end

  defp tick(character, context), do: Charm.tick(character, character.internal.blackboard, context)

  defp charmed_player(_context) do
    character = %Character{
      object: %Object{guid: 1},
      player: %Player{},
      unit: %Unit{
        class: 8,
        level: 60,
        health: 100,
        max_health: 100,
        power1: 100,
        max_power1: 100,
        faction_template: 1,
        flags: 8,
        auras: [],
        min_damage: 5.0,
        max_damage: 6.0,
        base_attack_time: 2_000
      },
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, run_speed: 7.0},
      internal: %Internal{world: WorldRef.open(999), spellbook: %{133 => fireball()}, blackboard: %Blackboard{}}
    }

    {character, _events} = Aura.transition(character, %Change{holders: [charm_holder(28_410)], cause: :applied, now: 0})
    %{character: put_in(character.internal.events, [])}
  end

  defp charm_holder(id) do
    %Holder{
      spell: %Spell{id: id},
      caster_guid: Guid.from_low_guid(:mob, 1, 1),
      caster_faction_template: 17,
      applied_at: 0,
      expires_at: 60_000,
      negative?: true,
      auras: [%AuraData{type: :aoe_charm}]
    }
  end

  defp fireball do
    %Spell{
      id: 133,
      first_in_chain: 133,
      rank: 1,
      spell_family: 3,
      school: :fire,
      range_yards: 30.0,
      mana_cost: 10,
      power_type: 0,
      cast_time_ms: 1_500,
      effects: [%Effect{type: :school_damage, implicit_target_a: :target_enemy, base_points: 10}]
    }
  end

  defp context(character, target_distance) do
    controller = character.internal.possession.caster_guid
    world = character.internal.world
    enemy = %FactionTemplate{id: 17, faction: 15, faction_group: 8, enemy_group: 1}
    friendly = %FactionTemplate{id: 1, faction: 1, faction_group: 3, friend_group: 2, enemy_group: 12}

    rows = [
      {1, 0.0, %{alive?: true, faction_template: enemy, owner_guid: controller}},
      {controller, -10.0, %{alive?: true, in_combat: true, faction_template: enemy, combat_targets: [2]}},
      {2, target_distance, %{alive?: true, faction_template: friendly, unit_flags: 8}}
    ]

    observations =
      Map.new(rows, fn {guid, x, metadata} ->
        {guid, %Observation{guid: guid, position: {world, x, 0.0, 0.0}, distance: abs(x), metadata: metadata}}
      end)

    Context.new(1_000, perception: Perception.new(1_000, {world, 0.0, 0.0, 0.0}, observations, %{}))
  end
end
