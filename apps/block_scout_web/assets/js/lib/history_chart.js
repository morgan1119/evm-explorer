import $ from 'jquery'
import Chart from 'chart.js'
import humps from 'humps'
import numeral from 'numeral'
import { formatUsdValue } from '../lib/currency'
import sassVariables from '../../css/app.scss'

const config = {
  type: 'line',
  responsive: true,
  data: {
    datasets: []
  },
  options: {
    legend: {
      display: false
    },
    scales: {
      xAxes: [{
        gridLines: {
          display: false,
          drawBorder: false
        },
        type: 'time',
        time: {
          unit: 'day',
          stepSize: 14
        },
        ticks: {
          fontColor: sassVariables.dashboardBannerChartAxisFontColor
        }
      }],
      yAxes: [{
        id: 'price',
        gridLines: {
          display: false,
          drawBorder: false
        },
        ticks: {
          beginAtZero: true,
          callback: (value, index, values) => `$${numeral(value).format('0,0.00')}`,
          maxTicksLimit: 4,
          fontColor: sassVariables.dashboardBannerChartAxisFontColor
        }
      }, {
        id: 'marketCap',
        display: false,
        gridLines: {
          display: false,
          drawBorder: false
        },
        ticks: {
          callback: (value, index, values) => '',
          maxTicksLimit: 6,
          drawOnChartArea: false
        }
      }, {
        id: 'numTransactions',
        display: false,
        position: 'right',
        gridLines: {
          display: false,
          drawBorder: false
        },
        ticks: {
          beginAtZero: true,
          callback: (value, index, values) => `${numeral(value).format('0,0')}`,
          maxTicksLimit: 4,
          fontColor: sassVariables.dashboardBannerChartAxisFontColor
        }
      }]
    },
    tooltips: {
      mode: 'index',
      intersect: false,
      callbacks: {
        label: ({datasetIndex, yLabel}, {datasets}) => {
          const label = datasets[datasetIndex].label
          if (datasets[datasetIndex].yAxisID === 'price') {
            return `${label}: ${formatUsdValue(yLabel)}`
          } else if (datasets[datasetIndex].yAxisID === 'marketCap') {
            return `${label}: ${formatUsdValue(yLabel)}`
          } else if (datasets[datasetIndex].yAxisID === 'numTransactions') {
            return `${label}: ${yLabel}`
          } else {
            return yLabel
          }
        }
      }
    }
  }
}

function getPriceData (marketHistoryData) {
  return marketHistoryData.map(({ date, closingPrice }) => ({x: date, y: closingPrice}))
}

function getMarketCapData (marketHistoryData, availableSupply) {
  if (availableSupply !== null && typeof availableSupply === 'object') {
    return marketHistoryData.map(({ date, closingPrice }) => ({x: date, y: closingPrice * availableSupply[date]}))
  } else {
    return marketHistoryData.map(({ date, closingPrice }) => ({x: date, y: closingPrice * availableSupply}))
  }
}

class MarketHistoryChart {
  constructor (el, availableSupply, marketHistoryData, dataConfig) {

    var axes = config.options.scales.yAxes.reduce(function(solution, elem){
      solution[elem.id] = elem
      return solution
    },
                                                  {})

    this.price = {
      label: window.localized['Price'],
      yAxisID: 'price',
      data: [],
      fill: false,
      pointRadius: 0,
      backgroundColor: sassVariables.dashboardLineColorPrice,
      borderColor: sassVariables.dashboardLineColorPrice,
      lineTension: 0
    }
    if (dataConfig.market == undefined || dataConfig.market.indexOf("price") == -1){
      this.price.hidden = true
      axes["price"].display = false
    }

    this.marketCap = {
      label: window.localized['Market Cap'],
      yAxisID: 'marketCap',
      data: [],
      fill: false,
      pointRadius: 0,
      backgroundColor: sassVariables.dashboardLineColorMarket,
      borderColor: sassVariables.dashboardLineColorMarket,
      lineTension: 0
    }
    if (dataConfig.market == undefined || dataConfig.market.indexOf("market_cap") == -1){
      this.marketCap.hidden = true
      axes["marketCap"].display = false
    }

    this.numTransactions = {
      label: window.localized['Tx/day'],
      yAxisID: 'numTransactions',
      data: [],
      fill: false,
      pointRadius: 0,
      backgroundColor: sassVariables.dashboardLineColorMarket,
      borderColor: sassVariables.dashboardLineColorTransactions,
      lineTension: 0,
    }
    if (dataConfig.transactions == undefined || dataConfig.transactions.indexOf("transactions_per_day") == -1){
      this.numTransactions.hidden = true
      axes["numTransactions"].display = false
    }

    this.availableSupply = availableSupply
    //TODO: This is where we dynamically append datasets
    config.data.datasets = [this.price, this.marketCap, this.numTransactions]
    this.chart = new Chart(el, config)
  }
  updateMarketHistory (availableSupply, marketHistoryData) {
    this.price.data = getPriceData(marketHistoryData)
    if (this.availableSupply !== null && typeof this.availableSupply === 'object') {
      const today = new Date().toJSON().slice(0, 10)
      this.availableSupply[today] = availableSupply
      this.marketCap.data = getMarketCapData(marketHistoryData, this.availableSupply)
    } else {
      this.marketCap.data = getMarketCapData(marketHistoryData, availableSupply)
    }
    this.chart.update()
  }
  updateTransactionHistory (transaction_history) {
    this.numTransactions.data = transaction_history.map(dataPoint => {
      return {x:dataPoint.date, y:dataPoint.number_of_transactions}
    })
    this.chart.update()
  }
}

export function createMarketHistoryChart (el) {
  const dataPaths = $(el).data('history_chart_paths')
  const dataConfig = $(el).data('history_chart_config')

  const $chartLoading = $('[data-chart-loading-message]')
  const $chartError = $('[data-chart-error-message]')
  const chart = new MarketHistoryChart(el, 0, [], dataConfig)
  Object.keys(dataPaths).forEach(function(history_source){
    $.getJSON(dataPaths[history_source], {type: 'JSON'})
      .done(data => {
        switch(history_source){
        case "market":
          const availableSupply = JSON.parse(data.supply_data)
          const marketHistoryData = humps.camelizeKeys(JSON.parse(data.history_data))
          $(el).show()
          chart.updateMarketHistory(availableSupply, marketHistoryData)
          break;
        case "transaction":
          const transaction_history = JSON.parse(data.history_data)

          $(el).show()
          chart.updateTransactionHistory(transaction_history)
          break;
        }
      })
      .fail(() => {
        $chartError.show()
      })
      .always(() => {
        $chartLoading.hide()
      })})
  return chart;
}

$('[data-chart-error-message]').on('click', _event => {
  $('[data-chart-loading-message]').show()
  $('[data-chart-error-message]').hide()
  createMarketHistoryChart($('[data-chart="historyChart"]')[0])
})
