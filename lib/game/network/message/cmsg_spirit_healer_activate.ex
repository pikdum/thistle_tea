defmodule ThistleTea.Game.Network.Message.CmsgSpiritHealerActivate do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SPIRIT_HEALER_ACTIVATE

  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Network.Server
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Visibility

  @restore_percent 0.5

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, character: %Character{} = character} = state) do
    if Death.alive?(character) do
      state
    else
      resurrect(state, character)
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end

  defp resurrect(state, character) do
    now = Time.now()
    World.stop_entity(Corpse.guid_for(state.guid))

    {character, events} = Death.resurrect(character, @restore_percent, now)
    {character, sickness_events} = apply_resurrection_sickness(character, now)
    duration_events = AuraLogic.self_duration_events(character, now)
    character = EventSink.emit(character, events ++ sickness_events ++ duration_events)

    state = Server.maybe_broadcast_update(%{state | character: character})

    Visibility.notify_visibility_changed(state.character)
    Visibility.resync_player(state)
  end

  defp apply_resurrection_sickness(character, now) do
    level = character.unit.level

    with duration_ms when is_integer(duration_ms) <- Death.resurrection_sickness_duration_ms(level),
         %Spell{} = spell <- SpellLoader.load(Death.resurrection_sickness_spell_id()) do
      AuraLogic.apply_spell(character, character.object.guid, level, %{spell | duration_ms: duration_ms}, now)
    else
      _ -> {character, []}
    end
  end
end
