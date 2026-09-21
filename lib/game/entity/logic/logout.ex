defmodule ThistleTea.Game.Entity.Logic.Logout do
  @moduledoc "Logout admission, posture, and temporary movement restrictions."

  import Bitwise, only: [band: 2, bor: 2, bnot: 1]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.MovementSync
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Emote
  alias ThistleTea.Game.Entity.Logic.Rest

  @logging_out 0x04

  def admission(%Character{} = character) do
    cond do
      character.internal.in_combat -> {:error, :failure_in_combat}
      MovementBlock.airborne?(character.movement_block) -> {:error, :failure_jumping_or_falling}
      Aura.has_spell?(character, 9454) -> {:error, :failure_frozen_by_gm}
      Rest.resting?(character) or not is_nil(character.internal.taxi_flight) -> {:ok, :instant}
      true -> {:ok, :delayed}
    end
  end

  def start(%Character{} = character, now) do
    free? = not character.internal.rooted? and not Aura.crowd_controlled?(character) and not Core.dead?(character)
    character = if free? and sit?(character), do: Emote.stand(character, 1, now), else: character
    mode = if free?, do: :rooted, else: :waiting
    player = %{character.player | field_bytes_flags: bor(character.player.field_bytes_flags || 0, @logging_out)}
    character = %{character | player: player, internal: %{character.internal | logout: mode}}
    sync(character, now)
  end

  def cancel(%Character{internal: %Internal{logout: nil}} = character, _now), do: character

  def cancel(%Character{} = character, now) do
    stand? = character.internal.logout == :rooted and character.unit.stand_state == 1 and not Core.dead?(character)
    player = %{character.player | field_bytes_flags: band(character.player.field_bytes_flags || 0, bnot(@logging_out))}
    character = %{character | player: player, internal: %{character.internal | logout: nil}}
    character = if stand?, do: Emote.stand(character, 0, now), else: character
    sync(character, now)
  end

  defp sit?(character) do
    character.unit.stand_state in [nil, 0] and character.unit.mount_display_id in [nil, 0] and
      not MovementBlock.swimming?(character.movement_block) and is_nil(character.internal.movement_start_time)
  end

  defp sync(character, now) do
    {character, events} = MovementSync.sync_movement_state(character, now)
    character |> Effects.enqueue(events) |> Core.mark_broadcast_update()
  end
end
