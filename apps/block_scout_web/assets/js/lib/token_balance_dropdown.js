import $ from 'jquery'
import { formatAllUsdValues } from './currency'

const tokenBalanceDropdown = (element) => {
  const $element = $(element)
  const $loading = $element.find('[data-loading]')
  const $errorMessage = $element.find('[data-error-message]')
  const apiPath = element.dataset.api_path

  $.get(apiPath)
    .done(response => {
      const responseHtml = formatAllUsdValues($(response))
      $element.html(responseHtml)
    })
    .fail(() => {
      $loading.hide()
      $errorMessage.show()
    })
}

export function loadTokenBalanceDropdown () {
  $('[data-token-balance-dropdown]').each((_index, element) => tokenBalanceDropdown(element))
}
