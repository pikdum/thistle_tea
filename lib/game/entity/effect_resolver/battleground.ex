defmodule ThistleTea.Game.Entity.EffectResolver.Battleground do
  @moduledoc "Captures battleground kill credit, including nearby teammates and their corpses."

  alias ThistleTea.Game.Battleground.CreatureDefeat
  alias ThistleTea.Game.Battleground.Defeat
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.KillReward
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Battleground, as: Catalog
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Battleground, as: BattlegroundSystem
  alias ThistleTea.Game.WorldRef

  def resolve(entity, effect, opts \\ [])

  def resolve(%Character{} = entity, %Effects.PlayerDefeated{} = effect, opts) do
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

  def resolve(
        %Mob{
          internal: %Internal{
            world: %WorldRef{instance_id: instance_id} = world,
            creature: %Internal.Creature{db_guid: db_guid},
            spawn: %Internal.Spawn{incarnation_id: incarnation_id}
          }
        } = entity,
        %Effects.CreatureDefeated{source_guid: source_guid},
        opts
      )
      when is_integer(instance_id) and is_integer(db_guid) and is_integer(incarnation_id) do
    bindings = Keyword.get(opts, :bindings, &Catalog.bindings/3)
    participants = Keyword.get(opts, :participants, &BattlegroundSystem.participants/1)
    metadata = Keyword.get(opts, :metadata, &Metadata.query(&1, [:owner_guid]))

    with [_ | _] = events <- bindings.(world.map_id, :creature, db_guid),
         killer_guid when is_integer(killer_guid) <- KillReward.controlling_player(source_guid, metadata),
         true <- Map.has_key?(participants.(world), killer_guid) do
      defeat = %CreatureDefeat{
        victim_guid: entity.object.guid,
        entry: entity.object.entry,
        db_guid: db_guid,
        incarnation_id: incarnation_id,
        killer_guid: killer_guid,
        bindings: events
      }

      [%Effects.BattlegroundCreatureDeath{world: world, defeat: defeat}]
    else
      _ineligible -> []
    end
  end

  def resolve(%Mob{}, %Effects.CreatureDefeated{}, _opts), do: []

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
