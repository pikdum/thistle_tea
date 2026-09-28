defmodule ThistleTea.Game.Player.Summoning do
  @moduledoc """
  Stores incoming summon requests and accepts a matching unexpired request
  when the Vanilla client responds.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Time

  def request(%{character: %Character{} = character} = state, summoner_guid, zone_id, world, position) do
    if Aura.has_spell?(character, 23_445) do
      state
    else
      auto_decline_ms = 120_000

      pending = %{
        summoner_guid: summoner_guid,
        world: world,
        position: position,
        expires_at: Time.now() + auto_decline_ms
      }

      Network.send_packet(%Message.SmsgSummonRequest{
        summoner_guid: summoner_guid,
        zone_id: zone_id || 0,
        auto_decline_ms: auto_decline_ms
      })

      %{state | character: %{character | internal: %{character.internal | pending_summon: pending}}}
    end
  end

  def accept(%{character: %Character{} = character} = state, summoner_guid) do
    case accept(character, summoner_guid, Time.now()) do
      {character, {world, {x, y, z, orientation}}} ->
        GenServer.cast(self(), {:start_teleport, x, y, z, orientation, world})
        %{state | character: character}

      {character, nil} ->
        %{state | character: character}
    end
  end

  def accept(%Character{internal: internal} = character, summoner_guid, now) do
    case internal.pending_summon do
      %{
        summoner_guid: ^summoner_guid,
        expires_at: expires_at,
        world: world,
        position: {x, y, z}
      }
      when now <= expires_at and character.unit.health > 0 and internal.in_combat != true ->
        {_current_x, _current_y, _current_z, orientation} = character.movement_block.position
        {%{character | internal: %{internal | pending_summon: nil}}, {world, {x, y, z, orientation}}}

      _invalid ->
        {%{character | internal: %{internal | pending_summon: nil}}, nil}
    end
  end
end
