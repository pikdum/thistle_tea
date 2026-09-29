defmodule ThistleTea.Game.World.Entity.Mob.PetCommands do
  @moduledoc "Admits attack-stop and aura-cancel requests against a creature's current controller."

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Outbound

  def stop_attack(%Mob{} = creature, controller) do
    if controlled?(creature, controller) and not Entity.dead?(creature) do
      %Engagement.Result{entity: creature} = Engagement.stop_attack(creature)
      creature
    else
      creature
    end
  end

  def cancel_aura(%Mob{internal: %{pet: %Pet{possessed?: false}}} = creature, controller, spell_id) do
    cond do
      not controlled?(creature, controller) ->
        creature

      Entity.dead?(creature) ->
        Outbound.send_packet(Message.SmsgPetActionFeedback.new(:pet_dead), controller)
        creature

      true ->
        {creature, effects} = Aura.remove_spells(creature, [spell_id], Time.now())
        Effects.enqueue(creature, effects)
    end
  end

  def cancel_aura(%Mob{} = creature, _controller, _spell_id), do: creature

  defp controlled?(%Mob{object: %{guid: guid}, internal: %{pet: %Pet{owner_guid: owner}, world: world}}, owner) do
    match?(%{controlled_guid: ^guid}, Metadata.get(owner)) and match?({^world, _, _, _}, World.position(owner))
  end

  defp controlled?(%Mob{}, _controller), do: false
end
