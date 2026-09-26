// 장바구니: 브라우저(localStorage)에 [{ product_id, quantity }] 형태로 저장한다.
const CART_KEY = "goods-cart";

function getCart() {
  try {
    const items = JSON.parse(localStorage.getItem(CART_KEY) || "[]");
    return Array.isArray(items) ? items : [];
  } catch {
    return [];
  }
}

function saveCart(items) {
  try {
    localStorage.setItem(CART_KEY, JSON.stringify(items));
  } catch {
    // 저장이 막힌 브라우저(사생활 보호 모드 등)에서는 무시
  }
  updateCartBadge();
}

function addToCart(productId, quantity = 1) {
  const items = getCart();
  const found = items.find((i) => i.product_id === productId);
  if (found) found.quantity = Math.min(99, found.quantity + quantity);
  else items.push({ product_id: productId, quantity });
  saveCart(items);
}

function setCartQuantity(productId, quantity) {
  const items = getCart()
    .map((i) => (i.product_id === productId ? { ...i, quantity: Math.max(1, Math.min(99, quantity)) } : i));
  saveCart(items);
}

function removeFromCart(productId) {
  saveCart(getCart().filter((i) => i.product_id !== productId));
}

function clearCart() {
  saveCart([]);
}

function cartCount() {
  return getCart().reduce((sum, i) => sum + i.quantity, 0);
}

function updateCartBadge() {
  const badge = document.getElementById("cart-count");
  if (badge) {
    const n = cartCount();
    badge.textContent = n;
    badge.hidden = n === 0;
  }
}
