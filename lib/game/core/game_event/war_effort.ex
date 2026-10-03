defmodule ThistleTea.Game.Core.GameEvent.WarEffort do
  @moduledoc """
  vmangos `WarEffortEvent`, the hardcoded Ahn'Qiraj War Effort: master event
  84, the Scarab Gong's ten hours of war (85), and the post-war watch (86).

  vmangos walks the effort from material collection through the gong to the
  final battle, then holds it complete. The supported patch's world comes
  after the war: its collection, transition, battle, and gate events fall
  outside the patch range and were never loaded, so the Scarab Wall stays
  open. The effort is therefore always complete here, which in vmangos leaves
  only the post-war event running, bringing Jonathan the Revelator to the
  gong for those who rang it.
  """

  @behaviour ThistleTea.Game.Core.GameEvent.Rule

  alias ThistleTea.Game.Core.GameEvent.Rule

  @war_effort 84
  @gong 85
  @post_war 86

  @impl Rule
  def events, do: [@war_effort, @gong, @post_war]

  @impl Rule
  def active_events(%DateTime{}, _scheduled), do: [@post_war]

  @impl Rule
  def boundaries(%DateTime{}), do: []
end
