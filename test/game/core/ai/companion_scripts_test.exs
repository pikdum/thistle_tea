defmodule ThistleTea.Game.Core.AI.CompanionScriptsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.AI.AIEvent
  alias ThistleTea.Game.Core.AI.BT
  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.BT.MiniPet
  alias ThistleTea.Game.Core.AI.BT.Pet, as: PetBT
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cast
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Loader.Script, as: ScriptLoader

  setup [:companion]

  describe "Script.execute_steps/5" do
    test "stay stops movement without dropping combat or the current script phase", %{pet: pet, context: context} do
      pet = PetBT.command(pet, :attack, 77, context.now)
      memory = %{Blackboard.new() | event_ai: %{Blackboard.new().event_ai | phase: 3}}
      {stayed, memory} = execute(pet, 0, context, blackboard: memory)
      assert stayed.internal.pet.command_state == :stay
      assert stayed.internal.pet.stay_position == {0.0, 0.0, 0.0}
      refute stayed.internal.pet.attack_command?
      assert stayed.internal.navigation_intents == []
      assert stayed.unit.target == 77
      assert stayed.internal.in_combat
      assert memory.event_ai.phase == 3
      assert memory.pet.returning == nil
    end

    test "follow stops attacking and casting without clearing the combat timer", %{pet: pet, context: context} do
      pet = PetBT.command(pet, :attack, 77, context.now)
      cast = Cast.new(%Spell{id: 10, cast_time_ms: 5_000}, Target.unit(77), context.now)
      pet = %{pet | internal: %{pet.internal | casting: cast}}
      {following, memory} = execute(pet, 1, context)
      assert following.internal.pet.command_state == :follow
      assert following.internal.casting == nil
      assert following.internal.in_combat
      assert following.internal.threat == %{}
      assert following.unit.target in [nil, 0]
      assert memory.pet.returning == :command
      assert Enum.any?(following.internal.events, &is_struct(&1, Effects.AttackStop))
    end

    test "possessed stay and follow leave client movement and combat in place", %{pet: pet, context: context} do
      pet = PetBT.command(pet, :attack, 77, context.now)
      pet = %{pet | internal: %{pet.internal | pet: %{pet.internal.pet | possessed?: true}}}

      for command <- [0, 1] do
        {updated, _} = execute(pet, command, context)
        assert updated.movement_block == pet.movement_block
        assert updated.unit.target == 77
        assert updated.internal.in_combat
        assert updated.internal.events == pet.internal.events
      end
    end

    test "explicit attacks override passive reaction and reject invalid targets", %{pet: pet, context: context} do
      target = Guid.from_low_guid(:mob, 38, 77)
      context = with_target(context, target, %{alive?: true})
      {attacking, _} = execute(pet, 2, context, target: target)
      assert attacking.unit.target == target
      assert attacking.internal.pet.attack_command?
      assert attacking.internal.in_combat

      for {guid, denied} <- [
            {0, context},
            {target + 1, context},
            {target, with_target(context, target, %{alive?: false})},
            {target, with_target(context, target, %{alive?: true, unit_flags: 2})},
            {target, with_target(context, target, %{alive?: true, owner_guid: 1})},
            {target, with_target(context, target, %{alive?: true, transport_guid: 7})},
            {target, with_target(context, target, %{alive?: true}, WorldRef.open(1))},
            {target, put_in(context.perception.entities[1].metadata.unit_flags, 0x20000)}
          ] do
        {unchanged, _} = execute(pet, 2, denied, target: guid)
        assert unchanged == pet
      end
    end

    test "dismiss uses lifecycle effects and preserves hunter pets", %{pet: pet, context: context} do
      for kind <- [:guardian, :mini_pet, :summon, :creature_pet] do
        {removed, _} = execute(with_kind(pet, kind), 3, context)
        assert [%Effects.DespawnSelf{}] = removed.internal.events
      end

      for kind <- [:charmed, :possessed] do
        {released, _} = execute(with_kind(pet, kind), 3, context)

        assert [%Effects.ReleaseControlled{source_guid: 1, target_guid: target, spell_id: 99}] =
                 released.internal.events

        assert target == pet.object.guid
      end

      hunter = with_kind(pet, :hunter)
      assert {^hunter, _} = execute(hunter, 3, context)
    end

    test "missing owners and unknown commands do not abort creature scripts", %{pet: pet, context: context} do
      for {state, command, context} <- [
            {pet, 1, Context.new(context.now)},
            {pet, 4, context},
            {%{pet | internal: %{pet.internal | pet: nil}}, 0, context}
          ] do
        steps = [%ScriptStep{command: :set_command_state, datalong: command, abort_on_failure?: true}, phase(7)]
        {updated, memory} = Script.execute_steps(state, state.internal.blackboard, steps, 0, context)
        assert updated == state
        assert memory.event_ai.phase == 7
      end
    end

    test "non-creature sources honor the abort flag", %{context: context} do
      player = %Character{object: %Object{guid: 1}, internal: %Internal{}}

      for abort? <- [true, false] do
        steps = [%ScriptStep{command: :set_command_state, datalong: 0, abort_on_failure?: abort?}, phase(7)]
        {^player, memory} = Script.execute_steps(player, Blackboard.new(), steps, 0, context)
        assert memory.event_ai.phase == if(abort?, do: 0, else: 7)
      end
    end

    @tag :vmangos_db
    test "loads tracker stay and delayed follow commands", %{pet: pet, context: context} do
      scripts = ScriptLoader.load_by_ids(Mangos.CreatureAiScript, [866_803])
      stay = Enum.find(scripts[866_803], &(&1.command == :set_command_state))
      assert stay.datalong == 0
      {stayed, memory} = Script.execute_steps(pet, Blackboard.new(), [stay], 0, context)
      assert stayed.internal.pet.command_state == :stay
      scripts = ScriptLoader.load_by_ids(Mangos.GenericScript, [866_802])
      follow = Enum.find(scripts[866_802], &(&1.command == :set_command_state))
      assert follow.datalong == 1
      {following, _} = Script.execute_steps(stayed, memory, [follow], 0, context)
      assert following.internal.pet.command_state == :follow
    end
  end

  describe "EventAI.events/1" do
    test "owned guardians and critters retain events while controlled pets suppress them", %{pet: pet, context: context} do
      event = %AIEvent{id: 1, event_type: :spawned, actions: [[phase(7)]]}
      pet = with_events(pet, [event])

      for kind <- [:guardian, :mini_pet, :creature_pet] do
        owned = with_kind(pet, kind)
        assert EventAI.events(owned) == [event]
        {_, memory} = EventAI.on_spawned(owned, Blackboard.new(), context.now, context)
        assert memory.event_ai.phase == 7
      end

      for kind <- [:hunter, :summon, :charmed, :possessed] do
        controlled = with_kind(pet, kind)
        assert EventAI.events(controlled) == []
        {_, memory} = EventAI.on_spawned(controlled, Blackboard.new(), context.now, context)
        assert memory.event_ai.phase == 0
      end

      possessed = %{pet | internal: %{pet.internal | pet: %{pet.internal.pet | possessed?: true}}}
      assert EventAI.events(possessed) == []
    end
  end

  describe "companion trees" do
    test "timed stay commands run before idle following", %{pet: pet, context: context} do
      event = %AIEvent{
        id: 1,
        event_type: :timer_ooc,
        actions: [[%ScriptStep{command: :set_command_state, datalong: 0}]]
      }

      pet = with_events(pet, [event])

      for {kind, tree} <- [{:guardian, PetBT.tree()}, {:creature_pet, PetBT.tree()}, {:mini_pet, MiniPet.tree()}] do
        {_, stayed} = BT.tick(tree, with_kind(pet, kind), context)
        assert stayed.internal.pet.command_state == :stay
        assert stayed.internal.navigation_intents == []
        {_, stayed} = BT.tick(tree, stayed, %{context | now: context.now + 1_000})
        assert stayed.internal.navigation_intents == []
      end
    end

    test "a staying mini-pet still runs events that resume following", %{pet: pet, context: context} do
      event = %AIEvent{
        id: 1,
        event_type: :timer_ooc,
        actions: [[%ScriptStep{command: :set_command_state, datalong: 1}]]
      }

      pet = pet |> with_kind(:mini_pet) |> with_events([event]) |> PetBT.command(:stay, 0, context.now)
      {_, following} = BT.tick(MiniPet.tree(), pet, context)
      assert following.internal.pet.command_state == :follow
      assert length(following.internal.navigation_intents) == 1
    end
  end

  defp companion(_context) do
    pet = %Mob{
      object: %Object{guid: Guid.from_low_guid(:pet, 8668, 1)},
      unit: %Unit{health: 100, max_health: 100, level: 20, bounding_radius: 0.25, flags: 0},
      internal: %Internal{
        world: WorldRef.open(0),
        in_combat: false,
        blackboard: Blackboard.new(),
        pet: %Pet{kind: :guardian, owner_guid: 1, reaction_state: :passive, control_spell_id: 99}
      },
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, run_speed: 7.0}
    }

    owner = %Observation{
      guid: 1,
      position: {pet.internal.world, 10.0, 0.0, 0.0},
      distance: 10.0,
      metadata: %{alive?: true, orientation: 0.0, unit_flags: 0}
    }

    perception = Perception.new(1_000, {pet.internal.world, 0.0, 0.0, 0.0}, %{1 => owner}, %{})
    %{pet: pet, context: Context.new(1_000, perception: perception)}
  end

  defp execute(pet, command, context, opts \\ []) do
    step = %ScriptStep{command: :set_command_state, datalong: command}
    memory = Keyword.get(opts, :blackboard, pet.internal.blackboard)
    Script.execute_steps(pet, memory, [step], Keyword.get(opts, :target, 0), context)
  end

  defp with_kind(pet, kind), do: %{pet | internal: %{pet.internal | pet: %{pet.internal.pet | kind: kind}}}

  defp with_events(pet, events), do: %{pet | internal: %{pet.internal | creature: %Creature{ai_events: events}}}

  defp with_target(context, guid, metadata, world \\ WorldRef.open(0)) do
    observation = %Observation{guid: guid, position: {world, 5.0, 0.0, 0.0}, metadata: metadata}
    %{context | perception: %{context.perception | entities: Map.put(context.perception.entities, guid, observation)}}
  end

  defp phase(value), do: %ScriptStep{command: :set_phase, datalong: value}
end
