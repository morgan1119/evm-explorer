defmodule Explorer.Chain.Import.Runner do
  @moduledoc """
  Behaviour used by `Explorer.Chain.Import.all/1` to import data into separate tables.
  """

  alias Ecto.Multi

  @type changeset_function_name :: atom
  @type on_conflict :: :nothing | :replace_all | Ecto.Query.t()

  @typedoc """
  Runner-specific options under `c:option_key/0` in all options passed to `c:run/3`.
  """
  @type options :: %{
          required(:params) => [map()],
          optional(:on_conflict) => on_conflict(),
          optional(:timeout) => timeout,
          optional(:with) => changeset_function_name()
        }

  @doc """
  Key in `t:all_options` used by this `Explorer.Chain.Import` behaviour implementation.
  """
  @callback option_key() :: atom()

  @doc """
  Row of markdown table explaining format of `imported` from the module for use in `all/1` docs.
  """
  @callback imported_table_row() :: %{value_type: String.t(), value_description: String.t()}

  @doc """
  The `Ecto.Schema` module that contains the `:changeset` function for validating `options[options_key][:params]`.
  """
  @callback ecto_schema_module() :: module()
  @callback run(Multi.t(), changes_list :: [%{optional(atom()) => term()}], %{optional(atom()) => term()}) :: Multi.t()
  @callback timeout() :: timeout()
end
