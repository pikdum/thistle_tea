defmodule ThistleTea.Game.Entity.Server.Mob.PetCommands do
  @moduledoc "Admits attack-stop and aura-cancel requests against a creature's current controller."

  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  def stop_attack(%Mob{} = creature, controller) do
    if controlled?(creature, controller) and not Core.dead?(creature) do
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

      Core.dead?(creature) ->
        Network.send_packet(Message.SmsgPetActionFeedback.new(:pet_dead), controller)
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
