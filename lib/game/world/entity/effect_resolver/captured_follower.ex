defmodule ThistleTea.Game.World.Entity.EffectResolver.CapturedFollower do
  @moduledoc false

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Metadata

  def resolve(%Character{object: %{guid: player}}, %Effects.EnsureCapturedFollower{
        player_guid: player,
        creature_guid: creature
      }) do
    case Metadata.get(creature) do
      %{alive?: true, follow_guid: follower, in_combat: false, evading?: false} when follower != player ->
        [
          %Effects.ForwardScriptSteps{
            target_guid: creature,
            source_guid: player,
            steps: [%ScriptStep{command: :movement, datalong: 15, position: {3.0, 0.0, 0.0, 0.0}}]
          }
        ]

      _unavailable ->
        []
    end
  end

  def resolve(_entity, _effect), do: []
end
