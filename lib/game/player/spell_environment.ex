defmodule ThistleTea.Game.Player.SpellEnvironment do
  @moduledoc "Resolves player terrain and reconciles location-dependent spell auras at the owner boundary."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.SpellEnvironment, as: EnvironmentLogic
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.SpellEnvironment, as: TerrainEnvironment

  def restore(%Character{} = character), do: character |> refresh() |> EnvironmentLogic.reconcile(Time.now())

  def reconcile(state, options \\ [])

  def reconcile(%State{character: %Character{movement_block: %MovementBlock{} = movement} = character} = state, options) do
    position = {character.internal.world, movement.position, movement.transport_guid, movement.transport_position}

    character =
      if position == state.spell_environment_position do
        character
      else
        refresh(character, options)
      end

    character = EnvironmentLogic.reconcile(character, Keyword.get_lazy(options, :now, &Time.now/0))
    %{state | character: character, spell_environment_position: position}
  end

  def reconcile(state, _options), do: state

  def refresh(%Character{internal: internal} = character, options \\ []) do
    outdoors = Keyword.get_lazy(options, :outdoors?, fn -> TerrainEnvironment.outdoors(character) end)
    %{character | internal: %{internal | outdoors?: outdoors}}
  end
end
