import { createGuestCart, addItemsToGuestCart, setGuestCartAddresses, placeGuestOrder } from './orders.magento'

export type OrderCustomer = {
  email: string
  firstname?: string
  lastname?: string
  phone?: string
  address?: { street?: string, city?: string, postcode?: string, countryId?: string }
}

export type OrderLine = { sku: string, name?: string, qty: number, price?: number }

export async function apiCreateOrder(payload: { customer: OrderCustomer, lines: OrderLine[], notes?: string }) {
  const cartId = await createGuestCart()

  await addItemsToGuestCart(cartId, payload.lines.map(l => ({ sku: l.sku, qty: l.qty })))

  const addr = {
    email: payload.customer.email,
    firstname: payload.customer.firstname || 'N/A',
    lastname: payload.customer.lastname || 'N/A',
    street: [payload.customer.address?.street || 'N/A'],
    city: payload.customer.address?.city || 'N/A',
    postcode: payload.customer.address?.postcode || '0000',
    countryId: payload.customer.address?.countryId || 'NO',
    telephone: payload.customer.phone || '00000000',
  }
  await setGuestCartAddresses(cartId, addr)

  const orderId = await placeGuestOrder(cartId)
  return { id: String(orderId) }
}
