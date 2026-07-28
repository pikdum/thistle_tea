defmodule ThistleTea.Game.Entity.Logic.AutoRepeat do
  @moduledoc """
  Pure lifecycle transitions for player auto-repeat spells.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.Effects

  def cancel(%Character{internal: %Internal{auto_shot: nil}} = character), do: {character, []}

  def cancel(%Character{internal: %Internal{} = internal} = character) do
    character = %{character | internal: %{internal | auto_shot: nil}}
    {character, [Effects.cancel_auto_repeat()]}
  end

  def cancel(entity), do: {entity, []}
end
