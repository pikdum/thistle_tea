defmodule ThistleTea.Game.Player.SpiritHealer do
  @moduledoc """
  Validates spirit-healer interaction and restores ghosts with resurrection
  sickness and the carried-equipment durability penalty.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Player.Durability
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility

  def activate(%{ready: true, character: %Character{} = character} = state, healer_guid) do
    if valid_healer?(character, healer_guid), do: resurrect(state), else: state
  end

  def activate(state, _healer_guid), do: state

  def valid_healer?(%Character{} = character, healer_guid) do
    with true <- Death.ghost?(character),
         :mob <- Guid.entity_type(healer_guid),
         %{alive?: true, npc_flags: flags} when is_integer(flags) <- Metadata.query(healer_guid, [:alive?, :npc_flags]),
         true <- (flags &&& 0x20) != 0,
         world = character.internal.world,
         {^world, _x, _y, _z} <- World.position(healer_guid),
         distance when is_number(distance) and distance <= 5.0 <- World.distance_between(character, healer_guid) do
      true
    else
      _invalid -> false
    end
  end

  defp resurrect(%{character: character} = state) do
    now = Time.now()
    World.stop_entity(Corpse.guid_for(state.guid))
    {character, events} = Death.resurrect(character, 0.5, now)
    {character, sickness_events} = apply_sickness(character, now)
    character = EventSink.emit(character, events ++ sickness_events)

    state =
      %{state | character: character}
      |> Durability.lose(:percent, 25, :carried)
      |> PlayerServer.maybe_broadcast_update()

    Visibility.notify_visibility_changed(state.character)
    Visibility.resync_player(state)
  end

  defp apply_sickness(character, now) do
    level = character.unit.level

    with duration when is_integer(duration) <- Death.resurrection_sickness_duration_ms(level),
         %Spell{} = spell <- SpellLoader.load(Death.resurrection_sickness_spell_id()) do
      Aura.apply_spell(character, character.object.guid, level, %{spell | duration_ms: duration}, now)
    else
      _missing -> {character, []}
    end
  end
end
