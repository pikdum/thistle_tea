defmodule ThistleTea.Game.World.Entity.Player.Emotes do
  @moduledoc """
  Player-owner emote requests, cached definitions, and same-world unit targets.
  """

  alias ThistleTea.Game.Core.Chat.Emote
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Loader.Emote, as: EmoteLoader
  alias ThistleTea.Game.World.Metadata

  def command(%{ready: true, character: %Character{} = character} = state, id) do
    %{state | character: Emote.command(character, id, Time.now())}
  end

  def command(state, _id), do: state

  def text(%{ready: true, character: %Character{} = character} = state, text_id, variation, target_guid) do
    with true <- Emote.allowed?(character),
         %Emote{} = definition <- EmoteLoader.text(text_id) do
      {target_guid, name} = target(character, target_guid)

      character =
        character
        |> Emote.text(definition, Time.now())
        |> Effects.enqueue(%Effects.TextEmote{text_emote: text_id, emote: variation, name: name})

      if Guid.entity_type(target_guid) in [:mob, :pet] do
        Entity.receive_emote(target_guid, character.object.guid, text_id)
      end

      %{state | character: character}
    else
      _ -> state
    end
  end

  def text(state, _text_id, _variation, _target_guid), do: state

  def stand(%{ready: true, character: %Character{} = character} = state, posture) do
    %{state | character: Emote.stand(character, posture, Time.now())}
  end

  def stand(state, _posture), do: state

  defp target(%Character{internal: %{world: world}}, guid) do
    with type when type in [:player, :mob, :pet] <- Guid.entity_type(guid),
         {^world, _x, _y, _z} <- World.position(guid),
         %{name: name} when is_binary(name) <- Metadata.query(guid, [:name]) do
      {guid, name}
    else
      _ -> {0, ""}
    end
  end
end
