defmodule ThistleTea.Game.Entity.Server.Mob.PetCasting do
  @moduledoc "Admits client spell commands against the creature's current owner, spellbook, and world."

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Request
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob.Spells
  alias ThistleTea.Game.Entity.Server.AIEnvironment
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  def cast(
        %Mob{internal: %Internal{pet: %Pet{owner_guid: controller}}} = state,
        controller,
        spell_id,
        %Target{} = targets
      ) do
    with %{controlled_guid: guid, alive?: alive?} when guid == state.object.guid <- Metadata.get(controller),
         {world, _, _, _} when world == state.internal.world <- World.position(controller),
         %Spell{} = spell <- Map.get(state.internal.spellbook, spell_id),
         false <- Spell.attribute?(spell, :passive) do
      now = Time.now()
      result = if alive?, do: attempt(state, spell, targets, now), else: {:error, :caster_dead}
      complete(state, spell, result, controller, now)
    else
      _invalid -> state
    end
  end

  def cast(state, _controller, _spell_id, _targets), do: state

  defp attempt(state, spell, targets, now) do
    state = World.snapshot_position(state, now)
    context = AIEnvironment.context(state, now, Request.new(List.wrap(Target.unit_guid(targets))))

    Spells.attempt_commanded_cast(
      state,
      Blackboard.ensure(state.internal.blackboard),
      %CreatureSpell{spell_id: spell.id},
      targets,
      context,
      destination_los?: World.line_of_sight?(state, targets.destination_location)
    )
  end

  defp complete(_state, _spell, {:ok, {state, blackboard}}, _controller, _now),
    do: %{state | internal: %{state.internal | blackboard: blackboard}}

  defp complete(state, spell, {:error, reason}, controller, now) do
    Network.send_packet(%Message.SmsgPetCastFailed{spell_id: spell.id, reason: reason}, controller)

    if !Cooldowns.on_cooldown?(state, spell, now) do
      Network.send_packet(%Message.SmsgClearCooldown{spell_id: spell.id, target_guid: state.object.guid}, controller)
    end

    state
  end
end
