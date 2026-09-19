defmodule ThistleTea.Game.Entity.EffectResolver.Durability do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.Metadata

  def resolve(entity, effect, opts \\ [])

  def resolve(%Character{} = entity, %Effects.DurabilityDamage{lethal?: true} = effect, _opts) do
    if death_penalty?(entity, effect) do
      [
        %Effects.DurabilityLoss{
          target_guid: entity.object.guid,
          mode: :percent,
          amount: 10,
          scope: :equipped,
          death?: true
        }
      ]
    else
      []
    end
  end

  def resolve(_entity, %Effects.DurabilityDamage{lethal?: true}, _opts), do: []
  def resolve(_entity, %Effects.DurabilityDamage{environmental?: true}, _opts), do: []

  def resolve(entity, %Effects.DurabilityDamage{source_guid: source}, opts) do
    if is_integer(source) and source > 0 and source != entity.object.guid do
      [entity.object.guid, source]
      |> Enum.filter(&player_guid?/1)
      |> Enum.flat_map(&hit_loss(&1, opts))
    else
      []
    end
  end

  defp death_penalty?(entity, effect) do
    not MapTemplate.battleground?(entity.internal.world.map_id) and
      (effect.environmental? or not player_source?(effect.source_guid))
  end

  defp player_source?(guid) when is_integer(guid) and guid > 0 do
    player_guid?(guid) or
      case Metadata.query(guid, [:owner_guid]) do
        %{owner_guid: owner} -> player_guid?(owner)
        _missing -> false
      end
  end

  defp player_source?(_guid), do: false
  defp player_guid?(guid), do: is_integer(guid) and guid > 0 and Guid.entity_type(guid) == :player

  defp hit_loss(guid, opts) do
    roll = Keyword.get(opts, :roll, fn -> :rand.uniform() * 100 end)
    slot = Keyword.get(opts, :slot, fn -> Enum.random(Inventory.slots()) end)

    if roll.() < 0.5,
      do: [%Effects.DurabilityLoss{target_guid: guid, mode: :points, amount: 1, scope: slot.()}],
      else: []
  end
end
