defmodule Lunixi.Guards do
  @moduledoc false
  @max 9_223_372_036_854_775_807
  def money?(n),
    do: is_binary(n) and Regex.match?(~r/\A[1-9][0-9]*\z/, n) and String.to_integer(n) <= @max

  def currency?(value), do: is_binary(value) and Regex.match?(~r/^[A-Z]{3}$/, value)

  def header?(value, max),
    do:
      is_binary(value) and byte_size(value) in 1..max and
        Enum.all?(:binary.bin_to_list(value), &(&1 in 33..126))

  def key?(value), do: header?(value, 128) and byte_size(value) >= 16

  def id?(value),
    do:
      is_binary(value) and value not in [".", ".."] and
        Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$/, value)

  def path?(path),
    do:
      is_binary(path) and byte_size(path) <= 4096 and String.starts_with?(path, "/api/v1/") and
        Regex.match?(~r|^[A-Za-z0-9/_~.:-]+$|, path) and not String.contains?(path, "//") and
        not Enum.any?(String.split(path, "/"), &(&1 in [".", ".."])) and
        not (path == "/api/v1/auth" or String.starts_with?(path, "/api/v1/auth/"))
end
