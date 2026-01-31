defmodule ElixDb.Dazo.PredicateMask do
  import Bitwise
  @moduledoc """
  Maps payload and query filter to 8-bit category masks for DAZO predicate-injected edges.

  Config: up to 8 filter fields. Each field is `{key, bit_index, values}` where
  `key` is the payload key (atom or string), `bit_index` is 0..7, and `values` is
  a list or MapSet of values that set this bit. Payload/filter value is normalized
  (string keys checked) before membership.

  - `payload_to_mask(payload, config)` → 0..255. Nil/empty payload → 0.
  - `filter_to_mask(filter, config)` → 0..255. Empty filter → 0 (no predicate pruning).
  - Unknown keys or missing keys → 0 for that bit.
  - Edge pruning: skip neighbor when `(edge_mask &&& query_mask) != query_mask`.
  """

  @max_bits 8

  @type key :: atom() | String.t()
  @type value :: term()
  @type field_config :: {key(), 0..7, [value()] | MapSet.t()}
  @type config :: [field_config()]

  @doc """
  Builds an 8-bit mask from a payload map using the given filter field config.

  Each config entry `{key, bit_index, values}` sets the bit at `bit_index` if
  `payload[key]` or `payload[to_string(key)]` is in `values`. Nil or empty
  payload returns 0. Unknown keys do not set any bit.
  """
  @spec payload_to_mask(payload :: map() | nil, config :: config()) :: 0..255
  def payload_to_mask(payload, config) when is_list(config) do
    if payload == nil or payload == %{} do
      0
    else
      Enum.reduce(config, 0, fn {key, bit_index, values}, acc ->
        raw = get_any_key(payload, key)
        if raw != nil and value_in?(raw, values), do: acc ||| bit(bit_index), else: acc
      end)
    end
  end

  @doc """
  Builds an 8-bit query mask from a filter map using the given filter field config.

  Each config entry sets the bit if the filter contains that key and the filter
  value is in the allowed values. Empty filter returns 0 (no predicate pruning;
  all edges are considered). Keys not in config do not contribute (exact filter
  applied later on candidates).
  """
  @spec filter_to_mask(filter :: map(), config :: config()) :: 0..255
  def filter_to_mask(filter, config) when is_list(config) do
    if filter == nil or map_size(filter) == 0 do
      0
    else
      Enum.reduce(config, 0, fn {key, bit_index, values}, acc ->
        raw = get_any_key(filter, key)
        if raw != nil and value_in?(raw, values), do: acc ||| bit(bit_index), else: acc
      end)
    end
  end

  @doc """
  Returns whether we should follow an edge: neighbor's mask must include all
  bits required by the query mask. When query_mask is 0, all edges are followed.
  """
  @spec edge_matches?(edge_mask :: 0..255, query_mask :: 0..255) :: boolean()
  def edge_matches?(_edge_mask, query_mask) when query_mask == 0, do: true
  def edge_matches?(edge_mask, query_mask), do: (edge_mask &&& query_mask) == query_mask

  @doc """
  Validates config: at most 8 fields, bit indices 0..7, no duplicate bits.
  Returns :ok or {:error, reason}.
  """
  @spec validate_config(config()) :: :ok | {:error, term()}
  def validate_config(config) when not is_list(config), do: {:error, :config_not_list}
  def validate_config(config) when length(config) > @max_bits, do: {:error, :too_many_fields}
  def validate_config(config) do
    bits = Enum.map(config, fn {_k, bit, _v} -> bit end)
    cond do
      Enum.any?(bits, &(&1 < 0 or &1 > 7)) -> {:error, :bit_out_of_range}
      length(bits) != length(Enum.uniq(bits)) -> {:error, :duplicate_bit}
      true -> :ok
    end
  end

  defp bit(i), do: Bitwise.bsl(1, i)

  defp get_any_key(map, key) do
    Map.get(map, key) ||
      Map.get(map, to_string(key)) ||
      (is_binary(key) && safe_atom_get(map, key))
  end

  defp safe_atom_get(map, key) do
    try do
      Map.get(map, String.to_existing_atom(key))
    rescue
      ArgumentError -> nil
    end
  end

  defp value_in?(val, values) when is_list(values), do: val in values
  defp value_in?(val, %MapSet{} = set), do: MapSet.member?(set, val)
  defp value_in?(_, _), do: false
end
