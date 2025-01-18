defmodule WowMessagesEx.Login.CMD_AUTH_LOGON_CHALLENGE_Server do
  # TODO: only enforce some?
  @enforce_keys [
    :protocol_version,
    :result,
    :server_public_key,
    :generator_length,
    :generator,
    :large_safe_prime_length,
    :large_safe_prime,
    :salt,
    :crc_salt,
    :security_flag,
    :pin_grid_seed,
    :pin_salt
  ]
  defstruct @enforce_keys

  def opcode do
    0x00
  end

  def header(%__MODULE__{} = _packet) do
    <<opcode()::little-size(8)>>
  end

  def body(%__MODULE__{} = packet) do
    <<
      packet.protocol_version::little-size(8),
      packet.result::little-size(8),
      packet.server_public_key::binary-size(32),
      packet.generator_length::little-size(8),
      packet.generator::binary-size(packet.generator_length),
      packet.large_safe_prime_length::little-size(8),
      packet.large_safe_prime::binary-size(packet.large_safe_prime_length),
      packet.salt::binary-size(32),
      packet.crc_salt::binary-size(16),
      packet.security_flag::little-size(8)
    >> <>
      if packet.security_flag == 1 do
        # TODO: how to handle enums
        <<packet.pin_grid_seed::little-size(32), packet.pin_salt::binary-size(16)>>
      else
        <<>>
      end
  end

  def packet(%__MODULE__{} = packet) do
    header(packet) <> body(packet)
  end
end
