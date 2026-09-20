defmodule ThistleTea.Game.Entity.EffectResolver.Battleground do
  @moduledoc "Captures battleground kill credit, including nearby teammates and their corpses."

  alias ThistleTea.Game.Battleground.Defeat
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.KillReward
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Battleground, as: BattlegroundSystem

  def resolve(%Character{} = entity, %Effects.PlayerDefeated{} = effect, opts \\ []) do
    participants = Keyword.get(opts, :participants, &BattlegroundSystem.participants/1)
    players = participants.(entity.internal.world)

    if Map.has_key?(players, entity.object.guid) do
      metadata = Keyword.get(opts, :metadata, &Metadata.query(&1, [:owner_guid, :alive?]))
      position = Keyword.get(opts, :position, &World.position/1)

      defeat = %Defeat{
        victim_guid: entity.object.guid,
        killer_guid: KillReward.controlling_player(effect.source_guid, metadata),
        position: entity.movement_block.position,
        count_death?: effect.count_death?,
        nearby_guids: Enum.filter(Map.keys(players), &nearby?(entity, &1, position, metadata))
      }

      [%Effects.BattlegroundDeath{world: entity.internal.world, defeat: defeat}]
    else
      []
    end
  end

  defp nearby?(entity, guid, position, metadata) do
    case {position.(guid), metadata.(guid)} do
      {nil, _offline} ->
        false

      {location, %{alive?: false}} ->
        KillReward.in_range?(entity, location) or KillReward.in_range?(entity, position.(Corpse.guid_for(guid)))

      {location, _alive} ->
        KillReward.in_range?(entity, location)
    end
  end
end
