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

  def build(%__MODULE__{} = packet) do
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

  def add_header(packet) do
    <<opcode()::little-size(8)>> <> packet
  end

  def remove_header(packet) do
    <<_header::little-size(8), packet::binary>> = packet
    packet
  end

  def parse(packet) do
    <<protocol_version::little-size(8), result::little-size(8),
      server_public_key::binary-size(32), generator_length::little-size(8),
      generator::binary-size(generator_length), large_safe_prime_length::little-size(8),
      large_safe_prime::binary-size(large_safe_prime_length), salt::binary-size(32),
      crc_salt::binary-size(16), security_flag::little-size(8), rest::binary>> = packet

    {pin_grid_seed, pin_salt} =
      if security_flag == 1 do
        <<pin_grid_seed::little-size(32), pin_salt::binary-size(16)>> = rest
        {pin_grid_seed, pin_salt}
      else
        {nil, nil}
      end

    {:ok,
     %__MODULE__{
       protocol_version: protocol_version,
       result: result,
       server_public_key: server_public_key,
       generator_length: generator_length,
       generator: generator,
       large_safe_prime_length: large_safe_prime_length,
       large_safe_prime: large_safe_prime,
       salt: salt,
       crc_salt: crc_salt,
       security_flag: security_flag,
       pin_grid_seed: pin_grid_seed,
       pin_salt: pin_salt
     }}
  end

  def parse!(packet) do
    {:ok, parsed} = parse(packet)
    parsed
  end
end
