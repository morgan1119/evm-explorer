defmodule BlockScoutWeb.ViewingTransactionsTest do
  @moduledoc false

  use BlockScoutWeb.FeatureCase, async: true

  alias Explorer.Chain.Wei
  alias BlockScoutWeb.{AddressPage, Notifier, TransactionListPage, TransactionLogsPage, TransactionPage}

  setup do
    block =
      insert(:block, %{
        number: 555,
        timestamp: Timex.now() |> Timex.shift(hours: -2),
        gas_used: 123_987
      })

    3
    |> insert_list(:transaction)
    |> with_block()

    pending = insert(:transaction, block_hash: nil, gas: 5891, index: nil)
    pending_contract = insert(:transaction, to_address: nil, block_hash: nil, gas: 5891, index: nil)

    lincoln = insert(:address)
    taft = insert(:address)

    # From Lincoln to Taft.
    txn_from_lincoln =
      :transaction
      |> insert(from_address: lincoln, to_address: taft)
      |> with_block(block)

    transaction =
      :transaction
      |> insert(
        value: Wei.from(Decimal.new(5656), :ether),
        gas: Decimal.new(1_230_000_000_000_123_123),
        gas_price: Decimal.new(7_890_000_000_898_912_300_045),
        input: "0x000012",
        nonce: 99045,
        inserted_at: Timex.parse!("1970-01-01T00:00:18-00:00", "{ISO:Extended}"),
        updated_at: Timex.parse!("1980-01-01T00:00:18-00:00", "{ISO:Extended}"),
        from_address: taft,
        to_address: lincoln
      )
      |> with_block(block, gas_used: Decimal.new(1_230_000_000_000_123_000), status: :ok)

    insert(:log, address: lincoln, index: 0, transaction: transaction)

    internal = insert(:internal_transaction, index: 0, transaction: transaction)

    {:ok,
     %{
       pending: pending,
       pending_contract: pending_contract,
       internal: internal,
       lincoln: lincoln,
       taft: taft,
       transaction: transaction,
       txn_from_lincoln: txn_from_lincoln
     }}
  end

  describe "viewing transaction lists" do
    test "viewing the default transactions tab", %{
      session: session,
      transaction: transaction,
      pending: pending
    } do
      session
      |> TransactionListPage.visit_page()
      |> assert_has(TransactionListPage.transaction(transaction))
      |> assert_has(TransactionListPage.transaction_status(transaction))
      |> refute_has(TransactionListPage.transaction(pending))
    end

    test "viewing the pending tab", %{pending: pending, pending_contract: pending_contract, session: session} do
      session
      |> TransactionListPage.visit_page()
      |> TransactionListPage.click_pending()
      |> assert_has(TransactionListPage.transaction(pending))
      |> assert_has(TransactionListPage.transaction(pending_contract))
      |> assert_has(TransactionListPage.transaction_status(pending_contract))
    end

    test "live update pending transaction", %{session: session} do
      session
      |> TransactionListPage.visit_page()
      |> TransactionListPage.click_pending()

      pending = insert(:transaction)
      Notifier.handle_event({:chain_event, :transactions, [pending.hash]})

      assert_has(session, TransactionListPage.transaction(pending))
    end

    test "live remove collated pending transaction", %{pending: pending, session: session} do
      session
      |> TransactionListPage.visit_page()
      |> TransactionListPage.click_pending()
      |> assert_has(TransactionListPage.transaction(pending))

      transaction = with_block(pending)
      Notifier.handle_event({:chain_event, :transactions, [transaction.hash]})

      refute_has(session, TransactionListPage.transaction(pending))
    end

    test "contract creation is shown for to_address on list page", %{session: session} do
      contract_address = insert(:contract_address)

      transaction =
        :transaction
        |> insert(to_address: nil)
        |> with_block()
        |> with_contract_creation(contract_address)

      :internal_transaction_create
      |> insert(transaction: transaction, index: 0)
      |> with_contract_creation(contract_address)

      session
      |> TransactionListPage.visit_page()
      |> assert_has(TransactionListPage.contract_creation(transaction))
    end
  end

  describe "viewing a pending transaction page" do
    test "can see a pending transaction's details", %{session: session, pending: pending} do
      session
      |> TransactionPage.visit_page(pending)
      |> assert_has(TransactionPage.detail_hash(pending))
      |> assert_has(TransactionPage.is_pending())
    end

    test "pending transactions live update once collated", %{session: session, pending: pending} do
      session
      |> TransactionPage.visit_page(pending)

      transaction = with_block(pending)

      Notifier.handle_event({:chain_event, :transactions, [transaction.hash]})

      session
      |> refute_has(TransactionPage.is_pending())
    end
  end

  describe "viewing a transaction page" do
    test "can navigate to transaction show from list page", %{session: session, transaction: transaction} do
      session
      |> TransactionListPage.visit_page()
      |> TransactionListPage.click_transaction(transaction)
      |> assert_has(TransactionPage.detail_hash(transaction))
    end

    test "can see a transaction's details", %{session: session, transaction: transaction} do
      session
      |> TransactionPage.visit_page(transaction)
      |> assert_has(TransactionPage.detail_hash(transaction))
    end

    test "can view a transaction's logs", %{session: session, transaction: transaction} do
      session
      |> TransactionPage.visit_page(transaction)
      |> TransactionPage.click_logs()
      |> assert_has(TransactionLogsPage.logs(count: 1))
    end

    test "can visit an address from the transaction logs page", %{
      lincoln: lincoln,
      session: session,
      transaction: transaction
    } do
      session
      |> TransactionLogsPage.visit_page(transaction)
      |> TransactionLogsPage.click_address(lincoln)
      |> assert_has(AddressPage.detail_hash(lincoln))
    end
  end
end
