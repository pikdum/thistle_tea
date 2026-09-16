defmodule ThistleTea.Game.Entity.Logic.Aura.ThreatSync do
  @moduledoc """
  Projects temporary threat aura transitions to the player's existing hostile
  references. New enemies acquired while faded do not inherit the reduction.
  """

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Effects

  def events(%Character{internal: %{threat_refs: %MapSet{} = refs}}, previous, current) do
    amount = total(current)

    if total(previous) == amount do
      []
    else
      refs
      |> Enum.sort()
      |> Enum.map(fn {guid, incarnation_id} -> Effects.temporary_threat(guid, incarnation_id, amount) end)
    end
  end

  def events(_entity, _previous, _current), do: []

  defp total(holders) do
    Enum.reduce(holders, 0, fn %Holder{auras: auras, stacks: stacks}, total ->
      Enum.reduce(auras, total, fn
        %Aura{type: :mod_total_threat, amount: amount}, total when is_number(amount) ->
          total + amount * max(stacks || 1, 1)

        _aura, total ->
          total
      end)
    end)
  end
end
