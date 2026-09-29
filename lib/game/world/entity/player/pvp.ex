defmodule ThistleTea.Game.World.Entity.Player.Pvp do
  @moduledoc """
  Player-owner boundary for PvP preference and authoritative territory changes.
  """

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Honor.Protection
  alias ThistleTea.Game.Core.Pvp, as: PvpLogic
  alias ThistleTea.Game.Core.Realm
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity.Player, as: PlayerServer
  alias ThistleTea.Game.World.Entity.Player.TickScheduler
  alias ThistleTea.Game.World.Loader.Exploration
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  def toggle(%{ready: true, character: %Character{} = character} = state, desired)
      when desired in [true, false, :toggle] do
    apply_transition(state, PvpLogic.toggle(character, desired, Time.now()))
  end

  def toggle(state, _desired), do: state

  def arrive(state, spell_lookup \\ &SpellLoader.load/1)

  def arrive(%{ready: true, character: %Character{} = character} = state, spell_lookup) do
    if Protection.eligible?(character) do
      character = Protection.apply(character, spell_lookup.(Protection.spell_id()), Time.now())
      apply_transition(state, character)
    else
      state
    end
  end

  def arrive(state, _spell_lookup), do: state

  def update_territory(%{character: %Character{} = character} = state, zone_id, area_id) do
    zone = Exploration.area(zone_id)
    area = Exploration.area(area_id)

    if zone != nil or battleground?(character) do
      character = PvpLogic.territory(character, zone, area, Realm.pvp_rules(), battleground?(character), Time.now())
      apply_transition(state, character)
    else
      state
    end
  end

  defp battleground?(%Character{internal: %{world: %{map_id: map_id}}}), do: map_id in [30, 489, 529]

  defp apply_transition(state, %Character{} = character) do
    CharacterStore.put(character)

    %{state | character: character}
    |> PlayerServer.maybe_broadcast_update()
    |> TickScheduler.ensure_scheduled()
  end
end
