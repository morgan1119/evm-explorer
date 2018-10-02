defmodule BlockScoutWeb.AddressChannel do
  @moduledoc """
  Establishes pub/sub channel for address page live updates.
  """
  use BlockScoutWeb, :channel

  alias Explorer.Chain.Hash
  alias BlockScoutWeb.{InternalTransactionView, AddressView, TransactionView}
  alias Phoenix.View

  intercept(["balance_update", "count", "internal_transaction", "pending_transaction", "transaction"])

  def join("addresses:" <> _address_hash, _params, socket) do
    {:ok, %{}, socket}
  end

  def handle_out(
        "balance_update",
        %{address: address, exchange_rate: exchange_rate},
        socket
      ) do
    Gettext.put_locale(BlockScoutWeb.Gettext, socket.assigns.locale)

    rendered =
      View.render_to_string(
        AddressView,
        "_balance_card.html",
        address: address,
        exchange_rate: exchange_rate
      )

    push(socket, "balance", %{balance: rendered})
    {:noreply, socket}
  end

  def handle_out("count", %{count: count}, socket) do
    Gettext.put_locale(BlockScoutWeb.Gettext, socket.assigns.locale)

    push(socket, "count", %{count: Cldr.Number.to_string!(count, format: "#,###")})

    {:noreply, socket}
  end

  def handle_out("internal_transaction", %{address: address, internal_transaction: internal_transaction}, socket) do
    Gettext.put_locale(BlockScoutWeb.Gettext, socket.assigns.locale)

    rendered_internal_transaction =
      View.render_to_string(
        InternalTransactionView,
        "_tile.html",
        current_address: address,
        internal_transaction: internal_transaction
      )

    push(socket, "internal_transaction", %{
      to_address_hash: to_string(internal_transaction.to_address_hash),
      from_address_hash: to_string(internal_transaction.from_address_hash),
      internal_transaction_html: rendered_internal_transaction
    })

    {:noreply, socket}
  end

  def handle_out("transaction", data, socket), do: handle_transaction(data, socket, "transaction")
  def handle_out("pending_transaction", data, socket), do: handle_transaction(data, socket, "pending_transaction")

  def handle_transaction(%{address: address, transaction: transaction}, socket, event) do
    Gettext.put_locale(BlockScoutWeb.Gettext, socket.assigns.locale)

    rendered =
      View.render_to_string(
        TransactionView,
        "_tile.html",
        current_address: address,
        transaction: transaction
      )

    push(socket, event, %{
      to_address_hash: to_string(transaction.to_address_hash),
      from_address_hash: to_string(transaction.from_address_hash),
      transaction_hash: Hash.to_string(transaction.hash),
      transaction_html: rendered
    })

    {:noreply, socket}
  end
end
