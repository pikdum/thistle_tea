defmodule ThistleTea.Game.Network.Message.CmsgAttackswing do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ATTACKSWING
  use ThistleTea.Game.Network.Opcodes, [:SMSG_ATTACKSTART, :SMSG_ATTACKSTOP]

  alias ThistleTea.DB.Mangos.ItemTemplate
  alias ThistleTea.DB.Mangos.Repo
  alias ThistleTea.Game.Network.Message

  require Logger

  defstruct [:target_guid]

  @impl ClientMessage
  def handle(%__MODULE__{target_guid: target_guid}, state) do
    Logger.info("CMSG_ATTACKSWING: #{target_guid}")

    %Message.SmsgAttackstart{
      attacker: state.guid,
      victim: target_guid
    }
    |> World.broadcast_packet(state.character)

    mainhand_entry = state.character.player.visible_item_16_0
    weapon = Repo.get(ItemTemplate, mainhand_entry)
    attack_speed = weapon.delay

    # use existing timer if already attacking
    attack_timer =
      case Map.fetch(state, :attack_timer) do
        {:ok, timer} -> timer
        :error -> Process.send_after(self(), :attack_swing, attack_speed)
      end

    Map.merge(state, %{attacking: target_guid, attack_timer: attack_timer})
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<target_guid::little-size(64)>> = payload

    %__MODULE__{
      target_guid: target_guid
    }
  end

  def handle_attack_swing(state) do
    case Map.fetch(state, :attacking) do
      {:ok, target_guid} ->
        mainhand_entry = state.character.player.visible_item_16_0
        weapon = Repo.get(ItemTemplate, mainhand_entry)
        %{dmg_min1: min_damage, dmg_max1: max_damage, delay: attack_speed} = weapon

        pid = :ets.lookup_element(:entities, target_guid, 2)
        attack = %{caster: state.guid, min_damage: min_damage, max_damage: max_damage}
        GenServer.cast(pid, {:receive_attack, attack})
        attack_timer = Process.send_after(self(), :attack_swing, attack_speed)
        Map.put(state, :attack_timer, attack_timer)

      :error ->
        state |> Map.delete(:attack_timer)
    end
  end
end
