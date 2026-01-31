defmodule ElixDb.Collection do
  @moduledoc """
  Collection struct: named container with fixed vector dimension and distance metric.
  """
  @enforce_keys [:name, :dimension, :distance_metric]
  defstruct [:name, :dimension, :distance_metric]

  @type distance_metric :: :cosine | :dot_product | :l2
  @type t :: %__MODULE__{
          name: String.t(),
          dimension: pos_integer(),
          distance_metric: distance_metric()
        }
end
