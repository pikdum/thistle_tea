defmodule ThistleTea.Game.Core.Pet.ControlledCombatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.BT.Pet, as: PetBT
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Combat.AttackFeedback
  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Combat.PlayerCombat
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.Internal.Totem
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.Companion, as: Relationship
  alias ThistleTea.Game.Core.Pet.Companion.EntityRef
  alias ThistleTea.Game.Core.Pet.ControlledCombat
  alias ThistleTea.Game.Core.WorldRef

  setup [:entities]

  describe "contact/4" do
    test "commands and threat membership wait for actual contact", %{pet: pet, enemy: enemy} do
      commanded = PetBT.command(pet, :attack, enemy, 1_000)
      referenced = Engagement.gain_threat_ref(pet, enemy, 7, 0)

      for unchanged <- [commanded, referenced] do
        refute Enum.any?(unchanged.internal.events, &is_struct(&1, Effects.ControlledCombatContact))
      end

      for outcome <- [:normal, :miss, :dodge, :parry, :immune] do
        contacted = AttackFeedback.receive(pet, %{victim_guid: enemy, outcome: outcome, damage: 0}, nil, 1_000)

        assert Enum.any?(contacted.internal.events, fn
                 %Effects.ControlledCombatContact{role: :attack, target_guid: 1, opponent_guid: ^enemy, now: 1_000} ->
                   true

                 _ ->
                   false
               end)
      end

      evaded = AttackFeedback.receive(pet, %{victim_guid: enemy, outcome: :evade, damage: 0}, nil, 1_000)
      refute Enum.any?(evaded.internal.events, &is_struct(&1, Effects.ControlledCombatContact))
    end

    test "totems propagate incoming damage contact", %{pet: pet, enemy: enemy} do
      totem = %{pet | internal: %{pet.internal | pet: nil, totem: %Totem{owner_guid: 1}}}
      damaged = Engagement.on_damage(totem, enemy, 1_000)
      assert Enum.any?(damaged.internal.events, &match?(%Effects.ControlledCombatContact{role: :attacked}, &1))
    end

    test "dead creatures, NPC owners and no-owner-threat templates do not propagate", %{pet: pet, enemy: enemy} do
      excluded = [
        %{pet | unit: %{pet.unit | health: 0}},
        %{pet | internal: %{pet.internal | pet: %{pet.internal.pet | owner_guid: enemy}}},
        %{pet | internal: %{pet.internal | creature: %Creature{static_flags2: 0x20}}}
      ]

      for entity <- excluded do
        assert ControlledCombat.contact(entity, enemy, 1_000, :attack) == entity
      end
    end
  end

  describe "receive/3" do
    test "incoming contact starts the owner window without copying pet threat", ctx do
      owner = receive_contact(ctx, :attacked)
      assert owner.internal.in_combat
      assert Bitwise.band(owner.unit.flags, 0x80000) != 0
      assert owner.internal.last_hostile_time == 1_000
      assert owner.internal.threat_refs == nil
      refute Enum.any?(owner.internal.events, &is_struct(&1, Effects.AddThreat))
      assert sync(owner, Context.new(5_999)).internal.in_combat
      refute sync(owner, Context.new(6_000)).internal.in_combat
    end

    test "outgoing contact adds the owner to the opponent with zero threat", ctx do
      owner = receive_contact(ctx, :attack)
      enemy = ctx.enemy
      assert owner.internal.in_combat

      assert Enum.any?(
               owner.internal.events,
               &match?(%Effects.AddThreat{source_guid: 1, target_guid: ^enemy, amount: 0}, &1)
             )
    end

    test "discarded ownership and distant or exempt companions cannot send late contact", ctx do
      removed = %{ctx.owner | internal: %{ctx.owner.internal | companion: Relationship.none()}}
      assert receive_contact(%{ctx | owner: removed}, :attack) == removed

      for fields <- [%{owner_guid: 2}, %{no_owner_threat?: true}] do
        context = change_metadata(ctx.context, ctx.pet.object.guid, fields)
        assert receive_contact(%{ctx | context: context}, :attack) == ctx.owner
      end

      observation = ctx.context.perception.entities[ctx.pet.object.guid]
      moved = %{observation | position: {WorldRef.open(1), 1.0, 0.0, 0.0}}
      context = put_observation(ctx.context, moved)
      assert receive_contact(%{ctx | context: context}, :attack) == ctx.owner
      assert receive_contact(%{ctx | context: Context.new(1_000)}, :attack) == ctx.owner
      dead = %{ctx.owner | unit: %{ctx.owner.unit | health: 0}}
      assert receive_contact(%{ctx | owner: dead}, :attack) == dead
    end

    test "a lethal pet hit still starts the current owner's combat window", ctx do
      context = change_metadata(ctx.context, ctx.pet.object.guid, %{alive?: false})
      assert receive_contact(%{ctx | context: context}, :attacked).internal.in_combat
    end

    test "guardian and totem contact uses their canonical owner slots", ctx do
      guid = ctx.pet.object.guid
      owner = %{ctx.owner | internal: %{ctx.owner.internal | companion: Relationship.none()}}
      guardian = %{owner | internal: %{owner.internal | guardians: %{guid => :active}}}
      totem = %{owner | internal: %{owner.internal | totem_guids: %{1 => guid}}}

      for owner <- [guardian, totem] do
        assert receive_contact(%{ctx | owner: owner}, :attacked).internal.in_combat
        refute ControlledCombat.holds_combat?(owner, ctx.context)
      end
    end

    test "Feign Death suppresses incoming contact and inherited threat, but not outgoing contact", ctx do
      holder = %Holder{auras: [%Aura{type: :feign_death}]}
      owner = %{ctx.owner | unit: %{ctx.owner.unit | auras: [holder]}}
      assert receive_contact(%{ctx | owner: owner}, :attacked) == owner
      attacking = receive_contact(%{ctx | owner: owner}, :attack)
      assert attacking.internal.in_combat
      refute Enum.any?(attacking.internal.events, &is_struct(&1, Effects.AddThreat))
      refute sync(attacking, %{ctx.context | now: 6_000}).internal.in_combat
    end

    test "untargetable owners ignore incoming contact and outgoing threat", ctx do
      owner = %{ctx.owner | unit: %{ctx.owner.unit | flags: 0x2}}
      assert receive_contact(%{ctx | owner: owner}, :attacked) == owner
      attacking = receive_contact(%{ctx | owner: owner}, :attack)
      assert attacking.internal.in_combat
      refute Enum.any?(attacking.internal.events, &is_struct(&1, Effects.AddThreat))
    end
  end

  describe "holds_combat?/2" do
    test "summoned pet references retain combat beyond contact without becoming owner references", ctx do
      owner = receive_contact(ctx, :attacked)
      held = sync(owner, %{ctx.context | now: 20_000})
      assert held.internal.in_combat
      assert held.internal.last_hostile_time == 1_000
      assert held.internal.threat_refs == MapSet.new()

      released = change_metadata(ctx.context, ctx.pet.object.guid, %{threat_refs: MapSet.new()})
      refute sync(held, %{released | now: 20_000}).internal.in_combat
    end

    test "pet removal preserves an overlapping owner threat reference", ctx do
      owner = ctx |> receive_contact(:attacked) |> PlayerCombat.gain_threat_ref(ctx.enemy, 7, 0)
      owner = %{owner | internal: %{owner.internal | companion: Relationship.none()}}
      assert sync(owner, %{ctx.context | now: 20_000}).internal.in_combat
      owner = PlayerCombat.lose_threat_ref(owner, ctx.enemy, 7)
      refute sync(owner, %{ctx.context | now: 20_000}).internal.in_combat
    end

    test "death, removal, replacement and stale enemy references release inherited combat", ctx do
      owner = receive_contact(ctx, :attacked)

      for {guid, fields} <- [
            {ctx.pet.object.guid, %{alive?: false}},
            {ctx.pet.object.guid, %{owner_guid: 2}},
            {ctx.enemy, %{alive?: false}},
            {ctx.enemy, %{incarnation_id: 8}},
            {ctx.enemy, %{in_combat: false}},
            {ctx.enemy, %{evading?: true}}
          ] do
        context = change_metadata(ctx.context, guid, fields)
        refute sync(owner, %{context | now: 20_000}).internal.in_combat
      end

      refute sync(owner, Context.new(20_000)).internal.in_combat

      companion = %{
        owner.internal.companion
        | status: {:active, %EntityRef{guid: Guid.runtime(:pet, 99), entry: 1, spell_id: 1}}
      }

      replaced = %{owner | internal: %{owner.internal | companion: companion}}
      refute sync(replaced, %{ctx.context | now: 20_000}).internal.in_combat
    end

    test "threat membership alone cannot initiate owner combat", ctx do
      refute sync(ctx.owner, ctx.context).internal.in_combat
    end
  end

  defp entities(_context) do
    world = WorldRef.open(0)
    guid = Guid.runtime(:pet, 1)
    enemy = Guid.runtime(:mob, 2)
    companion = %Relationship{kind: :hunter_pet, status: {:active, %EntityRef{guid: guid, entry: 1, spell_id: 1}}}

    owner = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, flags: 0, auras: []},
      internal: %Internal{world: world, companion: companion}
    }

    pet = %Mob{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, flags: 0, auras: []},
      internal: %Internal{world: world, pet: %Pet{kind: :hunter, owner_guid: 1}}
    }

    pet_observation = %Observation{
      guid: guid,
      position: {world, 1.0, 0.0, 0.0},
      metadata: %{owner_guid: 1, alive?: true, threat_refs: MapSet.new([{enemy, 7}])}
    }

    enemy_observation = %Observation{
      guid: enemy,
      position: {world, 2.0, 0.0, 0.0},
      metadata: %{alive?: true, in_combat: true, incarnation_id: 7}
    }

    context =
      Context.new(1_000,
        perception: Perception.new(1_000, nil, %{guid => pet_observation, enemy => enemy_observation}, %{})
      )

    %{owner: owner, pet: pet, enemy: enemy, context: context}
  end

  defp receive_contact(ctx, role) do
    contact = %Effects.ControlledCombatContact{
      target_guid: 1,
      controlled_guid: ctx.pet.object.guid,
      opponent_guid: ctx.enemy,
      role: role,
      now: 1_000
    }

    ControlledCombat.receive(ctx.owner, contact, ctx.context)
  end

  defp sync(owner, context), do: owner |> PlayerCombat.sync(Blackboard.new(), context) |> elem(0)

  defp change_metadata(context, guid, fields) do
    observation = context.perception.entities[guid]
    put_observation(context, %{observation | metadata: Map.merge(observation.metadata, fields)})
  end

  defp put_observation(context, observation) do
    %{
      context
      | perception: %{
          context.perception
          | entities: Map.put(context.perception.entities, observation.guid, observation)
        }
    }
  end
end
